#!/bin/sh
# Prints the folder holding Sparkle.framework and its tools, fetching the release once into the user's
# caches and checking it against the release's SHA-256. build.sh links the framework; release.sh runs
# generate_appcast from bin/.
set -eu
version=2.10.1
sha=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
dir="$HOME/Library/Caches/Monochrome/Sparkle-$version"
if [ ! -d "$dir/Sparkle.framework" ]; then
  archive=$(mktemp -d)/Sparkle.tar.xz
  curl -sSL -o "$archive" "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" >&2
  [ "$(shasum -a 256 "$archive" | cut -d' ' -f1)" = "$sha" ] || { echo "sparkle: the download does not match the checksum pinned here" >&2; exit 1; }
  mkdir -p "$dir" && tar -xJf "$archive" -C "$dir"
  rm -f "$archive"
fi
echo "$dir"
