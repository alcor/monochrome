#!/bin/sh
# Builds Monochrome.app, installs it to ~/Applications and opens it; the app does the rest of the setup
# itself when it starts (helper/Install.swift). Safe to re-run. The README lists the steps that need
# clicks (Accessibility, loading the extension, its shortcuts).
set -eu
here=$(cd "$(dirname "$0")" && pwd)

"$here/helper/install.sh"

cat <<'EOF'

Monochrome is open and sets itself up: the extension's native messaging host, the login item,
Chrome's App Shortcuts, its Dock tile in Chrome's place, and macOS's question about the default browser.
Continue with step 3 of "Setup" in README.md: allow Monochrome under Accessibility, reopen Chrome from
the Dock, load the extension, set its shortcuts.
EOF
