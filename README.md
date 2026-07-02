# Mac App Dualizer

<p>
  <img alt="platform" src="https://img.shields.io/badge/platform-macOS-000000?logo=apple&logoColor=white" />
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue" />
  <img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-56b877" />
</p>

Run **two independent instances** of a macOS app at the same time — each with its
own data directory and its own login. Great for using two accounts of the same
app (two Claude, Slack, Notion, or Discord logins) side by side.

- **CLI** — `clone-app.sh`, a single self-contained script.
- **GUI** — a small Electron app: drag in an app, name the clone, click **Clone**.

Works best with **Electron apps** (Claude, Slack, Notion, VS Code, Discord,
Figma, …) — which happens to be most of the "only one account per app" apps
people want to double.

> ⚠️ Clone only apps you're licensed to use, and respect each app's Terms of
> Service. This is a tool for legitimate multi-account / multi-profile use on
> your own machine.

---

## Why this exists

This started with a very specific itch: **running more than one Claude desktop
instance — each signed into a different account — on the same Mac.**

The Claude desktop app (which hosts **Claude Code**) supports many parallel
*sessions*, but only **one signed-in account** per install. If you have, say, a
personal account and a work/org account, there's no built-in way to be logged
into both at once.

The usual `open -n -a "Claude"` trick doesn't help either: a second copy shares
the **same data directory**, so it shares the same login and fights over lock
files. To get a *genuinely* separate instance you need a distinct identity, a
separate data directory, matching Electron helper names, and a valid
re-signature. We worked that out by hand for Claude, then generalized it into
this tool so anyone can do it for any app — starting with Claude itself.

See **[Example: two Claude instances](#example-two-claude-instances-different-accounts)** below.

---

## What a real second instance needs

1. A **distinct bundle identifier** and name, so macOS treats it as a separate app.
2. A **separate data directory**, so it stores its own cookies / session / login.
3. A **valid code signature** after those edits (macOS won't launch a bundle
   whose signature no longer matches its contents).
4. *(Electron)* the renamed app's **helper apps renamed to match**, or it won't
   launch.

This tool does all four.

---

## Requirements

- macOS (Apple Silicon or Intel)
- **Xcode Command Line Tools** — for `codesign`: `xcode-select --install`
- **Node.js** (18+) — needed for the data-isolation step on Electron apps
  (provides [`@electron/asar`](https://github.com/electron/asar)) and to run the GUI

---

## Quick start — CLI

```bash
git clone https://github.com/vishalmeena2211/mac-app-dualizer.git
cd mac-app-dualizer
chmod +x clone-app.sh

# Clone any Electron app into a second, independent copy
./clone-app.sh --source "/Applications/Slack.app" --name "Slack Work"

# Launch it
open -a "Slack Work"
```

Its data lives in `~/Library/Application Support/Slack Work`, completely separate
from the original — so you can log into a **different account**.

### Options

| Flag | Meaning |
|------|---------|
| `--source PATH` | The `.app` to clone (required) |
| `--name NAME` | Display name for the clone, e.g. `"Slack Work"` (required) |
| `--dest-dir DIR` | Where to write the clone (default: same folder as the source) |
| `--no-isolate` | Don't inject a separate data directory (Electron only) |
| `--strip-schemes` | Remove the app's custom URL schemes from the clone (see below) |

---

## Quick start — GUI

```bash
npm install
npm start
```

1. **Drag an app** onto the window (or click **Browse**). Its real icon, bundle
   id, and an *Electron / Native* badge appear.
2. Give the clone a name.
3. Click **Clone app**, watch the log, then **Launch clone**.

---

## Example: two Claude instances (different accounts)

```bash
./clone-app.sh --source "/Applications/Claude.app" --name "Claude 2"
open -a "Claude 2"
```

You'll now have the original **Claude** and a second **Claude 2**, each with its
own data directory — so each can be signed into a different account, both running
at once (including separate **Claude Code** sessions).

**Logging the clone into a second account.** Because a magic link only
authenticates the app that opens it, and macOS routes `claude://` deep links to
your *original* app, deliver the login link to the clone explicitly:

```bash
# Fire a magic-link callback straight into the clone
open -a "Claude 2" "claude://magic-link#<token-from-your-login-email>"
```

Or simpler: start the **"Continue with email"** flow *inside the Claude 2
window* — since that instance initiated it, completing the link logs it in.

> Heads-up: keep the clone's `productName` unchanged (the tool does this for
> you). Renaming it makes the web login flow think it's a browser and show the
> marketing site instead of the app sign-in.

---

## How it works

For each clone, the script:

1. **Copies** the bundle with `ditto`.
2. **Rewrites the identity** — a unique `CFBundleIdentifier` (original id +
   a slug of the clone name) and a new `CFBundleName` / `CFBundleDisplayName`.
3. *(Electron)* **Renames the helper apps** in `Contents/Frameworks`
   (`<App> Helper*.app` → `<Clone> Helper*.app`) and their executables, because
   Electron locates helpers by the main app's name.
4. *(Electron)* **Injects an isolated data directory** by prepending a tiny
   snippet to the app's main script inside `app.asar`:
   ```js
   require('electron').app.setPath(
     'userData',
     require('path').join(app.getPath('appData'), '<Clone Name>')
   );
   ```
   It then repacks `app.asar` and, if present, **recomputes the
   `ElectronAsarIntegrity` hash** in `Info.plist`.
   *`productName` is deliberately left unchanged, so the app's user-agent and any
   server-side "is this the desktop app?" detection keep working — important for
   web-based login flows.*
5. **Re-signs** the bundle ad-hoc (`codesign --force --deep --sign -`).
6. **Registers** it with Launch Services (`lsregister -f`).

---

## URL schemes & deep links (e.g. magic-link login)

Many apps register a custom URL scheme (`claude://`, `slack://`) to receive deep
links — including magic-link / SSO login callbacks. Two apps can't both be *the*
default handler for one scheme, so:

- **Keep schemes (default):** the clone also registers the scheme. Target a
  *specific* instance with `open -a "Claude 2" "claude://…"`, which routes to the
  clone regardless of the system default.
- **`--strip-schemes`:** the clone won't touch the original's deep links at all.
  Use this if you only want normal in-app use with zero interference.

---

## Caveats

- **Auto-updates revert the clone.** When the app updates itself it overwrites the
  bundle, wiping the rename/injection/signature. Just re-run the tool afterward —
  the clone's **data directory (your login) is untouched**.
- **Gatekeeper.** Ad-hoc signing is fine for locally-built clones. If you move a
  clone to another Mac, clear quarantine:
  `xattr -dr com.apple.quarantine "/Applications/Claude 2.app"`.
- **Non-Electron apps.** The tool changes the identity (which gives *sandboxed*
  apps a fresh container) but can't guarantee data isolation for arbitrary native
  apps.
- **Not affiliated** with Anthropic or any app you clone. Use responsibly and
  within each app's license and Terms of Service.

---

## Uninstall a clone

```bash
rm -rf "/Applications/Claude 2.app"
rm -rf "$HOME/Library/Application Support/Claude 2"
```

---

## Contributing

Issues and PRs are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Good first
areas: broader native-app support, an `electron-builder` packaged `.app`, and
testing against more Electron apps.

## License

MIT — see [LICENSE](LICENSE).
