# Technical findings

Reverse-engineering notes behind MenuBarKeeper. Everything here was measured on
macOS 27.0 (build 26A428), Apple Silicon, Xcode 26 / Swift 6.4. Where a claim was later
overturned it is marked as such — the wrong turns are the useful part.

## 1. How menu bar icon visibility actually works

There is no public API for hiding another application's menu bar icon. The mechanism used by
existing menu bar managers is a private framework:

| Symbol | Role |
|---|---|
| `MenuBarClientCore` (private framework) | The client used to submit a visibility request |
| `MBAssessmentModeConfiguration` | Describes the request |
| `MBAssessmentModeAssertion` | The assertion object that holds it |

The request is **whitelist-based**: you hand it the identifiers of the menu bar items that
should stay visible, and everything else is hidden. There is no "hide these" list.

### The parameter that cost the most time

The visible-item list is constructed from a `systemItemIDs` array. It **must be `[0...8]`** —
nine valid indices:

```swift
let systemItemIDs = Array(0...8)
```

Pass anything outside that range and the framework does not return an error. It **silently
ignores the whole request**. This produced a confident, wrong conclusion in an early version
of this document ("third-party apps cannot hide menu bar icons on macOS 27") which was later
retracted: the API works, the parameters were wrong.

> Lesson: a private API returning success means the call was accepted, not that the arguments
> meant anything. Validate the arguments separately, and when there is no effect, suspect
> your own parameters before concluding the platform is locked down.

### The old trick is genuinely dead

Growing a separator item until it pushes icons off-screen was the standard approach for
years. It no longer works: macOS 27 draws the entire menu bar in a single window owned by
`com.apple.MenuBarAgent`, so there is no per-item window geometry left to manipulate.

Icons can only be hidden through the whitelist API.

## 2. The old helper-process idea does not work

**Hypothesis.** The system hides the icon of the process that submits the request — so submit
it from a separate helper process, and the main app's icon survives.

A helper was written (`NSApplication` with one `NSStatusItem`, forwarding clicks to the main
app over `DistributedNotificationCenter`). Result:

```
隐藏后 helper 可见 = false      (measured)
```

**Why it failed.** The whitelist filters on **`bundleIdentifier`**, not on the process. A
second process does not change which bundle is being filtered, so the helper's icon was hidden
exactly like the main app's. The idea is abandoned; the source is kept in the local archive
only, and it is not part of the build.

**The real cause** of "the tool hides its own icon" is in §3.

## 3. macOS only protects the status item of an app in `/Applications`

This is the single most misleading behaviour in this project.

With the whitelist built correctly — including this app's own bundle identifier in first
position — running from `~/Desktop` still hides the app's own icon. Move the same bundle to
`/Applications` and it survives.

The system only treats a status item as a protected resident of the menu bar when the app
lives in a standard install location. Nothing in the API surface says so, and the symptom
("my app hides itself") looks like a bug in your own whitelist logic.

**Consequences in the code.** `Installation.swift` checks `Bundle.main.bundlePath`, the main
window warns and offers a one-click move, and `build.sh --install` copies the app into
`/Applications`. The code signature is unaffected by the move, so the Accessibility grant
survives it.

**This is also why the floating bar is self-drawn.** A second `NSStatusItem` would be subject
to the same whitelist — and per §2, so would a helper process's. A `NSPanel` at `.statusBar`
level is not a menu bar item at all, so the whitelist cannot reach it:

```swift
panel.styleMask = [.borderless, .nonactivatingPanel]
panel.level = .statusBar
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
```

## 4. Reading icon ownership

To show a list of "app → its menu bar icons" the app needs to know which icon belongs to
whom, and that information is in the accessibility tree.

- **macOS 27**: one window draws the whole menu bar, so the per-app `AXExtrasMenuBar` path
  returns nothing useful. The tree is read from `MenuBarAgent`
  (`AXUIElementCreateApplication` on the owning pid) instead, and each element's
  `AXUIElementGetPid` maps it back to an application.
- **macOS ≤ 26**: each app exposes its own `AXExtrasMenuBar`, which is simpler and still
  supported.

Both paths require the **Accessibility** permission. Without it the app lists nothing and
says why, instead of showing an empty window.

A hidden icon is **absent** from the tree, not merely invisible. That is what makes the
verification in §5 possible — and what makes it impossible to reproduce a hidden app's
original context menu.

## 5. Verification, since failure is silent

Every failure mode here is silent: a rejected request, an ignored parameter, a permission
that did not apply. So the app checks its own work. After applying the whitelist it rescans
and compares:

| Result | Meaning |
|---|---|
| Marked apps gone from the tree | verified, shown in green |
| Marked apps still present | ineffective, shown in orange |
| Mechanism unavailable / request rejected | reported as such |

`Support/Diagnostics.swift` goes further and can exercise the whole path headlessly, driven
by flag files (`/tmp/menubarkeeper-<flag>`) because environment variables do not survive a
launch through LaunchServices:

| Flag | What it does |
|---|---|
| `autoshow` | opens the main window |
| `showbar` | shows the floating bar |
| `selftest` | prints discovered apps, icon counts, resolved language, loaded assets |
| `verify` | hides one app, rescans, asserts the outcome, restores |
| `releasecheck` | walks one app through select → release and asserts the release was recorded |
| `toggletest` | synthesises three clicks on the app's own icon, asserts `true/false/true` |
| `menutest` | opens an icon's context menu (blocking; dismissed from a background thread) |
| `bartoggle` | flips the collapse state and asserts the button's symbol followed |
| `layoutdump` | logs the list's real geometry, every control's frame, whether any two collide, how much of the headline survives beside the language tab, and whether that tab agrees with the language in force |
| `windowshot` | renders the window from the view hierarchy to `/tmp/menubarkeeper-window.png` — no Screen Recording permission, nothing has to be in front of it |
| `sectiontest` | opens and closes the system items section through its real control and reports the row counts, the document height, and whether the last row ended up on screen |

`layoutdump` is the one to reach for first when a window looks wrong. Frames are the only
thing a screenshot cannot report: eleven rows laid out on one set of coordinates draw as a
single row, and `tamic=Y` on a view that takes part in a constraint chain means the engine
ignored every constraint naming it — silently, because such a view has handed its frame back
to its superview and there is no frame left to report a conflict about.

`windowshot` lays down `NSColor.windowBackgroundColor` before drawing, in the view's own
effective appearance. The bitmap starts transparent and the content view paints no background,
so a dark-appearance window otherwise came out as light text over nothing: composited onto
white, every label disappeared and the shot looked like a collapsed layout.

## 6. Two UI traps

### 6.1 The outside-click monitor eats the status item's click

Clicking the menu bar icon showed the floating bar but clicking it again did nothing.

The floating bar installs global *and* local monitors for `.leftMouseDown` to close itself
when the user clicks elsewhere. A click on the app's own status item reaches the monitor
first (mouse-down), which decides "outside" and hides the panel; then the status item's
action fires (mouse-up) and toggles it back on. Net effect: nothing appears to happen.

Note the local monitor matters too — the status item's window belongs to this process, so
both monitors see the click.

The fix is to exclude the status item's own frame from "outside", read through a closure so
it stays correct as the icon moves:

```swift
// AppDelegate injects: { self.statusItem.button?.window?.frame }
private func handleOutsideClick() {
    guard !isTrackingContextMenu else { return }
    if let rect = statusItemHitRect?(), rect.contains(NSEvent.mouseLocation) { return }
    guard Date().timeIntervalSince1970 > ignoreOutsideClicksUntil else { return }
    hide()
}
```

Testing this by calling `toggle()` directly proves nothing — it bypasses the monitor. The
`toggletest` routine posts real synthetic clicks through the event stream instead. `CGEvent`
uses top-left screen coordinates, so the y value has to be flipped relative to AppKit:
`cgY = mainScreen.frame.maxY - appKitY`.

### 6.2 Menus in a non-activating panel need `autoenablesItems = false`

The floating bar is a `.nonactivatingPanel` and is never the key window. Attaching an
`NSMenu` to a button there produces a menu that opens but is entirely greyed out, because
AppKit's automatic enabling logic judges every item against a window that does not have focus.
Set `menu.autoenablesItems = false` and enable items explicitly.

Two related details: `NSMenu.popUp(positioning:at:in:)` **blocks** until the menu closes, so
the "suppress the outside-click monitor" flag can bracket it exactly; and to dismiss a menu
from a timer while debugging, the timer must run on a background queue, because the main
thread is parked inside the menu's event tracking.

## 7. Icons

- **The app icon must be supplied already shaped.** macOS does not apply the rounded-square
  mask to third-party bundles — Xcode's asset catalog does that at build time, and this
  project has no asset catalog. `Scripts/make-app-icon.swift` clips the artwork to a
  squircle path (superellipse, n = 5) on the 824×824 content grid and re-exports the
  iconset, since the source artwork is a full-bleed opaque square. It is Swift rather than
  Python so that `make icon` works on a fresh clone: the earlier Pillow version needed a
  `pip install` that nothing declared, and read its input from a gitignored folder.
  `Supporting/AppIconSource.png` is the tracked source.
- **Template images recolour away any state carried by colour.** The menu bar icon is a
  template image (`isTemplate = true`): a single black-and-transparent artwork, correct in
  both light and dark menu bars. The daisies are the opposite — coloured and smiling when
  folded, grey and asleep when expanded — and the whole point of that design is the colour
  difference, which template recolouring would flatten to one monochrome shape. So the two
  cannot be the same image, and since 1.4.0 they are two *options* rather than one:
  `MenuBarIconStyle` picks between them, the daisies always load with `isTemplate = false`,
  and the capsule stays the default. That default is the whole lesson of 1.3.0, which shipped
  the daisy unconditionally — an upgrade repainted everybody's menu bar, which no optional
  appearance change should ever do. The rule that survives: never communicate state through
  `alphaValue`, and never put two states that differ only by colour into a template image.
- **Sizing**: menu bar assets are specified in points (the capsule is `44 × 18`, the daisy
  is an 18 pt square) with an `@2x` variant for Retina. The two have different aspect ratios,
  which is why the picker's thumbnails are normalised by *height*: letting each mark keep its
  own scale resized the control — and shifted the headline beside it — on every switch. The
  build copies `Resources/` verbatim, so `.lproj` folders and image variants keep their
  structure.
- **A hover cannot be synthesised, only a state can be set.** A click is testable because there
  is an event to post and a target/action to fire, which is how the menu-item and row-mark
  probes drive the real control instead of calling the model behind it. There is no equivalent
  for `mouseEntered`: nothing can be posted that AppKit will deliver as a pointer entering a
  view. So `StateDaisyButton.isHovering` is a settable property that the tracking area drives in
  normal use and the probe sets directly, and the check reads back the *mark* — the three marks
  are all 18 pt full-colour images, so only the name the control reports says which one is on
  screen.
- **One state, two ways in — so the row owns it.** A click anywhere on the row and a click on the
  state daisy both ask the row to toggle, and the row's `isMarked` setter is the only thing that
  writes the word and the mark. The alternative — each control updating itself — is what makes a
  row's word disagree with its own state for the second between a click and the next scan. The
  state itself is a plain `Bool` on the row: it used to live in the row's checkbox, but a checkbox
  and a daisy three points apart is two marks for one fact, and dropping the box is also what let
  the daisy take over the keyboard and accessibility duties the checkbox had been carrying.

## 8. Signing and the Accessibility grant

The Accessibility permission is recorded by TCC against the app's **designated requirement**.
For an ad-hoc signature that requirement is the binary's `cdhash`, which changes on every
rebuild — so macOS treats each build as a new app and asks again. Signing with a stable
certificate changes the requirement to
`identifier "..." and certificate leaf = H"..."`, which survives rebuilds.

```bash
codesign -dr - build/MenuBarKeeper.app
# good: designated => identifier "io.github.felixastra.MenuBarKeeper" and certificate leaf = H"..."
# bad:  designated => cdhash H"..."      (ad-hoc — the permission will keep resetting)
```

Create the certificate once with `Scripts/make-signing-cert.sh`; the private key stays in the
login keychain. Note that OpenSSL 3 writes PKCS#12 files that `security import` rejects unless
asked for the legacy algorithms:

```bash
openssl pkcs12 -export -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg SHA1 ...
```

**Releases are not notarized.** Notarization needs a paid Apple Developer account, so
downloaded builds are quarantined by Gatekeeper and the first launch needs
right-click → Open. If a stale grant ever misbehaves, clear it with
`tccutil reset Accessibility io.github.felixastra.MenuBarKeeper`.
