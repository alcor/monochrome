#!/bin/sh
# Builds Monochrome.app from the Swift here, installs it to ~/Applications, registers it with Chrome
# as the extension's native messaging host, and puts it in the Dock in place of Google Chrome, so
# opening Chrome goes through it and gets its launch flags. Needs the Xcode command
# line tools. Safe to re-run; re-run after moving the repo, since the extension's ID comes from its folder.
#
# Signing: macOS ties the Accessibility grant (for the ⌃Tab tap) to the app's signature. Signed with a
# certificate, that's the team and bundle id and survives rebuilds; ad-hoc signed, it's a hash of the
# binary and every rebuild has to be allowed again in System Settings.
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
name="Monochrome"
build="$here/build/$name.app"
app="$HOME/Applications/$name.app"
bundle_id="local.monochrome"
host="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/monochrome_helper.json"

swiftc --version >/dev/null 2>&1 || { echo "helper: needs the command line tools: xcode-select --install"; exit 1; }
[ -d "/Applications/Google Chrome.app" ] || { echo "Install Google Chrome first: https://www.google.com/chrome/"; exit 1; }

rm -rf "$build"
mkdir -p "$build/Contents/MacOS" "$build/Contents/Resources"
swiftc -O -o "$build/Contents/MacOS/Monochrome" "$here"/*.swift
cp "$here/Info.plist" "$build/Contents/Info.plist"
cp "$here/host.sh" "$build/Contents/Resources/host.sh"
chmod +x "$build/Contents/Resources/host.sh"
# The icon (Monochrome.icon, an Icon Composer document) needs Xcode's actool; with only the command
# line tools the app wears Chrome's icon instead.
if ! xcrun actool "$here/Monochrome.icon" --compile "$build/Contents/Resources" --app-icon Monochrome \
     --output-partial-info-plist /dev/null --platform macosx --minimum-deployment-target 13.0 >/dev/null 2>&1; then
  cp "/Applications/Google Chrome.app/Contents/Resources/app.icns" "$build/Contents/Resources/Monochrome.icns"
  echo "helper: icon not compiled (needs Xcode), using Chrome's"
fi
# A certificate from the keychain, so the Accessibility grant survives rebuilds: MONOCHROME_SIGN_IDENTITY
# if set, else the one used last time (kept in Application Support, since switching certificates
# costs a grant), else a Developer ID, else an Apple Development certificate (fine for this Mac; other
# Macs would need Developer ID), else ad hoc.
support="$HOME/Library/Application Support/$name"
mkdir -p "$support"
identities=$(security find-identity -v -p codesigning 2>/dev/null)
identity=${MONOCHROME_SIGN_IDENTITY:-$(cat "$support/identity" 2>/dev/null || true)}
if [ -n "$identity" ] && ! printf %s "$identities" | grep -qF "\"$identity\""; then
  echo "helper: no certificate named \"$identity\" in the keychain"
  identity=""
fi
[ -n "$identity" ] || identity=$(printf %s "$identities" | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
[ -n "$identity" ] || identity=$(printf %s "$identities" | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
codesign --force --deep --sign "${identity:--}" "$build"
if [ -n "$identity" ]; then
  printf %s "$identity" > "$support/identity"
  echo "helper: built, signed with $identity"
else
  echo "helper: built, signed ad hoc (Accessibility has to be allowed again after each rebuild)"
fi

# Replace the installed copy. A running one is quit first so the new one is what starts. An earlier
# version of the app was called Arc for Chrome; its login item, socket and app go too.
old="$HOME/Applications/Arc for Chrome.app"
if [ -d "$old" ]; then
  osascript -e 'tell application id "local.arc-for-chrome.helper" to quit' >/dev/null 2>&1 || true
  pkill -x ArcHelper 2>/dev/null || true
  "$old/Contents/MacOS/ArcHelper" --unregister 2>/dev/null || true # the binary itself: open would hand off to a running copy
  rm -rf "$old" "$HOME/Library/Application Support/Arc for Chrome"
fi
# By process, not by bundle id: "tell application id ... to quit" resolves the id to the newest bundle,
# the one just built, and launches that copy to quit it, which can leave it running beside the installed one.
pkill -x Monochrome 2>/dev/null || true
sleep 0.5
# Ad hoc, macOS ties the Accessibility grant to the code hash. If the build changed, the old entry is
# dead and toggling it does nothing; clearing it makes the app's one prompt at launch the one that
# counts. Signed with a certificate, the grant follows the signer and bundle id and is left alone.
cdhash() { codesign -dvvv "$1" 2>&1 | sed -n "s/^CDHash=//p"; }
if [ -z "$identity" ] && [ -d "$app" ] && [ "$(cdhash "$app")" != "$(cdhash "$build")" ]; then
  tccutil reset Accessibility "$bundle_id" >/dev/null 2>&1 || true
  echo "helper: the app changed, so macOS will ask for Accessibility again"
fi
mkdir -p "$HOME/Applications"
rm -rf "$app"
cp -R "$build" "$app"

# The extension's ID comes from the public key in its manifest (the first 32 hex digits of the key's
# SHA-256, written with a-p for 0-f), so it is the same unpacked from any folder and from the Web Store.
id=$(python3 -I -c 'import base64, hashlib, json, sys
key = base64.b64decode(json.load(open(sys.argv[1]))["key"])
print("".join(chr(97 + int(c, 16)) for c in hashlib.sha256(key).hexdigest()[:32]))' "$(dirname "$here")/manifest.json")
# The Web Store's copy has the store's ID (store/id); both are allowed, so either copy reaches the helper.
store_id=$(cat "$(dirname "$here")/store/id" 2>/dev/null || true)
mkdir -p "$(dirname "$host")"
python3 -I - "$host" "$app/Contents/Resources/host.sh" "$id" "$store_id" <<'EOF'
import json, sys
host, path, id, store_id = sys.argv[1:]
origins = [f'chrome-extension://{i}/' for i in dict.fromkeys([id, store_id]) if i]
with open(host, 'w') as f:
    json.dump({'name': 'monochrome_helper', 'description': "Monochrome: helper app",
               'path': path, 'type': 'stdio', 'allowed_origins': origins}, f, indent=2)
EOF
rm -f "$(dirname "$host")/erics_arc_player.json" "$(dirname "$host")/erics_arc_helper.json"
echo "helper: registered with Chrome for extension $id${store_id:+ and the store copy $store_id}"

# Dock: swap a pinned Google Chrome icon (which would start Chrome without the flags) for the helper.
dock_bak="$HOME/Library/Preferences/com.apple.dock.plist.pre-monochrome.bak"
[ -e "$dock_bak" ] || cp "$HOME/Library/Preferences/com.apple.dock.plist" "$dock_bak"
# The Dock drops icons for apps macOS hasn't registered yet, and the app was just rebuilt.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
python3 -I - "$name" <<'EOF'
import plistlib, subprocess, sys
name = sys.argv[1]
raw = subprocess.run(['defaults', 'export', 'com.apple.dock', '-'], capture_output=True, check=True).stdout
dock = plistlib.loads(raw)
tiles = dock.get('persistent-apps', [])
keep = [t for t in tiles if t.get('tile-data', {}).get('bundle-identifier') != 'com.google.Chrome'
        and t.get('tile-data', {}).get('file-label') not in ('Chrome Launcher', 'Arc for Chrome', name)]
if len(keep) != len(tiles):
    dock['persistent-apps'] = keep
    subprocess.run(['defaults', 'import', 'com.apple.dock', '-'], input=plistlib.dumps(dock), check=True)
EOF
# defaults quotes a label only when it has spaces.
in_dock() { defaults read com.apple.dock persistent-apps | grep -qE "\"file-label\" = \"?$name\"?;"; }
# A Dock that restarted in the last few seconds writes its old icons back over the change, so wait
# until it has been up a while before each attempt, then check.
wait_for_settled_dock() {
  # etime is [[dd-]hh:]mm:ss; only mm:ss can be under 15 seconds.
  up=$(ps -o etime= -p "$(pgrep -x Dock | head -1)" 2>/dev/null | tr -d ' ' | awk -F: 'NF == 2 { print $1 * 60 + $2; next } { print 999 }')
  [ "${up:-99}" -lt 15 ] && sleep $((15 - up))
  return 0
}
for attempt in 1 2 3 4 5; do
  wait_for_settled_dock
  in_dock || defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$app</string><key>_CFURLStringType</key><integer>0</integer></dict><key>file-label</key><string>$name</string></dict><key>tile-type</key><string>file-tile</string></dict>"
  killall Dock
  sleep 3
  in_dock && break
done
if in_dock; then echo "dock: $name icon in place"; else echo "dock: icon didn't stick; drag $app into the Dock"; fi

open "$app"
echo "installed: $app (allow it under System Settings → Privacy & Security → Accessibility if asked)"
