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
#   --tint "#RRGGBB"     Badge color for the clone icon (default: auto from name)
#   --no-tint            Do not add a distinguishing badge to the clone icon
#   -h, --help           Show this help
#
# Requires: macOS, Xcode Command Line Tools (codesign), and Node/npx (for the
# data-isolation, icon-badge, and registry steps).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$SCRIPT_DIR/src/asar-tools.js"   # dependency-free asar/Info.plist helpers (Node built-ins only)

SOURCE=""
CLONE_NAME=""
DEST_DIR=""
ISOLATE=1
STRIP_SCHEMES=0
TINT=""
DO_TINT=1
WORK=""

usage() { awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; }   # the comment block above

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)        SOURCE="${2:-}"; shift 2;;
    --name)          CLONE_NAME="${2:-}"; shift 2;;
    --dest-dir)      DEST_DIR="${2:-}"; shift 2;;
    --no-isolate)    ISOLATE=0; shift;;
    --strip-schemes) STRIP_SCHEMES=1; shift;;
    --tint)          TINT="${2:-}"; shift 2;;
    --no-tint)       DO_TINT=0; shift;;
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

SLUG="$(printf '%s' "$CLONE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')"
NEW_ID="${ORIG_ID}.${SLUG}"

NODE_OK=1
if ! command -v node >/dev/null 2>&1 || ! command -v npx >/dev/null 2>&1; then NODE_OK=0; fi

# Pick a deterministic badge color from the clone name if none was given.
if [[ "$DO_TINT" -eq 1 && -z "$TINT" ]]; then
  PALETTE=(d97757 4f8ef7 56b877 e5686a b06ff2 e0a83b 2bb3c0 e267a5)
  H="$(printf '%s' "$CLONE_NAME" | cksum | cut -d' ' -f1)"
  TINT="#${PALETTE[$(( H % ${#PALETTE[@]} ))]}"
fi

# Clean up a half-written clone (and any scratch dir) if we fail partway through.
cleanup_fail() {
  [[ -n "$WORK" && -d "$WORK" ]] && rm -rf "$WORK"
  [[ -e "$DEST" ]] && rm -rf "$DEST"
  return 0
}
trap 'cleanup_fail' ERR
die() { echo "error: $*" >&2; cleanup_fail; exit 1; }

echo "Cloning '$ORIG_NAME'  ->  '$CLONE_NAME'"
echo "  source : $SOURCE"
echo "  dest   : $DEST"
echo "  id     : $NEW_ID"
[[ "$DO_TINT" -eq 1 ]] && echo "  tint   : $TINT"
echo

echo "[1/8] Copying app bundle..."
ditto "$SOURCE" "$DEST"

DEST_PLIST="$DEST/Contents/Info.plist"

echo "[2/8] Setting new identity (bundle id + name)..."
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
  echo "[3/8] Electron app detected."

  FW="$DEST/Contents/Frameworks"
  if [[ -d "$FW" ]]; then
    echo "[4/8] Renaming Electron helper apps..."
    while IFS= read -r -d '' happ; do
      base="$(basename "$happ")"
      suffix="${base#* Helper}"; suffix="${suffix%.app}"
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

  if [[ "$ISOLATE" -eq 1 ]]; then
    if [[ "$NODE_OK" -eq 0 ]]; then
      echo "      ! Node/npx not found; skipping data isolation."
    else
      echo "[5/8] Injecting isolated data directory..."
      [[ -f "$TOOLS" ]] || die "helper not found: $TOOLS (run clone-app.sh from a full checkout of mac-app-dualizer)"
      WORK="$(mktemp -d)"

      # Files the app keeps *outside* the archive (app.asar.unpacked): native modules and
      # helper binaries can't be loaded or spawned from inside an asar, so the repacked
      # clone must reproduce exactly the same layout as the original.
      ORIG_UNPACK="$(node "$TOOLS" unpack-glob "$ASAR" "$WORK/app")"
      ORIG_UNPACK_DIR="$(node "$TOOLS" unpack-dir-glob "$ASAR")"

      npx --yes @electron/asar extract "$ASAR" "$WORK/app" >/dev/null
      node "$TOOLS" inject "$WORK/app" "$CLONE_NAME" | sed 's/^/      /' \
        || die "could not inject the data-isolation snippet (see above); re-run with --no-isolate to clone without a separate data directory"

      rm -f "$ASAR"; rm -rf "$DEST/Contents/Resources/app.asar.unpacked"
      if [[ -n "$ORIG_UNPACK" ]]; then
        PACK_ARGS=(--unpack "$ORIG_UNPACK")
      else
        PACK_ARGS=(--unpack "{*.node,*.dylib,spawn-helper}")   # nothing was unpacked; keep natives loadable anyway
      fi
      [[ -n "$ORIG_UNPACK_DIR" ]] && PACK_ARGS+=(--unpack-dir "$ORIG_UNPACK_DIR")
      npx --yes @electron/asar pack "$WORK/app" "$ASAR" "${PACK_ARGS[@]}" >/dev/null
      if [[ -n "$ORIG_UNPACK" ]]; then
        node "$TOOLS" verify-unpacked "$SOURCE/Contents/Resources/app.asar" "$ASAR" | sed 's/^/      /' \
          || die "the repacked app.asar does not keep the original app.asar.unpacked layout"
      fi
      # asar extract/pack write unpacked files as 0644, so spawn-helper, bundled MCP
      # servers and native addons would lose their executable bit: restore the modes.
      if [[ -d "$SOURCE/Contents/Resources/app.asar.unpacked" ]]; then
        node "$TOOLS" sync-unpacked-modes "$SOURCE/Contents/Resources/app.asar.unpacked" "$DEST/Contents/Resources/app.asar.unpacked" | sed 's/^/      /' \
          || die "could not restore permissions on app.asar.unpacked files"
      fi

      # Apps built with Electron's EnableEmbeddedAsarIntegrityValidation fuse (Claude is
      # one) compare app.asar against the hash stored in Info.plist at startup and abort
      # with EXC_BREAKPOINT on a mismatch, so the hash MUST be recomputed for the new
      # archive. asar-tools does this with Node built-ins only, so it works from a bare
      # git clone (no `npm install`) — the old `npx -p @electron/asar node -e 'require(…)'`
      # approach silently failed there and produced clones that crashed on launch (#1).
      node "$TOOLS" update-integrity "$DEST" | sed 's/^/      /' \
        || die "could not update the ElectronAsarIntegrity hash; the clone would crash on launch"

      rm -rf "$WORK"; WORK=""
    fi
  else
    echo "[5/8] Data isolation skipped (--no-isolate)."
  fi
else
  echo "[3/8] Not an Electron app — changed identity only."
  echo "      Sandboxed apps get a fresh container; other apps may share data."
fi

# --- Distinct icon badge -----------------------------------------------------
if [[ "$DO_TINT" -eq 1 ]]; then
  echo "[6/8] Badging clone icon ($TINT)..."
  if [[ "$NODE_OK" -eq 0 ]] || ! command -v iconutil >/dev/null 2>&1; then
    echo "      ! need Node + iconutil; skipping icon badge"
  else
    ICON_KEY="$("$PB" -c 'Print :CFBundleIconFile' "$DEST_PLIST" 2>/dev/null || true)"
    ICON_FILE=""
    if [[ -n "$ICON_KEY" ]]; then
      [[ "$ICON_KEY" == *.icns ]] && ICON_FILE="$DEST/Contents/Resources/$ICON_KEY" || ICON_FILE="$DEST/Contents/Resources/$ICON_KEY.icns"
    fi
    if [[ -f "$ICON_FILE" ]]; then
      ISET="$(mktemp -d)/icon.iconset"
      if iconutil --convert iconset --output "$ISET" "$ICON_FILE" >/dev/null 2>&1; then
        npx --yes -p pngjs node "$SCRIPT_DIR/src/iconbadge.js" --dir "$ISET" --color "$TINT" || echo "      ! badge step failed; keeping original icon"
        iconutil --convert icns --output "$ICON_FILE" "$ISET" >/dev/null 2>&1 && echo "      icon updated" || echo "      ! could not rebuild icns; keeping original"
      else
        echo "      ! could not expand icns; keeping original icon"
      fi
      rm -rf "$(dirname "$ISET")"
    else
      echo "      ! icon file not found; skipping badge"
    fi
  fi
fi

echo "[7/8] Re-signing (ad-hoc)..."
codesign --force --deep --sign - "$DEST" 2>/dev/null || die "codesign failed"
codesign --verify "$DEST" || die "code signature verification failed"
echo "      signature OK"
if [[ -f "$ASAR" && "$NODE_OK" -eq 1 && -f "$TOOLS" ]]; then
  # Final self-check: a stale ElectronAsarIntegrity hash means an instant crash on launch.
  node "$TOOLS" check-integrity "$DEST" | sed 's/^/      /' \
    || die "asar integrity check failed; the clone would crash on launch"
fi

echo "[8/8] Registering with Launch Services..."
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
touch "$DEST" 2>/dev/null || true

# Record in the registry so `dualize list/remove/repair` can manage it.
if [[ "$NODE_OK" -eq 1 && -f "$SCRIPT_DIR/src/registry.js" ]]; then
  node "$SCRIPT_DIR/src/registry.js" add \
    --name "$CLONE_NAME" --source "$SOURCE" --dest "$DEST" \
    --isolate "$ISOLATE" --strip "$STRIP_SCHEMES" --tint "$TINT" 2>/dev/null || true
fi

trap - ERR
echo
echo "Done."
echo "Launch:  open -a \"$CLONE_NAME\""
if [[ -f "$ASAR" && "$ISOLATE" -eq 1 ]]; then
  echo "Data:    ~/Library/Application Support/$CLONE_NAME"
fi
