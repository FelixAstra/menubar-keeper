# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **Two footer controls overlapped in English.** *Refresh* and the language picker were drawn
  on top of each other, by 29 pt on a 620 pt window. The row was anchored from both edges —
  the checkbox and the picker from the left, the buttons from the right — with nothing
  linking the two groups, and nothing in Auto Layout objects to two views occupying the same
  space. English is where it showed: *Detect and hide on launch*, the picker and three
  buttons need about 617 pt of the 588 pt available. The footer is now two rows, preferences
  above actions, and each row carries a request that the groups cannot meet
  (`trailing ≤ leading`), so a longer translation has to shorten a label instead of
  overlapping one. The two labels that can afford it — the checkbox and *Refresh* — drop
  their compression resistance and truncate, and both already have tooltips.
- **The app list showed rows that could not be used.** System items (input menu, Siri,
  SystemUIServer) and MenuBarKeeper itself were listed with everything else, each with a
  disabled checkbox, so the list mixed things you can hide with things that are fixed and
  reported a count that included both. They now live in a *System items (N) — never hidden*
  section behind a disclosure at the end of the list, opening it scrolls it into view, and
  those rows carry no checkbox at all — a disabled one still reads as "click here to hide
  this", which is the one thing the row cannot do. The count column stays aligned across
  both sections.

### Added

- **Automatic detection on launch.** The app now scans the menu bar when it starts and hides
  every app that can be hidden, instead of waiting to be told which ones. The
  *Detect and hide on launch* checkbox previously applied a selection you had to build by
  hand, so a fresh install did nothing until you opened the window and ticked rows — which
  read as the app not working.
- Releasing an app is remembered. An app sent back to the menu bar (from the window, or from
  the floating bar's *Restore to menu bar*) is recorded as released and subtracted from every
  later scan, so it is never quietly hidden again.

### Fixed

- **The app list rendered as a single line.** The scroll view's document view and the stack
  holding the rows never had `translatesAutoresizingMaskIntoConstraints` switched off, so
  every constraint naming them was silently ignored: both stayed 0×0 and all eleven rows
  were laid out on the same coordinates, drawing on top of one another with their titles
  squeezed to nothing. Nothing was logged — a view with that flag on has handed its frame
  back to its superview, so there is no frame for the engine to report a conflict about.
- Rows in the list did not span the window, so the checkbox sat immediately after the app
  name (and, once the rows were real, hard against the right edge in a ragged column).
  `NSStackView.alignment = .width` — the value that reads as "fill the width" — is not
  stored on this SDK, so each row is now pinned to the stack's width explicitly.
- Every control inside a row bunched against its leading edge, leaving the slack as empty
  space. `NSStackView` still defaults to `.gravityAreas`, which packs without stretching;
  the row now uses `.fill`, which hands the slack to the text stack.
- The window grew wider than its design size as soon as the list reported real widths. The
  content view's size was pinned as a floor, and AppKit sizes a window to its content view's
  fitting size — a floor can only raise that, never cap it, so the mechanism label's full
  sentence stretched the window to 651 pt. The size is now pinned exactly.
- The window could greet you with *"It does not look applied — N selected apps are still on
  the menu bar. Check that Accessibility permission is enabled"* when nothing was wrong. The
  system applies a hide a second or two after the submission, so the scan taken right after
  it still saw the icons; the window now rechecks once before saying so.
- Automatic detection is skipped when the app is not running from `/Applications`. The system
  only protects a status item belonging to an app in a standard location, so hiding everything
  automatically from a checkout would hide the app's own icon too and leave no way back — a
  risk that did not exist while folding was strictly manual.
- The self-test for hiding left the app it selected behind in the user's selection. It put back
  only the apps that had been hidden, so the target of the test stayed selected afterwards; it
  now captures and restores the whole selection.
- The walkthrough animation clicked the desktop instead of the Dock icon. The mock dock
  centred itself with `translateX(-50%)`, which the cursor targeting cannot see, so the
  opening click landed 255 pt to the right of the icon it was aiming at. The dock is now
  centred by position, like every other measured element.

### Changed

- Two probes make window bugs checkable without a screenshot: `layoutdump` logs the list's
  real geometry (frames, whether each view is managed by Auto Layout), and `windowshot`
  renders the window straight from the view hierarchy to `/tmp/menubarkeeper-window.png`
  without needing Screen Recording permission. Both found defects that looked like nothing
  at all on screen — eleven rows on one set of coordinates draw as one row.
- `layoutdump` also compares the footer controls' frames against each other and reports
  whether any two of them collide. That is the only way to catch the overlap above: every
  constraint is satisfied while two buttons sit on top of one another, and nothing is
  logged. A new `sectiontest` probe opens and closes the system section for real and reports
  the row counts and whether the section ends up on screen — "the group did not open" is
  invisible in a dump of a window whose rows all live in one list.
- The README's imagery is rendered rather than screen-captured, and its generator lives
  in [`tools/demo`](tools/demo): a menu bar banner that shows the floating bar in place,
  and a walkthrough animation covering selection, hiding, revealing, the per-icon context
  menu and restoring. Both are reproducible from the repo, and the committed PNGs are the
  ones the committed scripts produce.
- The window's hint and the *Detect and hide on launch* tooltip now describe the scan and say
  that releasing an app is permanent, in both languages.

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
