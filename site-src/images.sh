#!/bin/bash
# Makes site/img/ from the app's own demo renders and the store screenshots.
# Needs a build (make build) and cwebp (brew install webp). Run from the repo root.
# The switcher and the profile HUD come from store/screenshots/, which are light only:
# drawing them needs a screen, and --demo has no file output.
set -e
B=build/Build/Products/Release/Monochrome.app/Contents/MacOS/Monochrome
T=$(mktemp -d)
I=site/img
q="-q 84 -quiet"
run() { "$@" > /dev/null 2>&1 & p=$!; for i in $(seq 1 20); do sleep 0.5; kill -0 $p 2>/dev/null || return; done; kill $p 2>/dev/null; }
for m in light dark; do
  d=; [ $m = dark ] && d=dark
  run $B --demo-settings tabs $T/tabs-$m.png $d
  run $B --demo-settings router $T/router-$m.png $d
  run $B --demo-omnibox $T/omnibox-$m.png $d
  cwebp $q $T/tabs-$m.png -o $I/tabs-$m.webp
  cwebp $q $T/router-$m.png -o $I/router-$m.webp
  cwebp $q -crop 0 0 760 680 $T/omnibox-$m.png -o $I/omnibox-$m.webp
done
# The reader: the recipe fixture with the on-device model's summary (macOS 26), title to first paragraph.
node tldr/shots.mjs $T/reader > /dev/null
for m in light dark; do cwebp $q -crop 0 0 1280 690 $T/reader/recipe-1280x800-$m.png -o $I/reader-$m.webp; done
cwebp $q -crop 0 190 1280 420 store/screenshots/1-switcher.jpg -o $I/switcher.webp
cwebp $q -crop 420 290 440 220 store/screenshots/2-profiles.jpg -o $I/profiles.webp
# The touch icon, from the marquee tile's 212-pixel icon.
sips -c 212 212 --cropOffset 173 352 store/screenshots/marquee-tile.jpg --out $T/icon.jpg > /dev/null
sips -s format png -z 180 180 $T/icon.jpg --out $I/icon.png > /dev/null
echo "site/img updated; og.jpg is a 1200x630 shot of site-src/og.html (see README)"
