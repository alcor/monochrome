#!/bin/sh
# The extension alone, zipped for the Chrome Web Store: dist/store/monochrome-extension-<version>.zip. The files are
# the ones store/files lists, which the Xcode project's run script also copies into the app; the helper app, tests, docs and scripts stay out. The store refuses a manifest with a `key` field, so the package's
# manifest has it removed; the store assigns the key, and store/adopt-key.sh brings it back here so
# the unpacked extension and the store's share one ID.
set -e
cd "$(dirname "$0")/.."
version=$(python3 -c 'import json; print(json.load(open("manifest.json"))["version"])')
# Its own folder: make release runs generate_appcast over dist/, which reads every zip there as an app.
mkdir -p dist/store
out="dist/store/monochrome-extension-$version.zip"
rm -f "$out"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/icons"
python3 - "$stage/manifest.json" <<'EOF'
import json, sys
m = json.load(open('manifest.json'))
m.pop('key', None)
with open(sys.argv[1], 'w') as f:
    json.dump(m, f, ensure_ascii=False, indent=2)
    f.write('\n')
EOF
grep -v '^manifest.json$' store/files | while read -r f; do cp "$f" "$stage/$f"; done
(cd "$stage" && zip -q -X -r "$OLDPWD/$out" .)
unzip -l "$out" | tail -1
echo "$out"
