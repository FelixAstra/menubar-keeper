# Known gaps and next steps

A working product with a clear list of what is missing. Ordered by how much each item
affects someone using the app for the first time.

## Blocking wider adoption

**The app is not notarized.** macOS quarantines anything downloaded, so the first launch
requires right-click → Open. Every user hits this. Fixing it needs a paid Apple Developer
account, a Developer ID Application certificate, and a `notarytool` step in
`.github/workflows/release.yml` (the workflow already produces the DMG that would be
submitted). Until then the README works around it rather than solving it.

**No Homebrew cask.** Once notarized, `brew install --cask menubar-keeper` is the natural
distribution channel and removes the quarantine dance entirely.

## Should be there but isn't

| Gap | Notes |
|---|---|
| **Launch at login** | A menu bar manager that does not start itself is half-useful. `SMAppService.mainApp.register()` handles it on macOS 13+; the UI already has "hide on launch" to pair with it. |
| **Auto-update** | Sparkle is the standard and needs an appcast plus a signing key; a lighter option is a "new release available" check against the GitHub releases API. |
| **Tests** | `FoldController` is pure logic (whitelist computation, persistence, state transitions) and is fully testable without a UI. The verification routines in `Support/Diagnostics.swift` work but need a human to read the log. A `swift-testing` target runnable by CI would catch regressions in the one place where a bug hides icons the user cannot get back. |
| **Uninstall** | Nothing removes the Accessibility record or `UserDefaults`. `tccutil reset` is documented but not offered in the UI. |
| **Privacy statement** | The app reads the accessibility tree of the whole system, which deserves a short `PRIVACY.md` spelling out that nothing leaves the machine. The `NSAccessibilityUsageDescription` string covers only the permission prompt. |
| **Diagnostics export** | Logging exists but is gated behind `/tmp` flag files. A user reporting a bug has no straightforward way to hand over the state. |

## Product polish

| Gap | Notes |
|---|---|
| **Keyboard navigation in the floating bar** | Arrow keys and Return; today it is mouse-only. |
| **Accessibility labels** | VoiceOver reads the floating bar's buttons as unlabelled image buttons. |
| **Search in the app list** | Matters once someone has 30+ menu bar apps. |
| **Ordering control** | Which apps stay when space runs out is currently fixed by the whitelist, with no way to express priority. |
| **Multi-display behaviour** | The floating bar anchors to the display holding the status item. macOS only draws the menu bar on one display at a time; worth verifying on a two-display setup with the menu bar moved. |
| **Multiple instances of one bundle id** | Two copies of an app resolve to one entry. Rare, but the failure is silent. |

## Engineering

- `hdiutil create` prints a deprecation warning on macOS 27; `diskutil image create` is the
  replacement. Cosmetic for now.
- The universal binary is only exercised on Apple Silicon. The `x86_64` slice compiles, but
  running it on Intel hardware has not been verified.
- `build.sh` always does a clean full build (~15 s). Incremental builds are not worth the
  complexity at this size.
- The release workflow now refuses to publish when the tag disagrees with `VERSION`. Anything
  else that derives from `VERSION` should get the same treatment.
- No contributor scaffolding (issue templates, `CONTRIBUTING.md`). Worth adding only if the
  project takes contributions.

## What cannot be fixed

- **Per-icon granularity.** The private API keys on application, not on individual status
  items. One icon per app is the platform's limit, not a shortcut taken here.
- **A hidden app's own menu.** A hidden status item is absent from the accessibility tree, so
  its original menu cannot be produced. "Put back on the menu bar" is the workaround.
- **Mac App Store.** Distributing an app that calls a private framework is not permitted
  there. Direct download is the only route.
