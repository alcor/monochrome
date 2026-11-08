#!/bin/sh
# The extension alone, zipped for the Chrome Web Store: dist/monochrome-extension-<version>.zip. The helper app,
# tests, docs and scripts stay out. The store refuses a manifest with a `key` field, so the package's
# manifest has it removed; the store assigns the key, and store/adopt-key.sh brings it back here so
# the unpacked extension and the store's share one ID.
set -e
cd "$(dirname "$0")/.."
version=$(python3 -c 'import json; print(json.load(open("manifest.json"))["version"])')
mkdir -p dist
out="dist/monochrome-extension-$version.zip"
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
cp options.html options.js mini-browser.html \
  background.js helper.js mini-browser.js mini-browser-bar.js mini-browser-page.js routes.js player.js \
  peek-click.js peek-open.js music.js music-relay.js "$stage/"
cp icons/16.png icons/32.png icons/48.png icons/128.png "$stage/icons/"
(cd "$stage" && zip -q -X -r "$OLDPWD/$out" .)
unzip -l "$out" | tail -1
echo "$out"
