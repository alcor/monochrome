#!/bin/sh
# Builds Monochrome.app (build.sh), puts it in ~/Applications and opens it. The app does the rest when
# it starts (Install.swift): the native messaging host for each Chrome, the login item, Chrome's App
# Shortcuts, the Dock tile in Chrome's place and the default-browser question. Safe to re-run.
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
name="Monochrome"
build="$here/build/$name.app"
app="$HOME/Applications/$name.app"
bundle_id="local.monochrome"

[ -n "$(ls -d /Applications/Google\ Chrome*.app /Applications/Chromium.app 2>/dev/null)" ] || { echo "Install Google Chrome first: https://www.google.com/chrome/"; exit 1; }
"$here/build.sh"

# By process, not by bundle id: "tell application id ... to quit" resolves the id to the newest bundle,
# the one just built, and launches that copy to quit it, which can leave it running beside the installed one.
pkill -x Monochrome 2>/dev/null || true
sleep 0.5
# Ad hoc, macOS ties the Accessibility grant to the code hash. If the build changed, the old entry is
# dead and toggling it does nothing; clearing it makes the app's one prompt at launch the one that
# counts. Signed with a certificate, the grant follows the signer and bundle id and is left alone.
cdhash() { codesign -dvvv "$1" 2>&1 | sed -n "s/^CDHash=//p"; }
signer() { codesign -dvvv "$1" 2>&1 | sed -n "s/^Authority=//p" | head -1; }
if [ -z "$(signer "$build")" ] && [ -d "$app" ] && [ "$(cdhash "$app")" != "$(cdhash "$build")" ]; then
  tccutil reset Accessibility "$bundle_id" >/dev/null 2>&1 || true
  echo "helper: the app changed, so macOS will ask for Accessibility again"
fi
mkdir -p "$HOME/Applications"
rm -rf "$app"
cp -R "$build" "$app"
open "$app"
echo "installed: $app (allow it under System Settings → Privacy & Security → Accessibility if asked)"
