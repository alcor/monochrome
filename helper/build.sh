#!/bin/sh
# Builds helper/build/Monochrome.app from the Swift here and signs it. Installs nothing: the app does
# its own install when it is opened (Install.swift). Needs the Xcode command line tools.
#
# Signing: macOS ties the Accessibility grant (for the ⌃Tab tap) to the app's signature. Signed with a
# certificate, that's the team and bundle id and survives rebuilds; ad-hoc signed, it's a hash of the
# binary and every rebuild has to be allowed again in System Settings.
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
name="Monochrome"
build="$here/build/$name.app"

swiftc --version >/dev/null 2>&1 || { echo "helper: needs the command line tools: xcode-select --install"; exit 1; }

# Sparkle, for updates from the appcast (sparkle.sh fetches it once).
sparkle=$("$here/sparkle.sh")

rm -rf "$build"
mkdir -p "$build/Contents/MacOS" "$build/Contents/Resources" "$build/Contents/Frameworks"
swiftc -O -F "$sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$build/Contents/MacOS/Monochrome" "$here"/*.swift
cp -R "$sparkle/Sparkle.framework" "$build/Contents/Frameworks/"
cp "$here/Info.plist" "$build/Contents/Info.plist"
cp "$here/host.sh" "$build/Contents/Resources/host.sh"
chmod +x "$build/Contents/Resources/host.sh"

# The extension itself, for a Load unpacked from the app's Extension tab. The manifest keeps its key, so
# this copy has the ID the host is registered for, the same as a clone's.
root=$(dirname "$here")
extension="$build/Contents/Resources/extension"
mkdir -p "$extension/icons"
while read -r f; do cp "$root/$f" "$extension/$f"; done < "$root/store/files"

# The extension IDs the app registers its native messaging host for: the unpacked extension's, which
# is the first 32 hex digits of the SHA-256 of the manifest's public key written with a-p for 0-f (the
# same from any folder), and the Web Store's (store/id).
python3 -I - "$(dirname "$here")" "$build/Contents/Info.plist" <<'EOF'
import base64, hashlib, json, os, plistlib, sys
root, plist = sys.argv[1:]
key = base64.b64decode(json.load(open(os.path.join(root, 'manifest.json')))['key'])
ids = [''.join(chr(97 + int(c, 16)) for c in hashlib.sha256(key).hexdigest()[:32])]
store = os.path.join(root, 'store/id')
if os.path.exists(store):
    ids.append(open(store).read().strip())
info = plistlib.load(open(plist, 'rb'))
info['MonochromeExtensionIDs'] = list(dict.fromkeys(i for i in ids if i))
plistlib.dump(info, open(plist, 'wb'))
print('helper: extension IDs', ', '.join(info['MonochromeExtensionIDs']))
EOF

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
# Sparkle's updater and XPC services are signed first, each on its own, as its documentation asks.
for nested in Autoupdate Updater.app XPCServices/Downloader.xpc XPCServices/Installer.xpc; do
  codesign --force --sign "${identity:--}" -o runtime "$build/Contents/Frameworks/Sparkle.framework/Versions/B/$nested"
done
codesign --force --sign "${identity:--}" -o runtime "$build/Contents/Frameworks/Sparkle.framework"
codesign --force --deep --sign "${identity:--}" "$build"
if [ -n "$identity" ]; then
  printf %s "$identity" > "$support/identity"
  echo "helper: built, signed with $identity"
else
  echo "helper: built, signed ad hoc (Accessibility has to be allowed again after each rebuild)"
fi
echo "$build"
