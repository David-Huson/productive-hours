#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
iconset="$PWD/.build/Worktempo.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/Worktempo.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/Worktempo.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o .build/Worktempo.icns
