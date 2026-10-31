#!/bin/bash
# Renders banner.html into docs/assets/banner.jpg (2560×1280): the README banner and the GitHub
# social preview. Needs Google Chrome, which draws the blur and noise filters exactly. The film
# grain makes a PNG weigh megabytes, so the screenshot is saved as a high-quality JPEG.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$(dirname "$here")")"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
out="$root/docs/assets/banner.jpg"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$(dirname "$out")"
"$chrome" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --force-device-scale-factor=2 --window-size=1280,640 \
    --screenshot="$tmp/banner.png" "file://$here/banner.html" 2>/dev/null
sips -s format jpeg -s formatOptions 88 "$tmp/banner.png" --out "$out" >/dev/null
echo "Rendered $out"
