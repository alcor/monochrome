#!/bin/sh
# After the first upload the Chrome Web Store assigns the extension its key and ID. Install the store's
# copy once in any profile, then run this: it finds that copy's manifest in Chrome's profile folders,
# copies its `key` into this manifest, and rebuilds and reinstalls the helper so it registers for the ID, so the unpacked
# extension loaded from this folder has the store's ID from then on.
#   store/adopt-key.sh <extension id from the dashboard>
set -e
cd "$(dirname "$0")/.."
id=$1
[ -n "$id" ] || { echo "usage: store/adopt-key.sh <extension id>"; exit 1; }
manifest=$(ls -d "$HOME/Library/Application Support/Google/Chrome"/*/Extensions/"$id"/*/manifest.json 2>/dev/null | head -1)
[ -n "$manifest" ] || { echo "no installed copy of $id found under Chrome's profiles; install it from the store first"; exit 1; }
python3 - "$manifest" <<'EOF'
import json, sys, collections
store = json.load(open(sys.argv[1]))
key = store['key']
m = json.load(open('manifest.json'), object_pairs_hook=collections.OrderedDict)
m['key'] = key
with open('manifest.json', 'w') as f:
    json.dump(m, f, ensure_ascii=False, indent=2)
    f.write('\n')
print('manifest.json: key adopted from', sys.argv[1])
EOF
make install
