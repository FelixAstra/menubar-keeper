#!/usr/bin/env bash
#
# Renders `docs/images/menu-bar.png`: one frame of the simulation, cropped to the
# strip that matters.
#
# Unlike the animation this is a single still, so it is not a frame range. The moment
# is 8400 ms — every app is hidden, the floating bar is fully open, and `cursor=0`
# keeps the pointer out of the shot.
#
# Usage: make-banner.sh [framesDir] [outPng]
#
set -euo pipefail

# `render.mjs` is resolved relative to this script, not to the caller's cwd.
cd "$(dirname "$0")"

FRAMES="${1:-frames}"
# Two levels up, not one: this script has already moved into `tools/demo`, and the
# repository's images live in `docs/images`. `../docs` would be `tools/docs` — a directory
# that does not exist, which is how this default used to write the banner somewhere nobody
# was looking.
OUT="${2:-../../docs/images/menu-bar.png}"
AT=8400
# 168 device pixels at 2× = 84 pt: the menu bar (32 pt), the pointer-free gap, the
# floating bar (40 pt) and a little air underneath.
CROP_PIXELS=168

node render.mjs "$FRAMES" --times "$AT" --scale 2 --query cursor=0

ffmpeg -y -hide_banner -loglevel error \
  -i "$FRAMES/f$(printf '%06d' "$AT").png" \
  -vf "crop=iw:${CROP_PIXELS}:0:0" -frames:v 1 -update 1 "$OUT"

ls -la "$OUT"
