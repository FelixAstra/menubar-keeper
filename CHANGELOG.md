# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-09-26

### Added

- **The daisy at the end of every app list row is a control now, not a picture.** Point at a
  folded row and it becomes the trowel, with a tooltip saying what the click will do
  (*取消收折，恢复到菜单栏* / *Show — put this app's icon back on the menu bar*); click it and the
  app changes state. It goes through the same path as clicking the row and as the checkbox, so
  there is one state with three ways in rather than three controls that can drift apart.
- A `rowstatecheck` probe covers it end to end: what each mark shows at rest and under the
  pointer, that a click on the control really moves the app, and — the failure worth catching —
  that no row ends up saying one thing while the selection says another. A hover cannot be
  synthesised the way a click can (there is no event to post that AppKit delivers as
  `mouseEntered`), so the probe puts the control into the state the tracking area would and
  then reads back the mark it draws. It restores the selection exactly as it found it, then
  reports every row row-by-row.

### Changed

- **The blue checkbox is gone from the list rows.** It sat three points from a daisy saying the
  same thing, so every row carried two marks for one fact — and the row read as busier than what
  it had to say. The daisy is the row's only control now: it shows the state, it changes it, and
  it is the way in from the keyboard, which the checkbox used to be; the state word rides along as
  its accessibility value. A locked row keeps its plain sleeping daisy where the checkbox was, so
  the two sections still line up down the right-hand edge — and the placeholder column that held a
  space open for a box nobody has any more is gone with it.
- **Both states of the row now say the same kind of thing.** The column used to report the
  app's icon count while it was on the menu bar and switch to a word once it was hidden, so one
  column answered two different questions and the two states did not look like each other. It
  is a state word in both states now — *已收折* / *未收折*, *hidden* / *shown* — which is the
  one thing it can say that is true of the row rather than of the last scan.
- The row's daisy and word follow the selection the moment it changes, rather than the next
  scan a second later. A row that disagreed with its own checkbox for that second read as
  broken; whether the system actually applied the change is the headline's job, not the row's.
- A row whose app can never be hidden (a system item, or MenuBarKeeper itself) keeps the plain
  sleeping daisy and gets no tooltip, no highlight and no click — the control never offers an
  action it cannot perform.
- The demonstration's walkthrough now points at each row's state mark instead of the middle of
  the row, so the trowel the swap produces is actually visible in the animation.

### Fixed

- The floating bar's trowel was commented as "the same mark the main window uses for state",
  which had never been true — the window used the daisies and the trowel appeared nowhere in
  it. The comment says what the mark means in each place now.
- The demonstration's list rows show the state mark and the state word the app shows. They had
  gone on saying *1 icon* with no mark since 1.3.0, so the README's walkthrough was advertising
  a window that no longer existed.
- The demonstration's *Hide on launch* box was drawn empty, so the walkthrough showed the one
  preference that ships ticked as if it were off. It shows the tick now — the same mark the row
  checkboxes drew, which is the only place it is drawn any more.

## [1.4.0] - 2026-09-25

### Added

- **The menu bar mark is a choice now**: the brand capsule, or the state daisy — coloured and
  smiling while icons are folded away, grey and asleep while everything is on the bar. The
  picker sits in the window's title row beside the language tab, shows the mark in effect, and
  names both options in its menu. Switching redraws the menu bar immediately: nothing but one
  image depends on it, so unlike the language tab it needs no relaunch.
- An `iconstylecheck` probe drives that picker the way a click does — it finds the real
  `NSPopUpButton` on the content view, fires the real `NSMenuItem` action, and then checks the
  status item's *image*, since the stored preference alone would not prove the menu bar
  redrew. It restores the value exactly as it found it, absent key included.

### Changed

- **A fresh install is back on the brand capsule.** 1.3.0 made the daisy unconditional, which
  repainted the menu bar of every existing install on upgrade — and took the README's imagery
  and the walkthrough with it, both of which are supposed to show the app as it ships. The
  daisy is opt-in from here: the *absent* preference value resolves to the capsule, so an
  install that never touches this control looks exactly as it did before the daisies existed.
  Adding an option must not repaint anyone's menu bar behind their back.

### Fixed

- `selftest` reports the icon style it resolved (`iconStyle=… rawKey=…`), including the
  absent-key case — the one that has to keep answering "capsule`.

## [1.3.0] - 2026-09-25

### Added

- **Clicking a folded icon on the floating bar now opens the app's own menu**, the way
  clicking the menu bar icon would have. Three measured facts forced the shape: a hidden
  status item leaves the accessibility tree completely (so the icon has to come back
  first); `AXPress` on a third-party item returns success and does nothing (MenuBarKeeper's
  own item — the control group — does respond, so the mechanism is sound and the foreign
  items simply ignore it); and a synthetic click only lands once the menu bar has finished
  re-flowing after the reveal, which is why the click waits 0.35 s for the item's frame to
  hold still. The reveal itself lands in 0.07–0.11 s, the icon goes back after 0.45 s, and
  an open menu survives the icon vanishing — which keeps this two steps rather than a state
  machine tracking a foreign menu. A 3 s failsafe re-hides the icon no matter what, because
  a transient reveal is the one state where a dropped asynchronous hop leaves the user's
  menu bar wrong; it fired once in five runs before it existed. If nothing can be clicked —
  no Accessibility permission, or the icon never came back — the old activate fallback runs,
  so a click is never a no-op.
- **Garden state icons**, replacing the monochrome capsule for state display: a coloured,
  smiling daisy while icons are folded away, a grey, sleeping one while everything is on
  the menu bar — in the menu bar itself and at the right end of every row of the app list.
  The trowel marks the actions that put an app back on the menu bar.

### Changed

- The menu bar icon is the state daisy now, not the template capsule: full colour on
  purpose, since the entire point of the design is the colour difference between the two
  states and template recolouring would flatten both to the same monochrome shape. The
  capsule stays as the brand mark in the window's title row and as the fallback if the
  daisy assets are missing — nothing depends on artwork being present in order to work.

## [1.2.0] - 2026-09-25

### Added

- The layout probe reports how much of the state headline survives beside the language tab,
  and whether that tab agrees with the language actually in force. A clipped label reports the
  width it was handed rather than the width its text wants, so the two have to be compared;
  and a tab showing the wrong half would cost a restart to find out.
- `windowshot` lays down the window's own colour before drawing. The bitmap starts transparent
  and the content view paints no background of its own, so a dark-appearance window rendered as
  light text over nothing: composited onto white, every label disappeared — which reads exactly
  like a layout that has collapsed. It was the one artifact whose whole job is to be looked at,
  and half of it was blank.

### Changed

- **The language switcher moved into the title row**, as a 中 / EN tab in the top-right corner,
  and **the footer is back to a single row**: *Detect and hide on launch* at its left, then
  *Refresh* immediately left of *Show all*, then the primary button. The two belong together —
  the picker is what made the footer need two rows in 1.1.0. It sat between the checkbox and
  the buttons, and in English the row needed 617 pt of the 588 pt available, so it was split.
  Moving the picker up leaves a row that fits with a fifth of its width to spare, and the
  height the second row was using goes back to the app list, which is the part that has to stay
  visible. The window is 620×602 rather than 620×630.
- 中 / EN is a `NSSegmentedControl` rather than a pop-up: the current language is one click
  away instead of two, and nothing is hidden behind a menu. It shows the language *in effect*
  rather than the stored choice — a fresh install stores "follow macOS", which has no segment
  of its own, so the tab resolves it, and a Chinese Mac shows 中 selected. Holding ⌥ while
  clicking returns to following macOS, which a two-segment tab has nowhere else to put.
- The headline gives way before the tab does. They share the title row and the tab has to stay
  legible, while the sentence still reads when shortened — so it is the headline that carries
  the low compression resistance and truncates. Both languages leave about 170 pt spare at
  620 pt wide, measured rather than assumed.
- Switching to the language already in effect no longer restarts the app; it pins the choice
  and stops. Otherwise clicking 中 on a Chinese Mac would raise "Language changed", relaunch,
  and arrive at exactly the same window.
- The demo in `tools/demo` mirrors the new window — the tab in the title row, the footer on one
  row — so the README's animation keeps showing the interface that exists.

### Fixed

- **`tools/demo`'s regeneration instructions wrote the assets to the wrong directory.**
  `./build-assets.sh frames ../docs/images` looks right from `tools/demo` and is not: one level
  up is `tools/docs/images`, and `ffmpeg` creates a missing output directory without
  complaining, so the new files land where nothing reads them while the committed ones appear
  untouched. Both the instructions and `make-banner.sh`'s default now point two levels up, and
  the default was removed in favour of an explicit path — a wrong default is how this went
  unnoticed.
- The demo README claimed the renders are reproducible "identically a year later" and offered
  a byte-for-byte comparison as the way to prove an edit changed nothing. Neither holds:
  Chrome's rasteriser gives a different file every time, and the same frame rendered twice
  differed by about 26 000 sub-pixel anti-aliasing pixels. The recipe would have reported a
  difference on every run, including between two runs of the same file. Both claims are
  replaced with what is actually true, and the gap is listed in the roadmap.
- **The language tab stretched to a third of the window.** `NSSegmentedControl` hugs its
  content less than the `NSTextField` beside it does, so the row's spare width went to the tab:
  two single-character labels came out 264 pt wide, a blue bar running across the title row.
  It is now pinned rigid at 70.5 pt and the headline absorbs the slack instead, which is
  invisible because it is left-aligned.

## [1.1.0] - 2026-09-25

### Added

- **Automatic detection on launch.** The app now scans the menu bar when it starts and hides
  every app that can be hidden, instead of waiting to be told which ones. The
  *Detect and hide on launch* checkbox previously applied a selection you had to build by
  hand, so a fresh install did nothing until you opened the window and ticked rows — which
  read as the app not working.
- Releasing an app is remembered. An app sent back to the menu bar (from the window, or from
  the floating bar's *Restore to menu bar*) is recorded as released and subtracted from every
  later scan, so it is never quietly hidden again.
- Automatic detection is skipped when the app is not running from `/Applications`. The system
  only protects a status item belonging to an app in a standard location, so hiding everything
  automatically from a checkout would hide the app's own icon too and leave no way back — a
  risk that did not exist while folding was strictly manual.

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
- **`make icon` runs on a fresh clone.** It used a Python script that needed Pillow — a
  `pip install` nothing in the repo declared — and read its source artwork out of a
  gitignored folder, so a clone could not regenerate the icon at all: the documented target
  failed twice over. It is now `Scripts/make-app-icon.swift`, drawing the squircle clip with
  Core Graphics and calling `iconutil`, both of which are already required to build the app,
  and the artwork is committed as `Supporting/AppIconSource.png`. The `.icns` in the repo is
  the one the committed script produces (same 824×824 content grid, corners transparent,
  99.96 % mask agreement on the 1024 px layer).

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
- The self-test for hiding left the app it selected behind in the user's selection. It put back
  only the apps that had been hidden, so the target of the test stayed selected afterwards; it
  now captures and restores the whole selection.
- The walkthrough animation clicked the desktop instead of the Dock icon. The mock dock
  centred itself with `translateX(-50%)`, which the cursor targeting cannot see, so the
  opening click landed 255 pt to the right of the icon it was aiming at. The dock is now
  centred by position, like every other measured element.

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

[1.5.0]: https://github.com/FelixAstra/menubar-keeper/releases/tag/v1.5.0
[1.4.0]: https://github.com/FelixAstra/menubar-keeper/releases/tag/v1.4.0
[1.3.0]: https://github.com/FelixAstra/menubar-keeper/releases/tag/v1.3.0
[1.2.0]: https://github.com/FelixAstra/menubar-keeper/releases/tag/v1.2.0
[1.1.0]: https://github.com/FelixAstra/menubar-keeper/releases/tag/v1.1.0
[1.0.0]: https://github.com/FelixAstra/menubar-keeper/releases/tag/v1.0.0
