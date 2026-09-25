# Demo renderer

Everything the README shows — the menu bar banner and the walkthrough animation — is
rendered from `sim/index.html`, a mock macOS desktop built with HTML and CSS. Nothing
here is part of the shipping app; `Scripts/build.sh` never touches this directory.

The point of rendering rather than screen-recording is repeatability: the page is a
**pure function of time**, addressed as `index.html?t=<milliseconds>`, so any frame can
be produced on its own and re-produced on demand. `?cursor=0` hides the pointer, which is
how the still banner is taken.

Repeatable is not the same as byte-identical — see *Checking that an edit changed nothing*
below for what that means in practice.

## Regenerating the assets

```bash
cd tools/demo
npm install                 # playwright-core only; it drives the Chrome already on the Mac

node render.mjs frames --fps 20 --duration 13200 --scale 2   # 265 frames, about 3 minutes
./build-assets.sh frames ../../docs/images                   # demo.mp4 + demo.gif
./make-banner.sh  frames ../../docs/images/menu-bar.png      # the still strip
```

Two levels up from `tools/demo`, not one: `../docs` is `tools/docs`, which does not exist —
and `ffmpeg` will happily create it and write the assets where nothing reads them.

`render.mjs` also takes `--times 0,500,1000` for one-off frames, `--query cursor=0` to
leave the pointer out, and `--scale 1` while iterating.

### Checking that an edit changed nothing

Pruning something from `sim/index.html` that is supposed to be inert is worth proving,
because "unused" is easy to get wrong — the glyph table is referenced both by name and as
`GLYPHS.<name>`, so a search for string literals misses half of it.

**Do not compare the frames byte for byte.** The same page rendered at the same timestamp
twice does not produce the same file: Chrome's rasteriser is not deterministic here, and a
single 1280×800 frame at 2× came back with ~26 000 differing pixels, all of them sub-pixel
anti-aliasing. A byte comparison therefore reports a difference every time, including
between two runs of the identical file, which is worse than no check at all.

Compare a region you can reason about instead. Rendering a *different* page and diffing the
result is still useful — a real layout change moves whole edges and shows up as thousands of
pixels across a wide band, where the jitter is a few hundred scattered along text:

```bash
mkdir -p /tmp/before && git show HEAD:tools/demo/sim/index.html > /tmp/before/index.html
cp sim/pill.png sim/appicon.png sim/wallpaper.jpg /tmp/before/
node render.mjs /tmp/after  --times 0,3000,5700,9700 --scale 1
node render.mjs /tmp/before --times 0,3000,5700,9700 --scale 1 --sim /tmp/before
# then look at the pairs, or count differing pixels per frame
```

The banner is a case in point: regenerating it produces a file that differs from the
committed one by about 440 pixels in the right-hand quarter, which is the same number the
same file differs from itself by. Nothing had changed.

## How the walkthrough is laid out

`T` in `sim/index.html` is the timeline: every beat is a `[start, end]` pair in
milliseconds, and `renderFrame(t)` reads nothing else. Edit `T` and the captions, and
the whole animation re-times itself — the pointer path, the dock magnification, the
window's open and close, the menu bar reflow and the floating bar all follow from it.

Two details worth knowing before changing anything:

- **The dock icon launch animation scales `#window` from the Dock icon's position**, so
  `transform-origin` is computed from measured geometry, not hard-coded.
- **`boxOf()` measures layout boxes, not `getBoundingClientRect`.** The window and the
  floating bar animate with `scale`, and a transform-aware measurement would move every
  cursor target while they do. The flip side is that anything the pointer has to hit must
  be centred by *position* — `centreX()` — and never with `translateX(-50%)`, because a
  translate is invisible to `boxOf`. The dock was centred that way once, which put every
  dock-landing click 255 pt to the right of its icon, out on the wallpaper.

## Assets in `sim/`

| File | Origin |
|---|---|
| `wallpaper.jpg` | Generated for this demo — no third-party imagery |
| `pill.png` | Copy of `Resources/MenuBarTemplate@2x.png`, the shipping menu bar icon |
| `appicon.png` | Extracted from `Resources/MenuBarKeeper.icns` |

The demo shows the mark the app ships with, which is why the menu bar here wears the capsule:
the garden daisies are an optional menu bar style (`MenuBarIconStyle`, picked in the window)
and a walkthrough of a default install must not show them. Rendering a *daisy* walkthrough
means copying `Resources/DaisyHidden@2x.png` in as another `<img>` and swapping `src` — the
same one-line change 1.3.0 made in the other direction.

`index.html` loads them as ordinary relative files, so opening it directly in a browser
works too — `file://…/sim/index.html?t=9700` is a quick way to look at one moment.
