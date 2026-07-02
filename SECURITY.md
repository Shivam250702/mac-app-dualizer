# Security Policy

## Reporting a vulnerability

If you find a security issue, please **do not open a public issue**. Instead use
GitHub's private vulnerability reporting:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability**.

We'll aim to respond within a few days.

## Scope & notes

This tool copies and re-signs macOS application bundles **locally** on the user's
own machine. It does not transmit data anywhere. Points worth understanding:

- **Ad-hoc code signing.** Clones are re-signed ad-hoc (`codesign --sign -`).
  This is appropriate for locally-built copies but is not a trusted developer
  signature. Don't distribute clones you didn't build yourself, and be cautious
  running clones from untrusted sources.
- **`app.asar` modification.** For Electron apps, the tool injects a small
  snippet that only calls `app.setPath('userData', ...)`. The change is visible
  in `clone-app.sh` and is easy to audit.
- **No elevated privileges.** The tool does not require `sudo`. If a destination
  needs admin rights, that's a macOS filesystem permission, not something this
  tool escalates.

Use only on apps you're licensed to run, and within each app's Terms of Service.
