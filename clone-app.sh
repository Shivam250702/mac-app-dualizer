#!/usr/bin/env bash
#
# clone-app.sh — Clone a macOS app so you can run a second, fully independent
# instance (its own data directory, its own login).
#
# Best support: Electron apps (Slack, Claude, Notion, VS Code, Discord, ...).
# Native apps: bundle id / name are changed (helps sandboxed apps get a fresh
# container) but data isolation is not guaranteed.
#
# Usage:
#   ./clone-app.sh --source "/Applications/Claude.app" --name "Claude 2"
#
# Options:
#   --source PATH        Path to the .app to clone (required)
#   --name NAME          Display name for the clone, e.g. "Claude 2" (required)
#   --dest-dir DIR       Where to write the clone (default: same dir as source)
#   --no-isolate         Do NOT inject a separate data directory (Electron only)
#   --strip-schemes      Remove the app's custom URL schemes from the clone
#                        (prevents it from competing for deep links like foo://)
#   -h, --help           Show this help
#
# Requires: macOS, Xcode Command Line Tools (codesign), and Node/npx
# (only needed for the --isolate step on Electron apps; provides @electron/asar).
#
set -euo pipefail

SOURCE=""
CLONE_NAME=""
DEST_DIR=""
ISOLATE=1
STRIP_SCHEMES=0

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)        SOURCE="${2:-}"; shift 2;;
    --name)          CLONE_NAME="${2:-}"; shift 2;;
    --dest-dir)      DEST_DIR="${2:-}"; shift 2;;
    --no-isolate)    ISOLATE=0; shift;;
    --strip-schemes) STRIP_SCHEMES=1; shift;;
    -h|--help)       usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1;;
  esac
done

[[ -n "$SOURCE" && -n "$CLONE_NAME" ]] || { echo "error: --source and --name are required" >&2; usage; exit 1; }
[[ -d "$SOURCE" ]] || { echo "error: source app not found: $SOURCE" >&2; exit 1; }
case "$CLONE_NAME" in *\'*|*\"*|*\\*) echo "error: clone name must not contain quotes or backslashes" >&2; exit 1;; esac
command -v codesign >/dev/null 2>&1 || { echo "error: codesign not found — install Xcode Command Line Tools (xcode-select --install)" >&2; exit 1; }

PB=/usr/libexec/PlistBuddy
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
SRC_PLIST="$SOURCE/Contents/Info.plist"

ORIG_NAME="$("$PB" -c 'Print :CFBundleName' "$SRC_PLIST" 2>/dev/null || basename "$SOURCE" .app)"
ORIG_ID="$("$PB" -c 'Print :CFBundleIdentifier' "$SRC_PLIST")"
[[ -n "$DEST_DIR" ]] || DEST_DIR="$(dirname "$SOURCE")"
DEST="$DEST_DIR/$CLONE_NAME.app"

[[ -e "$DEST" ]] && { echo "error: destination already exists: $DEST" >&2; exit 1; }

# slug for a unique bundle identifier, e.g. "Claude 2" -> "claude-2"
SLUG="$(printf '%s' "$CLONE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')"
NEW_ID="${ORIG_ID}.${SLUG}"

NODE_OK=1; command -v npx >/dev/null 2>&1 || NODE_OK=0

echo "Cloning '$ORIG_NAME'  ->  '$CLONE_NAME'"
echo "  source : $SOURCE"
echo "  dest   : $DEST"
echo "  id     : $NEW_ID"
echo

echo "[1/7] Copying app bundle..."
ditto "$SOURCE" "$DEST"

DEST_PLIST="$DEST/Contents/Info.plist"

echo "[2/7] Setting new identity (bundle id + name)..."
"$PB" -c "Set :CFBundleIdentifier $NEW_ID" "$DEST_PLIST"
"$PB" -c "Set :CFBundleName $CLONE_NAME" "$DEST_PLIST" 2>/dev/null || true
if "$PB" -c "Print :CFBundleDisplayName" "$DEST_PLIST" >/dev/null 2>&1; then
  "$PB" -c "Set :CFBundleDisplayName $CLONE_NAME" "$DEST_PLIST"
else
  "$PB" -c "Add :CFBundleDisplayName string $CLONE_NAME" "$DEST_PLIST" 2>/dev/null || true
fi

if [[ "$STRIP_SCHEMES" -eq 1 ]]; then
  "$PB" -c "Delete :CFBundleURLTypes" "$DEST_PLIST" 2>/dev/null && echo "      custom URL schemes removed" || true
fi

ASAR="$DEST/Contents/Resources/app.asar"
if [[ -f "$ASAR" ]]; then
  echo "[3/7] Electron app detected."

  # --- Rename helper apps so the framework can find them ---------------------
  # Electron looks for "<AppName> Helper*.app"; since we renamed the app, the
  # helpers must be renamed to match or the clone will refuse to launch.
  FW="$DEST/Contents/Frameworks"
  if [[ -d "$FW" ]]; then
    echo "[4/7] Renaming Electron helper apps..."
    while IFS= read -r -d '' happ; do
      base="$(basename "$happ")"        # "Claude Helper (GPU).app"
      suffix="${base#* Helper}"          # " (GPU).app"
      suffix="${suffix%.app}"            # " (GPU)"
      newbase="$CLONE_NAME Helper$suffix"
      newapp="$FW/$newbase.app"
      mv "$happ" "$newapp"
      hplist="$newapp/Contents/Info.plist"
      oldexec="$("$PB" -c 'Print :CFBundleExecutable' "$hplist" 2>/dev/null || true)"
      if [[ -n "$oldexec" && -f "$newapp/Contents/MacOS/$oldexec" ]]; then
        mv "$newapp/Contents/MacOS/$oldexec" "$newapp/Contents/MacOS/$newbase"
        "$PB" -c "Set :CFBundleExecutable $newbase" "$hplist"
      fi
      "$PB" -c "Set :CFBundleName $newbase" "$hplist" 2>/dev/null || true
      hid="$("$PB" -c 'Print :CFBundleIdentifier' "$hplist" 2>/dev/null || true)"
      [[ -n "$hid" ]] && "$PB" -c "Set :CFBundleIdentifier ${hid}.${SLUG}" "$hplist" 2>/dev/null || true
    done < <(find "$FW" -maxdepth 1 -name "* Helper*.app" -print0)
  fi

  # --- Inject an isolated data directory -------------------------------------
  if [[ "$ISOLATE" -eq 1 ]]; then
    if [[ "$NODE_OK" -eq 0 ]]; then
      echo "      ! Node/npx not found; skipping data isolation."
      echo "        (Install Node.js so @electron/asar is available, then re-run.)"
    else
      echo "[5/7] Injecting isolated data directory..."
      WORK="$(mktemp -d)"
      trap 'rm -rf "$WORK"' EXIT
      npx --yes @electron/asar extract "$ASAR" "$WORK/app" >/dev/null
      ENTRY="$(node -e 'const p=require(process.argv[1]+"/package.json");process.stdout.write(p.main||"index.js")' "$WORK/app")"
      ENTRY_FILE="$WORK/app/$ENTRY"
      if [[ -f "$ENTRY_FILE" ]]; then
        # This snippet runs first in the main process and redirects userData to
        # ~/Library/Application Support/<CloneName>. It does NOT touch
        # productName, so the app's user-agent / server-side detection is
        # unchanged (important for web-login flows).
        SNIPPET=";(function(){try{var e=require('electron'),p=require('path');var a=e.app||e;var d='$CLONE_NAME';a.setPath('userData',p.join(a.getPath('appData'),d));try{a.setAppLogsPath(p.join(a.getPath('appData'),d,'Logs'));}catch(_){}}catch(_){}})();"
        printf '%s\n' "$SNIPPET" | cat - "$ENTRY_FILE" > "$ENTRY_FILE.tmp" && mv "$ENTRY_FILE.tmp" "$ENTRY_FILE"

        rm -f "$ASAR"; rm -rf "$DEST/Contents/Resources/app.asar.unpacked"
        npx --yes @electron/asar pack "$WORK/app" "$ASAR" --unpack "{*.node,*.dylib,spawn-helper}" >/dev/null

        # Newer Electron enforces an asar integrity hash in Info.plist. If the
        # key exists, recompute it for our repacked archive.
        if "$PB" -c "Print :ElectronAsarIntegrity:Resources/app.asar:hash" "$DEST_PLIST" >/dev/null 2>&1; then
          HASH="$(npx --yes -p @electron/asar node -e 'const a=require("@electron/asar"),c=require("crypto");const r=a.getRawHeader(process.argv[1]);process.stdout.write(c.createHash("sha256").update(r.headerString).digest("hex"))' "$ASAR" 2>/dev/null || true)"
          if [[ -n "$HASH" ]]; then
            "$PB" -c "Set :ElectronAsarIntegrity:Resources/app.asar:hash $HASH" "$DEST_PLIST"
            echo "      asar integrity hash updated"
          else
            echo "      ! could not recompute integrity hash; app may fail to launch"
          fi
        fi
      else
        echo "      ! could not locate entry file ($ENTRY); skipping isolation"
      fi
      rm -rf "$WORK"; trap - EXIT
    fi
  else
    echo "[5/7] Data isolation skipped (--no-isolate)."
  fi
else
  echo "[3/7] Not an Electron app — changed identity only."
  echo "      Sandboxed apps will get a fresh container; other apps may share data."
fi

echo "[6/7] Re-signing (ad-hoc)..."
codesign --force --deep --sign - "$DEST" 2>/dev/null
codesign --verify "$DEST" && echo "      signature OK"

echo "[7/7] Registering with Launch Services..."
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

echo
echo "Done."
echo "Launch:  open -a \"$CLONE_NAME\""
if [[ -f "$ASAR" && "$ISOLATE" -eq 1 ]]; then
  echo "Data:    ~/Library/Application Support/$CLONE_NAME"
fi
