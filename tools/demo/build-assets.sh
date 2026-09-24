#!/usr/bin/env bash
#
# Turns the rendered PNG frames into the two demo assets:
#
#   demo.mp4  full frame rate, for anyone who wants to scrub through it
#   demo.gif  the README hero: fewer frames, smaller canvas, tuned palette
#
# Usage: build-assets.sh <framesDir> <outDir>
#
set -euo pipefail

FRAMES="${1:?frames directory}"
OUT="${2:?output directory}"
mkdir -p "$OUT"

INPUT=(-pattern_type glob -framerate 20 -i "$FRAMES/*.png")

# --- MP4: the reference copy -------------------------------------------------
ffmpeg -y -hide_banner -loglevel error "${INPUT[@]}" \
  -vf "scale=1600:1000:flags=lanczos" \
  -c:v libx264 -preset slow -crf 21 -pix_fmt yuv420p -movflags +faststart \
  "$OUT/demo.mp4"

# --- GIF: one palette for the whole clip, then a two-pass encode -------------
# Feeding the same scaled stream to palettegen and paletteuse in one filtergraph
# keeps the palette global, which is what stops the background from shimmering.
ffmpeg -y -hide_banner -loglevel error "${INPUT[@]}" \
  -vf "fps=12.5,scale=1040:650:flags=lanczos,split[a][b];\
[a]palettegen=max_colors=192:stats_mode=diff[p];\
[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  -loop 0 "$OUT/demo.gif"

ls -la "$OUT"
