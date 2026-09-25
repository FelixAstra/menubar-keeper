# MenuBarKeeper

**Hide the menu bar icons you don't need — and get them back with one click.**

[**Download**](https://github.com/FelixAstra/menubar-keeper/releases/latest/download/MenuBarKeeper.dmg) · macOS 14+ · MIT · English / 简体中文

<img src="docs/images/menu-bar.png?v=4" alt="A macOS menu bar with MenuBarKeeper's daisy icon beside the clock, and the apps it hides listed in a bar directly underneath" width="100%">

## Download

Grab the disk image: **[MenuBarKeeper.dmg](https://github.com/FelixAstra/menubar-keeper/releases/latest/download/MenuBarKeeper.dmg)**

1. Open the image and drag **MenuBarKeeper** into **Applications**.
2. Launch it from there and grant **Accessibility** permission when asked.

> **First launch is blocked by Gatekeeper.** The app is not notarized, so macOS refuses to
> open a downloaded copy. Right-click the app in Applications → **Open** → **Open** again.
> Or clear the flag from a terminal:
> `xattr -dr com.apple.quarantine /Applications/MenuBarKeeper.app`

## What it does

<img src="docs/images/demo.gif?v=5" alt="Walkthrough: tick apps in the MenuBarKeeper window and their icons leave the menu bar; click the daisy and they drop down beneath it; right-click one to put it back; click again and everything is restored" width="100%">

<sub>[demo.mp4](docs/images/demo.mp4) — the same walkthrough without GIF dithering.</sub>

| | |
|---|---|
| **See** | Every menu bar icon, grouped by the app that owns it |
| **Hide** | On launch it hides every app it finds on the menu bar — nothing to set up |
| **Reach** | Click the menu bar icon and the hidden ones drop down right underneath it |
| **Act** | Right-click a hidden icon to open, quit, or send the app back to the menu bar |
| **Undo** | *Show all* restores everything; quitting the app always does too |

Hidden apps keep running. Only the icon goes away.

### What happens on launch

MenuBarKeeper scans the menu bar and hides **every app it can hide**, so the bar is clean
without you picking anything. Anything you send back stays back: the release is remembered, and
no later scan will hide that app again. Unchecking *Detect and hide on launch* in the window
stops the scan, leaving only the apps you ticked by hand.

The scan is skipped if the app is not running from `/Applications` — see below.

## Usage

| Action | Result |
|---|---|
| Click the menu bar icon | Show / hide the floating bar of hidden icons |
| Right-click it (or ⌥-click) | Menu: expand all, permissions, help, quit |
| Click a row in the window | Hide / unhide that app — an app you unhide is not auto-hidden again |
| Click *System items (N)* in the window | See the items macOS manages, which can never be hidden |
| Right-click an icon in the floating bar | Open, Preferences, Hide, Put back, Quit |
| ⌥⌘M | Show / hide the floating bar |
| ⌥⌘\\ | Collapse / expand the menu bar |

**Putting an app back** is how you reach the rest of its own menu: a hidden icon is not in
the system's accessibility tree at all, so its original menu cannot be reproduced. Send it
back to the menu bar for a moment, use it, then hide it again.

## Why /Applications matters

macOS only honours a status item from an app installed in `/Applications`. Run the app from
anywhere else and **its own icon gets hidden along with the others**, leaving no way back.
The app detects this and offers to move itself; the build script installs there by default.

## Build from source

```bash
git clone https://github.com/FelixAstra/menubar-keeper.git
cd menubar-keeper
make            # universal binary (arm64 + x86_64) -> build/
make install    # build, copy to /Applications, launch
make dmg        # build and package MenuBarKeeper-<version>.dmg
make icon       # regenerate the app icon from Supporting/AppIconSource.png
make help       # all targets
```

Requires the Xcode command line tools. No Xcode project, no third-party dependencies —
including `make icon`, which draws the icon's rounded-square mask with Core Graphics rather
than an image library you would have to install first.

> The images in this README are rendered from [`tools/demo`](tools/demo) instead of being
> screen-recorded, so they can be regenerated rather than re-shot.

> For a stable Accessibility grant across rebuilds, create a local signing certificate once
> with `make cert`. Ad-hoc signatures are keyed to the binary's hash, so every rebuild makes
> macOS treat the app as new and ask for the permission again.

## How it works

Menu bar icon visibility is driven by a private framework (`MenuBarClientCore`), and icon
ownership is read from the accessibility tree of the system's menu bar agent. Two short
documents cover the rest:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — modules and data flow
- [docs/TECHNICAL-FINDINGS.md](docs/TECHNICAL-FINDINGS.md) — the reverse-engineered API notes and the pitfalls behind them
- [docs/ROADMAP.md](docs/ROADMAP.md) — known gaps, and what is impossible rather than merely missing

## Limitations

- Granularity is **per app**, not per icon — you cannot hide one icon of an app and keep another.
- System items (clock, battery, Control Center) are never touched. They are listed in their
  own section at the end of the app list rather than among the apps you can hide.
- The app is not notarized, so the first launch needs the right-click → Open dance.
- Tested on macOS 27 with Apple Silicon; the fallback path targets macOS ≤ 26.

## Localization

English and Simplified Chinese. The language follows your system setting; the **中 / EN** tab in
the top-right corner of the window pins one instead, and the app restarts to apply it.
⌥-clicking the tab goes back to following the system.

## License

[MIT](LICENSE)
