# Demo renderer

Everything the README shows — the menu bar banner and the walkthrough animation — is
rendered from `sim/index.html`, a mock macOS desktop built with HTML and CSS. Nothing
here is part of the shipping app; `Scripts/build.sh` never touches this directory.

The point of rendering rather than screen-recording is repeatability: the page is a
**pure function of time**, addressed as `index.html?t=<milliseconds>`, so any frame can
be produced on its own and produced again identically a year later. `?cursor=0` hides
the pointer, which is how the still banner is taken.

## Regenerating the assets

```bash
cd tools/demo
npm install                 # playwright-core only; it drives the Chrome already on the Mac

node render.mjs frames --fps 20 --duration 13200 --scale 2   # 265 frames, ~3 minutes
./build-assets.sh frames ../docs/images                      # demo.mp4 + demo.gif
./make-banner.sh  frames ../docs/images/menu-bar.png         # the still strip
```

`render.mjs` also takes `--times 0,500,1000` for one-off frames, `--query cursor=0` to
leave the pointer out, and `--scale 1` while iterating.

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
  cursor target while they do. For the same reason the floating bar is centred under the
  menu bar icon by `left`, not by `translateX(-50%)`.

## Assets in `sim/`

| File | Origin |
|---|---|
| `wallpaper.jpg` | Generated for this demo — no third-party imagery |
| `pill.png` | Copy of `Resources/MenuBarTemplate@2x.png`, the shipping menu bar icon |
| `appicon.png` | Extracted from `Resources/MenuBarKeeper.icns` |

`index.html` loads them as ordinary relative files, so opening it directly in a browser
works too — `file://…/sim/index.html?t=9700` is a quick way to look at one moment.
