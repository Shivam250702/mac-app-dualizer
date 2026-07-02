# Mac App Dualizer

Run **two independent instances** of a macOS app at the same time — each with its
own data directory and its own login. Perfect for using two accounts of the same
app (e.g. two Claude, Slack, Notion, or Discord logins) side by side.

Works best with **Electron apps** (Claude, Slack, Notion, VS Code, Discord,
Figma, …), which is most of the "one login per app" apps people want to double.

- **CLI** — `clone-app.sh`, a single self-contained script.
- **GUI** — a small Electron app: pick an app, name the clone, click **Clone**.

> ⚠️ Clone only apps you're licensed to use, and respect each app's Terms of
> Service. This tool is for legitimate multi-account / multi-profile use on your
> own machine.

---

## Why a plain second copy isn't enough

`open -n -a "Some App"` can sometimes start a second process, but both copies
share the **same data directory** (`~/Library/Application Support/<App>`), so they
share one login and often fight over lock files. To get a *real* second instance
you need three things:

1. A **distinct bundle identifier** and name, so macOS treats it as a separate app.
2. A **separate data directory**, so it stores its own cookies / session / login.
3. A **valid code signature** after those edits (macOS refuses to launch a bundle
   whose signature no longer matches its contents).

For Electron apps there's a fourth: the renamed app must have its **helper apps
renamed to match**, or it won't launch.

This tool does all of that.

---

## Requirements

- macOS (Apple Silicon or Intel)
- **Xcode Command Line Tools** — for `codesign`: `xcode-select --install`
- **Node.js** (18+) — only needed for the data-isolation step on Electron apps
  (provides [`@electron/asar`](https://github.com/electron/asar))

---

## Quick start — CLI

```bash
git clone <your-repo-url> mac-app-dualizer
cd mac-app-dualizer
chmod +x clone-app.sh

# Clone Claude into a second, independent "Claude 2"
./clone-app.sh --source "/Applications/Claude.app" --name "Claude 2"

# Launch it
open -a "Claude 2"
```

Its data lives in `~/Library/Application Support/Claude 2`, completely separate
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

1. Click **Browse…** and choose an app from `/Applications`.
2. Give the clone a name.
3. Click **Clone app**, watch the log, then **Launch clone**.

---

## How it works

For each clone, the script:

1. **Copies** the bundle with `ditto`.
2. **Rewrites the identity** — a unique `CFBundleIdentifier` (original id +
   a slug of the clone name) and a new `CFBundleName` / `CFBundleDisplayName`.
3. **(Electron)** **Renames the helper apps** in `Contents/Frameworks`
   (`<App> Helper*.app` → `<Clone> Helper*.app`) and their executables, because
   Electron locates helpers by the main app's name.
4. **(Electron)** **Injects an isolated data directory** by prepending a tiny
   snippet to the app's main script inside `app.asar`:
   ```js
   require('electron').app.setPath(
     'userData',
     require('path').join(app.getPath('appData'), '<Clone Name>')
   );
   ```
   It then repacks `app.asar` and, if present, **recomputes the
   `ElectronAsarIntegrity` hash** in `Info.plist`.
   *Note: `productName` is deliberately left unchanged, so the app's user-agent
   and any server-side "is this the desktop app?" detection keep working — this
   matters for web-based login flows.*
5. **Re-signs** the bundle ad-hoc (`codesign --force --deep --sign -`).
6. **Registers** it with Launch Services (`lsregister -f`).

---

## URL schemes & deep links (e.g. magic-link login)

Many apps register a custom URL scheme (like `claude://`, `slack://`) to receive
deep links — including **magic-link / SSO login callbacks**. Two apps can't both
be *the* default handler for one scheme, so:

- **Keep schemes (default):** the clone also registers the scheme. Deliver a deep
  link to a *specific* instance with:
  ```bash
  open -a "Claude 2" "claude://…"
  ```
  This targets the clone regardless of which app is the system default, so a
  magic link lands in the right instance and the right data directory.

- **`--strip-schemes`:** the clone won't touch the original's deep links at all.
  Use this if you only care about normal in-app use and want zero interference.

**Tip for magic-link logins:** start the login flow *inside the clone's own
window* (e.g. “Continue with email”). Because the clone initiated it, completing
the link logs that instance in.

---

## Caveats

- **Auto-updates revert the clone.** When the app updates itself it overwrites the
  bundle, wiping the rename/injection/signature. Just re-run the tool afterward.
  (The clone's data directory is untouched, so your login survives.)
- **Gatekeeper.** Ad-hoc signing is fine for locally-built clones. If you move a
  clone to another Mac you may need to clear quarantine:
  `xattr -dr com.apple.quarantine "/Applications/Claude 2.app"`.
- **Non-Electron apps.** The tool changes the identity (which gives *sandboxed*
  apps a fresh container) but can't guarantee data isolation for arbitrary native
  apps.
- **Not affiliated** with any of the apps you clone. Use responsibly and within
  each app's license and Terms of Service.

---

## Uninstall a clone

```bash
# Remove the app and its data
rm -rf "/Applications/Claude 2.app"
rm -rf "$HOME/Library/Application Support/Claude 2"
```

---

## License

MIT — see [LICENSE](LICENSE).
