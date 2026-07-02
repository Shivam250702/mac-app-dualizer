# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- **Distinct clone icons** — clones get an auto-colored badge (deterministic from
  the name, or `--tint "#RRGGBB"` / `--no-tint`) so instances are easy to tell
  apart in the Dock and Cmd-Tab.
- **Clone registry** — every clone is recorded in
  `~/.config/mac-app-dualizer/clones.json`.
- **`dualize` subcommands** — `list`, `repair` / `repair --all`, and
  `remove [--purge]`, in addition to `clone`.
- **Repair after auto-update** — `dualize repair` re-applies the patch (keeping
  the clone's data directory / login) when an app update reverts the clone.
- **Rollback on failure** — a failed clone cleans up its half-written bundle.
- **CI** — GitHub Actions running shellcheck + `node --check` + package.json
  validation.
- Issue/PR templates, `SECURITY.md`, and this changelog.

## [1.0.0]

### Added
- Initial release: `clone-app.sh` CLI and Electron GUI to clone a macOS app into
  a second, independent instance (own identity, data directory, re-signed bundle,
  renamed Electron helpers).
