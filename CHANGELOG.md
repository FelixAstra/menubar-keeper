# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- The walkthrough animation clicked the desktop instead of the Dock icon. The mock dock
  centred itself with `translateX(-50%)`, which the cursor targeting cannot see, so the
  opening click landed 255 pt to the right of the icon it was aiming at. The dock is now
  centred by position, like every other measured element.

### Changed

- The README's imagery is rendered rather than screen-captured, and its generator lives
  in [`tools/demo`](tools/demo): a menu bar banner that shows the floating bar in place,
  and a walkthrough animation covering selection, hiding, revealing, the per-icon context
  menu and restoring. Both are reproducible from the repo, and the committed PNGs are the
  ones the committed scripts produce.

## [1.0.0] - 2026-09-24

First public release.

### Added

- Group menu bar icons by app and move any of them into a hidden area.
- A floating bar, drawn below the menu bar, that reveals the hidden apps' icons;
  click one to switch to it, right-click for per-app actions.
- Per-app context menu with Open, Preferences, Restore to menu bar, Hide, Reveal in
  Finder, Quit and Force Quit.
- Global shortcuts that work even when the menu bar icon is hidden:
  `⌥⌘M` toggles the floating bar, `⌥⌘\` toggles the menu bar icons.
- Optional "hide on launch".
- Localization: English and Simplified Chinese, selected automatically from the
  macOS language setting, with a manual override in the main window.
- Built-in verification that hiding really took effect, reported in the window.
- Universal binary (Apple Silicon and Intel), packaged as a `.dmg`.

[1.0.0]: https://github.com/FelixAstra/menubar-keeper/releases/tag/v1.0.0
