#!/bin/sh
# A release: helper/release.sh <version>. Sets the version in the app's Info.plist (both fields; Sparkle
# compares CFBundleVersion) and the extension's manifest, builds, zips the app into dist/, and writes
# appcast.xml for Sparkle, signed with the EdDSA key in the keychain (generate_keys made it; the public
# half is SUPublicEDKey in Info.plist). It prints the commands that publish, since those are the
# irreversible part: the GitHub release the appcast points at, and the commit that carries the appcast.
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
root=$(dirname "$here")
version=${1:?usage: helper/release.sh <version>}
cd "$root"
plutil -replace CFBundleShortVersionString -string "$version" helper/Info.plist
plutil -replace CFBundleVersion -string "$version" helper/Info.plist
python3 - "$version" <<'PY'
import json, sys
m = json.load(open('manifest.json'))
m['version'] = sys.argv[1]
with open('manifest.json', 'w') as f:
    json.dump(m, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
"$here/build.sh"
mkdir -p dist
zip="dist/Monochrome-app-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent helper/build/Monochrome.app "$zip"
sparkle=$("$here/sparkle.sh")
"$sparkle/bin/generate_appcast" --download-url-prefix "https://github.com/arfct/monochrome/releases/download/v$version/" \
  --link "https://github.com/arfct/monochrome/releases" -o appcast.xml dist
echo
echo "built $zip and appcast.xml. To publish:"
echo "  gh release create v$version $zip --title \"Monochrome $version\" --notes \"...\""
echo "  git commit -am \"Release $version\" && git push"
echo "The app checks the appcast on main, so the release must exist before that push lands."
