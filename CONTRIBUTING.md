# Contributing to Mac App Dualizer

Thanks for your interest! This project is small and welcomes contributions.

## Ground rules

- This tool is for **legitimate multi-account / multi-profile use on your own
  machine**. Please don't propose features aimed at circumventing licensing,
  DRM, or an app's Terms of Service.
- Keep it **macOS-native and dependency-light**. The CLI should stay runnable
  with just macOS + Xcode CLT + Node.

## Getting set up

```bash
git clone https://github.com/vishalmeena2211/mac-app-dualizer.git
cd mac-app-dualizer
npm install        # for the GUI
npm start          # launch the Electron GUI
```

Test the CLI against a low-stakes Electron app first (e.g. Slack), not a
critical one.

## Before opening a PR

- Shell: `bash -n clone-app.sh` must pass.
- JS: `node --check` each file under `src/` and `bin/`.
- Describe **what app you tested against** and your macOS + chip
  (Apple Silicon / Intel) in the PR.
- Keep changes focused; one topic per PR.

## Ideas / roadmap

- Broader **non-Electron** app support (per-app data isolation strategies).
- Package the GUI as a distributable `.app` via `electron-builder`.
- A `--list` / uninstall helper for managing existing clones.
- Detect and warn when a cloned app has been reverted by an auto-update.

## Reporting bugs

Open an issue with:

- the exact command or GUI steps,
- the target app + version,
- macOS version and chip,
- the full log output.
