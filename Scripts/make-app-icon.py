#!/usr/bin/env python3
"""Fit the white-background app icon into macOS's rounded-square (squircle) grid and
export `Resources/MenuBarKeeper.icns`.

Why this step exists
--------------------
The design export is a full-bleed 1024×1024 **opaque square** (all four corners have
alpha 255). The macOS app icon grid is "1024 canvas, 824×824 content centred, corners
transparent", and **the system does not apply that shape to third-party apps**. Dropped
into the bundle as-is, the icon shows up in Finder as a plain white square.

(Xcode 14+ applies the mask automatically for an asset catalog "Single Size" app icon.
This project builds with `swiftc` and a hand-assembled bundle, so there is no asset
catalog doing that work — it has to be done here.)

Usage
-----
    python3 Scripts/make-app-icon.py                  # default in/out paths
    python3 Scripts/make-app-icon.py <source> <out.icns>

Requires Pillow: `pip install Pillow`

Re-run it after changing the icon design; `Scripts/build.sh` copies the result into the
bundle.
"""

import math
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# The original export lives in the local archive, not in the published repo.
DEFAULT_SRC = os.path.join(ROOT, "_archive", "icon-source", "app-icon-white.png")
DEFAULT_OUT = os.path.join(ROOT, "Resources", "MenuBarKeeper.icns")
ICONSET = os.path.join(ROOT, "build", "MenuBarKeeper.iconset")

CANVAS = 1024       # canvas edge length
CONTENT = 824       # Big Sur icon grid: 824×824 content, 100pt margin on each side
OFFSET = (CANVAS - CONTENT) // 2
SUPERSAMPLE = 4     # mask supersampling factor, for anti-aliasing
SQUIRCLE_N = 5.0    # superellipse exponent; n=5 approximates Apple's squircle

# iconset filenames required by iconutil -> pixel edge length
SIZES = {
    "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
}


def squircle_mask(size):
    """Builds a size×size superellipse mask with an anti-aliased edge."""
    from PIL import Image, ImageDraw

    big = size * SUPERSAMPLE
    radius = big / 2.0
    points = []
    steps = 4096
    for i in range(steps):
        t = 2.0 * math.pi * i / steps
        cos_t, sin_t = math.cos(t), math.sin(t)
        x = radius * math.copysign(abs(cos_t) ** (2.0 / SQUIRCLE_N), cos_t)
        y = radius * math.copysign(abs(sin_t) ** (2.0 / SQUIRCLE_N), sin_t)
        points.append((radius + x, radius + y))

    layer = Image.new("L", (big, big), 0)
    ImageDraw.Draw(layer).polygon(points, fill=255)
    return layer.resize((size, size), Image.LANCZOS)


def main(argv):
    try:
        from PIL import Image
    except ImportError:
        print("Pillow is required: pip install Pillow", file=sys.stderr)
        return 1

    src_path = argv[1] if len(argv) > 1 else DEFAULT_SRC
    out_path = argv[2] if len(argv) > 2 else DEFAULT_OUT

    if not os.path.exists(src_path):
        print(f"Source icon not found: {src_path}", file=sys.stderr)
        return 1

    source = Image.open(src_path).convert("RGBA")
    if source.size != (CANVAS, CANVAS):
        source = source.resize((CANVAS, CANVAS), Image.LANCZOS)

    master = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    box = (OFFSET, OFFSET, OFFSET + CONTENT, OFFSET + CONTENT)
    master.paste(source.crop(box), (OFFSET, OFFSET), squircle_mask(CONTENT))

    if os.path.isdir(ICONSET):
        shutil.rmtree(ICONSET)
    os.makedirs(ICONSET)
    for name, px in SIZES.items():
        master.resize((px, px), Image.LANCZOS).save(os.path.join(ICONSET, name), "PNG")

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", ICONSET, "-o", out_path], check=True)
    print("Wrote", out_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
