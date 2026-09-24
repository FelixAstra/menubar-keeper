# Architecture

MenuBarKeeper is a single-process AppKit app with no Xcode project and no dependencies.
`Scripts/build.sh` compiles everything under `Sources/` with `swiftc` and assembles the
bundle by hand, which keeps the whole build readable in one file.

## Layout

```
Sources/
├── main.swift                     NSApplication bootstrap
├── App/                           UI and lifecycle
│   ├── AppDelegate.swift          status item, menus, hot keys, wiring
│   ├── KeeperWindowController.swift  main window: the app list and controls
│   ├── FloatingBarController.swift   the bar of hidden icons
│   ├── AppRowView.swift           one row in the list
│   └── AppIcons.swift             icon lookup with SF Symbol fallbacks
├── Core/                          behaviour, no UI
│   ├── FoldController.swift       hidden set, whitelist, persistence, auto-collapse
│   ├── MenuBarVisibility.swift    bridge to the private visibility API
│   ├── MenuBarScanner.swift       "which app owns which icon" + aggregation
│   ├── MenuBarAgentInventory.swift   macOS 27 path: AX tree of MenuBarAgent
│   ├── AccessibilityInventory.swift  macOS ≤ 26 path: per-app AXExtrasMenuBar
│   └── AppActions.swift           open / hide / quit / preferences for a hidden app
└── Support/
    ├── Localization.swift         string lookup + language override
    ├── Installation.swift         /Applications detection and migration
    ├── DebugLog.swift             file-backed logging (stderr is lost under LaunchServices)
    └── Diagnostics.swift          verification routines, behind flag files
```

`Core` never imports a view, and `Support` never imports `App`. The split is what makes it
possible to test the fold logic by launching the app with a flag file rather than clicking
through the UI (see `Support/Diagnostics.swift`).

## Data flow

```
MenuBarScanner.scan()
   └─ MenuBarAgentInventory (macOS 27)  or  AccessibilityInventory (older)
        → [MenuBarAppEntry]  (bundleIdentifier, displayName, iconCount, isObservable)
             │
             ├─► KeeperWindowController   renders one row per app
             │
             └─► FoldController           hiddenBundles (UserDefaults)
                    ├─ MenuBarVisibility.apply(whitelist:)  ← the actual hiding
                    └─ FloatingBarController                ← the way back in
```

The whitelist handed to the system is `running apps − hidden apps + this app`. It is
rebuilt and re-submitted whenever an app launches or quits, because the API is
whitelist-based (it takes visible identifiers, not a hide list) and applications come and
go while the app is running.

## Decisions worth knowing

**The floating bar is a self-drawn `NSPanel`, not a second row of menu bar items.** An extra
`NSStatusItem` is subject to the same whitelist as every other icon, so it would be hidden
along with the rest — and a separate helper process does not help, because the whitelist
filters on `bundleIdentifier`, not on the process. A window at `.statusBar` level with
`.nonactivatingPanel` is outside the menu bar's jurisdiction entirely. See
[TECHNICAL-FINDINGS.md](TECHNICAL-FINDINGS.md) for the experiments behind this.

**The app must live in `/Applications`.** macOS only protects the status item of an app
installed in a standard location. Run it from the Desktop and its own icon is hidden with
the others, leaving no controls. `Installation.swift` detects this, the window offers to
move, and `build.sh --install` does it automatically.

**Hiding is per app.** The private API keys on application, not on individual status items,
so one icon per app is the granularity the platform allows. The UI says so rather than
pretending otherwise.

**A hidden icon is unreachable.** Once hidden, the status item is absent from the
accessibility tree, so it cannot be clicked on the user's behalf. `AppActions.swift`
reimplements the useful subset (open, preferences via a synthesised ⌘,, quit, reveal in
Finder) and offers "put back on the menu bar" for everything else.

**Every screen is verified, not assumed.** After applying the whitelist the app rescans and
compares: if the marked apps are gone from the accessibility tree it reports *verified*;
otherwise it says so in orange. Silent failure is what makes menu bar utilities feel broken.

## Localization

`Localization.swift` resolves English or Simplified Chinese from the system language, with a
manual override stored in `UserDefaults`. Strings live in
`Resources/<lang>.lproj/Localizable.strings`; the app window's display name comes from
`InfoPlist.strings`. Adding a language means adding a `.lproj` directory and one case to
`L10n.Language` — no code changes elsewhere.
