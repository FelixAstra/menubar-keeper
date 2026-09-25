import AppKit

/// Self-tests and interaction probes, kept out of `AppDelegate` on purpose.
///
/// None of this runs during normal use — every routine is gated behind a marker
/// file or an environment variable (see `DebugLog`). They exist because several
/// behaviours in this app can only be verified by really driving the UI:
///
/// * whether hiding actually took effect (needs a real hide, then a rescan),
/// * whether clicking the status item toggles the floating bar (a direct call to
///   `toggle()` would bypass the event monitors and always pass),
/// * whether an `NSMenu` really opens inside a non-activating panel,
/// * whether the floating bar's toggle button follows the state changes.
///
/// Keeping them in a separate type also means the production delegate stays
/// readable, and this file can be excluded from a release build if ever needed.
///
/// Run one with, for example:
///
///     touch /tmp/menubarkeeper-selftest && open /Applications/MenuBarKeeper.app
final class Diagnostics {

    private let delegate: AppDelegate
    private let fold = FoldController.shared

    init(delegate: AppDelegate) {
        self.delegate = delegate
    }

    /// Starts whichever probes were requested. Called once, after launch.
    func startIfRequested() {
        schedule(after: 0.5, when: "autoshow") { [weak self] in
            self?.delegate.showMainWindow()
        }
        schedule(after: 0.8, when: "showbar") {
            FloatingBarController.shared.show()
        }
        schedule(after: 1.0, when: "selftest") { [weak self] in
            self?.runSelfTest()
        }
        schedule(after: 1.5, when: "menutest") { [weak self] in
            self?.runMenuCheck()
        }
        schedule(after: 1.5, when: "bartoggle") { [weak self] in
            self?.runBarToggleCheck()
        }
        schedule(after: 2.0, when: "toggletest") { [weak self] in
            self?.runToggleCheck()
        }
        schedule(after: 2.5, when: "releasecheck") { [weak self] in
            self?.runReleaseCheck()
        }
        schedule(after: 3.0, when: "verify") { [weak self] in
            self?.runFoldVerification()
        }
        schedule(after: 1.2, when: "layoutdump") { [weak self] in
            self?.runLayoutDump()
        }
        schedule(after: 1.8, when: "iconstylecheck") { [weak self] in
            self?.runIconStyleCheck()
        }
        schedule(after: 1.8, when: "rowstatecheck") { [weak self] in
            self?.runRowStateCheck()
        }
        schedule(after: 1.4, when: "windowshot") { [weak self] in
            self?.runWindowShot()
        }
        schedule(after: 1.4, when: "sectiontest") { [weak self] in
            self?.runSectionCheck()
        }
        schedule(after: 1.6, when: "axdump") { [weak self] in
            self?.runTreeDump()
        }
        schedule(after: 1.6, when: "revealcheck") { [weak self] in
            self?.runRevealCheck()
        }
        schedule(after: 1.6, when: "opencheck") { [weak self] in
            self?.runOpenCheck()
        }
        schedule(after: 1.6, when: "sweepcheck") { [weak self] in
            self?.runSweepCheck()
        }
        schedule(after: 1.6, when: "hitprobe") { [weak self] in
            self?.runHitProbe()
        }
        schedule(after: 1.6, when: "clickshot") { [weak self] in
            self?.runClickShot()
        }
        schedule(after: 2.0, when: "barclick") { [weak self] in
            self?.runBarClickCheck()
        }
    }

    /// The interactive probes drive the real menu bar, so only one may run per launch.
    ///
    /// This is not tidiness. Each of them reveals an icon, waits for the bar to go quiet and
    /// then clicks; two running at once means one probe's reveal is the other's "the bar is
    /// still moving", and the log interleaves two timelines that are only readable apart. The
    /// first run that did this produced a sweep whose hits all landed on MenuBarKeeper's own
    /// icon and a control group that failed — both artifacts of the collision, not of the
    /// code under test. Leaving a stale marker file next to a new one is easy enough to do by
    /// accident, so the guard belongs here rather than in the operator's discipline.
    private var exclusiveProbe: String?

    private func claim(_ name: String) -> Bool {
        if let taken = exclusiveProbe {
            report("[probe] \(name) skipped: \(taken) already owns the menu bar this launch")
            return false
        }
        exclusiveProbe = name
        return true
    }

    private func schedule(after delay: TimeInterval, when flag: String, _ body: @escaping () -> Void) {
        guard DebugLog.isEnabled(flag) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body)
    }

    private func report(_ line: String) { DebugLog.write(line) }

    // MARK: - Environment report

    /// Dumps the environment the app is running in: identity, persisted state and
    /// which icon assets actually made it into the bundle.
    ///
    /// Read-only apart from one temporary `UserDefaults` round-trip (proving the
    /// process can write), which is removed again immediately. The user's real
    /// hidden-app selection is never touched.
    private func runSelfTest() {
        let defaults = UserDefaults.standard
        let keys = FoldController.Keys.self

        report("[selftest] bundleID=\(Bundle.main.bundleIdentifier ?? "nil")")
        report("[selftest] version=\(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))")
        report("[selftest] language=\(L10n.effectiveCode) override=\(L10n.language.rawValue)")
        // The effective style against the raw key: an absent key is the case that matters,
        // because that is a fresh install, and there the answer has to be `capsule`.
        report("[selftest] iconStyle=\(MenuBarIconStyle.current.rawValue) "
               + "rawKey=\(defaults.string(forKey: MenuBarIconStyle.defaultsKey) ?? "nil")")
        report("[selftest] hiddenBundles=\(defaults.stringArray(forKey: keys.hidden) ?? [])")
        report("[selftest] releasedBundles=\(defaults.stringArray(forKey: keys.released) ?? [])")
        // The effective value, not the raw key: auto-fold is registered as defaulting
        // to true, so an absent key means "on" and reporting `bool(forKey:)` would
        // contradict what the app actually does.
        report("[selftest] collapseOnLaunch=\(fold.collapsesOnLaunch) "
               + "rawKey=\(defaults.bool(forKey: keys.collapseOnLaunch))")
        report("[selftest] foldedApps=\(fold.foldedApplications.compactMap(\.bundleIdentifier))")
        report("[selftest] isCollapsed=\(fold.isCollapsed)")
        report("[selftest] mechanismAvailable=\(fold.isMechanismAvailable)")
        report("[selftest] axTrusted=\(AccessibilityInventory.isTrusted)")

        if let window = delegate.statusItemWindow {
            report("[selftest] statusWindow frame=\(window.frame) visible=\(window.isVisible) "
                   + "occlusion=\(window.occlusionState.contains(.visible) ? "visible" : "hidden")")
        } else {
            report("[selftest] statusWindow=nil")
        }
        report("[selftest] statusItem.isVisible=\(delegate.isStatusItemVisible)")

        report("[selftest] appIcon=\(describe(AppIcons.appIcon))")
        report("[selftest] menuBar.expanded=\(describe(AppIcons.menuBar(collapsed: false)))")
        report("[selftest] menuBar.collapsed=\(describe(AppIcons.menuBar(collapsed: true)))")
        report("[selftest] statusButton.image=\(describe(delegate.statusItemImage))")

        defaults.set("ok", forKey: "MenuBarKeeper.selftest")
        report("[selftest] writeReadback=\(defaults.string(forKey: "MenuBarKeeper.selftest") ?? "nil")")
        defaults.removeObject(forKey: "MenuBarKeeper.selftest")
    }

    /// One line describing an image: the size the UI lays out with, whether macOS is
    /// recolouring it, and the pixels that actually made it into the bundle.
    ///
    /// Three separate things, and each has gone wrong at least once — a 44 pt icon with
    /// nothing but a 1× representation, a daisy flattened by template recolouring, and an
    /// asset that never reached the bundle at all. Reporting them separately is what makes
    /// the output tell those apart instead of just saying "an image exists".
    private func describe(_ image: NSImage?) -> String {
        guard let image else { return "nil" }
        let reps = image.representations.map { "\($0.pixelsWide)×\($0.pixelsHigh)px" }
        return "\(image.size.width)×\(image.size.height)pt template=\(image.isTemplate) "
            + "reps=[\(reps.joined(separator: ","))]"
    }

    /// Exercises the icon-style picker the way a click does, and reports what changed.
    ///
    /// The wiring is the point. Which artwork a given style resolves to is easy enough to
    /// judge by eye, but "picking a style really redraws the menu bar" runs through four
    /// things — the menu item, the window's action, the stored preference and
    /// `AppDelegate.applyIconStyle` — and a probe that called those directly would prove
    /// nothing about the control the user actually clicks. So this finds the real
    /// `NSPopUpButton` on the content view, fires the real `NSMenuItem` action, and then
    /// looks at the status item's image rather than at the preference alone.
    ///
    /// The stored value is restored exactly as found — including removing the key when it
    /// was absent, which is the state a fresh install is in and the one that has to keep
    /// resolving to the brand capsule.
    private func runIconStyleCheck() {
        guard claim("iconstylecheck") else { return }
        let defaults = UserDefaults.standard
        let key = MenuBarIconStyle.defaultsKey
        let originalRaw = defaults.string(forKey: key)
        let original = MenuBarIconStyle.current

        delegate.showMainWindow()
        after(1.5) { [weak self] in
            guard let self else { return }
            guard let window = NSApp.windows.first(where: {
                $0.isVisible && $0.title == L("window.title")
            }), let content = window.contentView,
                let picker = self.firstDescendant(of: content, as: NSPopUpButton.self) else {
                self.report("[iconstyle] no picker on the main window")
                return
            }

            self.report("[iconstyle] start style=\(original.rawValue) rawKey=\(originalRaw ?? "nil") "
                        + "items=\(picker.itemTitles) selected=\(picker.indexOfSelectedItem) "
                        + "button=\(self.describe(picker.image)) "
                        + "statusItem=\(self.describe(self.delegate.statusItemImage))")

            /// Runs an item's own target/action — exactly what AppKit does on a click, rather
            /// than a shortcut past the wiring this probe exists to check.
            func fire(_ item: NSMenuItem) -> Bool {
                guard let action = item.action, let target = item.target else { return false }
                NSApp.sendAction(action, to: target, from: item)
                return true
            }

            for style in MenuBarIconStyle.allCases where style != original {
                let title = L(style.localizationKey)
                guard let item = picker.item(withTitle: title), fire(item) else {
                    self.report("[iconstyle] no menu item titled \(title)")
                    continue
                }
                self.report("[iconstyle] clicked=\(title) "
                            + "stored=\(defaults.string(forKey: key) ?? "nil") "
                            + "resolved=\(MenuBarIconStyle.current.rawValue) "
                            + "picker.selected=\(picker.indexOfSelectedItem) "
                            + "picker.button=\(self.describe(picker.image)) "
                            + "statusItem=\(self.describe(self.delegate.statusItemImage))")
            }

            // Put it back through the same path, then restore the key itself: writing
            // "capsule" is not the same state as never having written anything.
            if let item = picker.item(withTitle: L(original.localizationKey)) {
                _ = fire(item)
            }
            if let originalRaw {
                defaults.set(originalRaw, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            self.report("[iconstyle] restored style=\(MenuBarIconStyle.current.rawValue) "
                        + "rawKey=\(defaults.string(forKey: key) ?? "nil") "
                        + "picker.selected=\(picker.indexOfSelectedItem) "
                        + "picker.button=\(self.describe(picker.image)) "
                        + "statusItem=\(self.describe(self.delegate.statusItemImage))")
        }
    }

    // MARK: - Row state control

    /// Drives the state daisy at the end of a list row: what it shows at rest, what it shows
    /// under the pointer, and whether clicking it really moves the app.
    ///
    /// The hover step cannot be synthesised the way a click can — there is no event to post that
    /// AppKit will deliver as `mouseEntered` — so the probe puts the control into the state the
    /// tracking area would and reads what it then draws. That is why `isHovering` is settable
    /// rather than private.
    ///
    /// The click goes through the button's own action, the way the icon-style probe fires a menu
    /// item's action: calling `FoldController` directly would pass whether or not the control is
    /// wired to anything.
    ///
    /// Two clicks leave the app where it started, but that is not enough on its own. Un-hiding
    /// is *recorded* (`releasedBundles`: the user asked for this one back), so the selection is
    /// captured up front and put back with `setSelection`, which restores what it found instead
    /// of stacking another decision on top of it.
    private func runRowStateCheck() {
        guard claim("rowstatecheck") else { return }
        delegate.showMainWindow()

        after(1.5) { [weak self] in
            guard let self else { return }
            guard let content = NSApp.windows
                .first(where: { $0.isVisible && $0.title == L("window.title") })?.contentView else {
                self.report("[rowstate] no main window")
                return
            }

            let buttons = self.descendants(of: content, as: StateDaisyButton.self)
            guard !buttons.isEmpty else {
                self.report("[rowstate] no state buttons — is the app list empty?")
                return
            }
            self.report("[rowstate] buttons=\(buttons.count)")

            for (index, button) in buttons.enumerated() {
                let rest = self.describe(button)
                button.isHovering = true
                let hover = self.describe(button)
                button.isHovering = false
                self.report("[rowstate] #\(index) interactive=\(button.isInteractive) "
                            + "rest=\(rest) hover=\(hover)")
            }

            // A picture of the hover look. The swap is the part no number settles: every mark is
            // an 18 pt full-colour image, so only the name written above says which one it is.
            if let shown = buttons.first(where: { $0.isInteractive && $0.isFolded }) {
                shown.isHovering = true
                self.writeWindowShot(to: "/tmp/menubarkeeper-row-hover.png")
                shown.isHovering = false
                self.report("[rowstate] hover shot written while showing \(shown.mark.rawValue)")
            } else {
                self.report("[rowstate] no folded row to photograph")
            }

            guard let button = buttons.first(where: { $0.isInteractive }),
                  let row = self.firstAncestor(of: button, as: AppRowView.self) else {
                self.report("[rowstate] no foldable row to click")
                return
            }

            let bundle = row.entry.bundleIdentifier
            let before = FoldController.shared.selection
            self.report("[rowstate] clicking \(bundle) "
                        + "hidden=\(FoldController.shared.isHidden(bundle)) "
                        + "selection[\(self.describe(before))]")

            func click(_ label: String) {
                guard let action = button.action else {
                    self.report("[rowstate] \(label) the state button has no action wired to it")
                    return
                }
                _ = NSApp.sendAction(action, to: button.target, from: button)
                self.report("[rowstate] \(label) rowMarked=\(row.isMarked) "
                            + "mark=\(button.mark.rawValue) "
                            + "hidden=\(FoldController.shared.isHidden(bundle)) "
                            + "texts=[\(self.texts(of: row))]")
            }
            click("click-1")
            click("click-2")

            FoldController.shared.setSelection(before)
            self.report("[rowstate] restored "
                        + "selection[\(self.describe(FoldController.shared.selection))] "
                        + "hidden=\(FoldController.shared.isHidden(bundle)) "
                        + "texts=[\(self.texts(of: row))]")

            // Then the list as it stands a moment later, row by row, because the interesting
            // failure is a row that says one thing while the selection says another.
            self.after(1.4) {
                let fold = FoldController.shared
                var mismatched: [String] = []
                for row in self.descendants(of: content, as: AppRowView.self) {
                    guard let button = self.firstDescendant(of: row, as: StateDaisyButton.self) else {
                        self.report("[rowstate] \(self.entry(row)) has no state button")
                        continue
                    }
                    guard row.entry.canFold else {
                        // A locked row is not a different kind of row — it has the same mark in
                        // the same place, just with nothing to do — so what is checked about it
                        // is that it has no pointer response at all.
                        self.report("[rowstate] \(self.entry(row)) locked "
                                    + "mark=\(button.mark.rawValue) "
                                    + "interactive=\(button.isInteractive) "
                                    + "tooltip=\(button.toolTip ?? "nil")")
                        continue
                    }
                    let wants = fold.isHidden(row.entry.bundleIdentifier)
                    if wants != button.isFolded { mismatched.append(row.entry.bundleIdentifier) }
                    self.report("[rowstate] \(self.entry(row)) mark=\(button.mark.rawValue) "
                                + "rowSaysFolded=\(button.isFolded) selectionSaysFolded=\(wants) "
                                + "texts=[\(self.texts(of: row))]")
                }
                self.report("[rowstate] mismatched=\(mismatched.isEmpty ? "none" : mismatched.joined(separator: ","))")
            }
        }
    }

    private func entry(_ row: AppRowView) -> String {
        row.entry.bundleIdentifier.isEmpty ? row.entry.displayName : row.entry.bundleIdentifier
    }

    private func describe(_ button: StateDaisyButton) -> String {
        "\(button.mark.rawValue) \(describe(button.image)) tooltip=\(button.toolTip ?? "nil")"
    }

    private func describe(_ selection: FoldController.Selection) -> String {
        "hidden=\(selection.hidden.count) released=\(selection.released.count)"
    }

    // MARK: - Hiding verification

    /// Hides one app for real, rescans, then restores exactly what was there before.
    ///
    /// The accessibility tree is the judge: a hidden app disappears from it. That
    /// makes the result checkable without looking at the screen, which matters
    /// because hidden status items cannot be screenshotted reliably.
    private func runFoldVerification() {
        let original = fold.selection
        let before = MenuBarScanner.scan()
        report("[verify] before: \(before.count) visible, self visible="
               + "\(before.first { $0.isSelf }?.isObservable ?? false)")
        report("[verify] before detail: \(describe(before))")

        guard let target = before.first(where: { $0.canFold && $0.isObservable })?.bundleIdentifier else {
            report("[verify] no suitable target, skipping")
            return
        }
        report("[verify] target=\(target)")

        fold.setHidden(true, for: target)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self else { return }
            self.report("[verify] submitted, rescanning…")
            DispatchQueue.global(qos: .userInitiated).async {
                let after = MenuBarScanner.scan()
                let ownAfter = after.first { $0.isSelf }?.isObservable ?? false
                DispatchQueue.main.async {
                    self.report("[verify] after: \(after.count) visible")
                    self.report("[verify] after detail: \(self.describe(after))")
                    self.report("[verify] target still on menu bar = "
                                + "\(after.first { $0.bundleIdentifier == target }?.isObservable ?? false)"
                                + "  ← expected false")
                    self.report("[verify] self still on menu bar = \(ownAfter)  ← the key check")
                    if let window = self.delegate.statusItemWindow {
                        self.report("[verify] own statusWindow frame=\(window.frame) "
                                    + "visible=\(window.isVisible) "
                                    + "occlusion=\(window.occlusionState.contains(.visible) ? "visible" : "hidden")")
                    }
                    self.report("[verify] isCollapsed=\(self.fold.isCollapsed) "
                                + "lastError=\(self.fold.lastError ?? "nil")")

                    self.fold.restore()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        // Restore the captured selection whole. Putting back only what
                        // was hidden would leave the app this test selected behind in
                        // the user's selection — the test must leave no trace.
                        self.fold.setSelection(original)
                        self.report("[verify] restored: hidden=\(original.hidden.sorted()) "
                                    + "released=\(original.released.sorted())")
                    }
                }
            }
        }
    }

    private func describe(_ entries: [MenuBarAppEntry]) -> String {
        entries
            .map { "\($0.bundleIdentifier)×\($0.itemCount)\($0.isSelf ? "[self]" : "")" }
            .joined(separator: ", ")
    }

    // MARK: - Menu bar accessibility tree

    /// Dumps the menu bar agent's accessibility tree, then asks the one question the dump
    /// exists for: **does a hidden status item survive in the tree?**
    ///
    /// Whether it does decides what "clicking a folded icon" can even mean. If the element
    /// is still there, its menu can be opened with an accessibility press and the icon never
    /// has to reappear. If it is gone, the icon has to be put back on the menu bar first,
    /// clicked, and hidden again — a visible flicker that should only be paid for if there
    /// is no alternative. `AppActions` has claimed "the item does not even appear in the
    /// tree" since 1.0 without this ever being measured; this probe is that measurement.
    private func runTreeDump() {
        report("[ax] ossystem=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        report("[ax] trusted=\(AccessibilityInventory.isTrusted) "
               + "collapsed=\(fold.isCollapsed) "
               + "hidden=\(fold.hiddenBundles.sorted())")

        let nodes = MenuBarAgentInventory.walk()
        report("[ax] nodes=\(nodes.count)")
        for node in nodes {
            let frame = node.frame.map {
                String(format: "(%.0f,%.0f %.0f×%.0f)", $0.minX, $0.minY, $0.width, $0.height)
            } ?? "no-frame"
            report("[ax]   d\(node.depth) pid=\(node.pid) \(node.bundleIdentifier ?? "-") "
                   + "role=\(node.role ?? "-") id=\(node.identifier ?? "-") \(frame) "
                   + "actions=[\(node.actions.joined(separator: ","))]")
        }

        report("[ax] — verdict —")
        for bundle in fold.hiddenBundles.sorted() {
            let items = MenuBarAgentInventory.items(ofBundle: bundle)
            let frames = items.map { item in
                item.frame.map { String(format: "(%.0f,%.0f %.0f×%.0f)", $0.minX, $0.minY, $0.width, $0.height) }
                    ?? "no-frame"
            }
            let pressable = items.filter { $0.actions.contains(MenuBarAgentInventory.pressAction) }.count
            report("[ax] hidden \(bundle): items=\(items.count) frames=[\(frames.joined(separator: " "))] "
                   + "pressed=\(pressable)/\(items.count)")
        }
    }

    /// Reveals a hidden icon, clicks it, and photographs the menu bar either side of the
    /// click — the measurement that decides whether a synthetic click opens a foreign menu.
    ///
    /// The instruments before this one each failed for their own reason, and it is worth
    /// recording which, because the sequence is the point. Reading frames back from the
    /// accessibility tree says what an item *believes* about itself; it reported our item and
    /// the revealed one overlapping by two points, and only a photograph showed that the two
    /// points are real — they are simply adjacent, and both rectangles are honest.
    /// `AXUIElementCopyElementAtPosition` seemed like the direct answer to "what is at this
    /// point", but it searches the frontmost application, so every sample came back as
    /// whatever window sat behind the menu bar.
    ///
    /// A photograph has neither failure mode, and now that this app holds the Screen
    /// Recording permission, it can take one itself. Three shots — before the reveal, after
    /// it, and after the click — turn "the menu did not open" into something that can be
    /// looked at rather than inferred.
    ///
    /// The wait before the click comes from `/tmp/menubarkeeper-clicksettle`, so the threshold
    /// can be found by sweeping it across launches instead of guessing once.
    private func runClickShot() {
        guard claim("clickshot"), let target = targetBundle() else { return }
        let settle = contentsOf("/tmp/menubarkeeper-clicksettle") ?? 0.35
        let gesture = gesture()
        awaitQuiet(within: 6) { [weak self] _ in
            guard let self else { return }
            self.shoot("before")
            self.fold.beginTransientReveal(target)
            self.awaitItem(ofBundle: target, within: 5) { _ in
                self.awaitQuiet(within: 6) { _ in
                    let own = MenuBarAgentInventory.items(ofBundle: FoldController.ownBundleID)
                        .first?.frame
                    let item = MenuBarAgentInventory.items(ofBundle: target).first
                    guard let frame = item?.frame,
                          let point = StatusItemOpener.clickPoint(for: frame) else {
                        self.report("[clickshot] \(target): item not on the bar")
                        self.fold.endTransientReveal()
                        return
                    }
                    self.report("[clickshot] own=\(own.map(self.box) ?? "-") "
                                + "target=\(self.box(frame)) click=\(self.box(CGRect(origin: point, size: .zero)))"
                                + " settle=\(settle)s gesture=\(gesture.label)")
                    self.shoot("revealed")

                    // The wait under test. `revealed` above is taken at the same moment the
                    // production path would click, so the two shots differ only by this.
                    self.after(settle) {
                        let before = self.windowOwners()
                        let menusBefore = MenuBarAgentInventory.openMenus(ofBundle: target)
                        StatusItemOpener.click(at: point, gesture: gesture)
                        self.after(1.0) {
                            let opened = self.newWindows(since: before)
                                .filter { !$0.contains("Window Server") }
                            let menus = MenuBarAgentInventory.openMenus(ofBundle: target)
                                .filter { !menusBefore.contains($0) }
                            self.report("[clickshot] \(settle)s after reveal → windows "
                                        + "\(opened.isEmpty ? "none" : opened.sorted().joined(separator: " "))"
                                        + " · menus "
                                        + "\(menus.isEmpty ? "none" : menus.joined(separator: " "))")
                            self.shoot("clicked")
                            self.fold.endTransientReveal()
                            self.after(1.0) {
                                self.shoot("after")
                                self.report("[clickshot] done")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Runs `screencapture` into `/tmp/menubarkeeper-bar-<label>.png`.
    ///
    /// The strip starts at x = 1200 by default and runs to the right edge, which is where the
    /// items these probes deal with live. Captured at 2× like the rest of the screen, so a
    /// point `x` is at pixel `(x - 1200) × 2`. `from`, `to` and the height are knobs: the
    /// acceptance test for the whole feature has to photograph the *middle* of the screen,
    /// because the answer it is looking for is a window the target app opens for itself.
    ///
    /// Tall rather than menu-bar-high on purpose. The first version captured 32 pt — just the
    /// bar — which cannot show the one thing it was built to look for: **a menu opens below the
    /// menu bar, not in it.** Every capture came back with the icon present and nothing else,
    /// which reads as "no menu" whether or not one was there.
    private var shootHeight: Int {
        Int(contentsOf("/tmp/menubarkeeper-shotheight") ?? 440)
    }

    private func shoot(_ label: String, from left: Int = 1200) {
        let screen = NSScreen.screens.first?.frame ?? .zero
        let width = Int(screen.width) - left
        let path = "/tmp/menubarkeeper-bar-\(label).png"
        try? FileManager.default.removeItem(atPath: path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-R", "\(left),0,\(width),\(shootHeight)", path]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            report("[shot] \(label): could not run screencapture: \(error.localizedDescription)")
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? nil
        report("[shot] \(label): status=\(task.terminationStatus) "
               + "bytes=\(size.map(String.init) ?? "none") path=\(path)")
    }

    /// Drives the whole feature the way a user does: opens the floating bar, clicks the icon
    /// for a folded app, and reports whether that app responded.
    ///
    /// The end-to-end check, and the only one that exercises `iconClicked(_:)` — the reveal,
    /// the aiming, the click, the re-hide and the fallback are all downstream of it. The
    /// earlier probes measured those pieces one at a time and each passed while the feature as
    /// a whole was still unproven, which is exactly the gap a test like this closes.
    ///
    /// It reports two independent signals, because neither is sufficient. A new window owned by
    /// the target is what "the app did something" looks like; but a click that reopens a window
    /// the app already has produces none, which read as failure until a screenshot showed the
    /// app's own window sitting there. `AXMenu` in the target's tree is the narrower, exact
    /// answer for menu-shaped apps. A photograph at `left = 0` settles anything left over.
    private func runBarClickCheck() {
        guard claim("barclick"), let target = targetBundle() else { return }
        let bar = FloatingBarController.shared
        let before = windowOwners()
        let selectionBefore = fold.selection
        let menusBefore = MenuBarAgentInventory.openMenus(ofBundle: target)
        report("[barclick] target=\(target) collapsed=\(fold.isCollapsed) "
               + "folded=\(fold.foldedApplications.compactMap(\.bundleIdentifier).count)")
        bar.show()

        after(1.0) { [weak self] in
            guard let self else { return }
            guard let view = bar.viewForDiagnostics,
                  let button = self.findControl(target, in: view) as? NSButton else {
                self.report("[barclick] \(target): no icon button on the bar")
                bar.hide()
                return
            }
            self.report("[barclick] bar visible=\(bar.isVisible) button=\(self.box(button))")
            self.shoot("barclick-before", from: 0)

            button.performClick(nil)

            // Two seconds: the reveal, the settle, the click, the re-hide, and then whatever
            // the target app takes to put a window up. Measured at about 1.1 s end to end.
            self.after(2.0) {
                let windows = self.newWindows(since: before)
                    .filter { !$0.contains("Window Server") }
                let menus = MenuBarAgentInventory.openMenus(ofBundle: target)
                    .filter { !menusBefore.contains($0) }
                self.report("[barclick] after click: bar visible=\(bar.isVisible) · windows "
                            + "\(windows.isEmpty ? "none" : windows.sorted().joined(separator: " "))"
                            + " · menus \(menus.isEmpty ? "none" : menus.joined(separator: " "))")
                self.report("[barclick] icon back off the menu bar="
                            + "\(MenuBarAgentInventory.items(ofBundle: target).isEmpty)  ← expect true")
                self.report("[barclick] selection unchanged="
                            + "\(self.fold.selection == selectionBefore)  ← expect true")
                self.report("[barclick] lastError=\(self.fold.lastError ?? "nil")")
                self.shoot("barclick-after", from: 0)
                bar.hide()
                self.after(0.8) { self.report("[barclick] done") }
            }
        }
    }

    /// Reports what actually receives a click at each point along the strip a revealed item
    /// and our own item occupy.
    ///
    /// The instrument for one specific disagreement. `sweepcheck` clicks across the rectangle
    /// the tree reports for the target and watches for its menu; when nothing opens, that
    /// result has two readings — the app ignores synthetic clicks, or the rectangle is simply
    /// not where the item is drawn, so the clicks went somewhere else entirely. Reading the
    /// tree again cannot separate them, because the tree is the thing in doubt. Hit-testing
    /// can: it asks the window server who is under the cursor, which is the same question the
    /// click asks. No clicks are posted here, so nothing on screen moves.
    private func runHitProbe() {
        guard claim("hitprobe"), let target = targetBundle() else { return }
        awaitQuiet(within: 6) { [weak self] _ in
            guard let self else { return }
            self.fold.beginTransientReveal(target)
            self.awaitItem(ofBundle: target, within: 5) { items in
                guard let reported = items.first?.frame else {
                    self.report("[hit] \(target): item never appeared")
                    self.fold.endTransientReveal()
                    return
                }
                self.awaitQuiet(within: 6) { _ in
                    let own = MenuBarAgentInventory.items(ofBundle: FoldController.ownBundleID)
                        .first?.frame
                    let settled = MenuBarAgentInventory.items(ofBundle: target).first?.frame
                        ?? reported
                    self.report("[hit] target=\(target)")
                    self.report("[hit] own reported=\(own.map(self.box) ?? "-")")
                    self.report("[hit] target reported=\(self.box(settled)) "
                                + "(first seen \(self.box(reported)))")

                    let from = min(own?.minX ?? settled.minX, settled.minX) - 8
                    let to = max(own?.maxX ?? settled.maxX, settled.maxX) + 8
                    self.walkHit(from: from, to: to, y: settled.midY, step: 4)
                }
            }
        }
    }

    /// One row per sample point, naming the owner of the element under it.
    private func walkHit(from x: CGFloat, to: CGFloat, y: CGFloat, step: CGFloat) {
        guard x <= to else {
            report("[hit] done")
            fold.endTransientReveal()
            return
        }
        let point = CGPoint(x: x, y: y)
        report(String(format: "[hit]   x=%.0f  %@", x,
                      MenuBarAgentInventory.describeElement(at: point)))
        after(0.06) { [weak self] in
            self?.walkHit(from: x + step, to: to, y: y, step: step)
        }
    }

    /// Clicks across the width of a revealed item to find where — if anywhere — it responds.
    ///
    /// The controls established that both routes work and that the aiming is right: a press on
    /// our own status item toggles the bar, and so does a synthetic click at the point
    /// `clickPoint` computes. So "this app's menu did not open" is not an aiming bug in
    /// general — but it could still be one for *this* app, if the rectangle the accessibility
    /// tree reports is not where the item is drawn. Sweeping the whole rectangle tells the two
    /// apart: a hit anywhere means the aim was merely off, no hit anywhere means the item is
    /// not reachable by a synthetic click at all and the app's own quirks are the reason.
    private func runSweepCheck() {
        guard claim("sweepcheck") else { return }
        guard let target = targetBundle() else { return }
        awaitQuiet(within: 6) { [weak self] _ in
            guard let self else { return }
            self.fold.beginTransientReveal(target)
            self.awaitItem(ofBundle: target, within: 5) { items in
                guard let frame = items.first?.frame else {
                    self.report("[sweep] \(target): item never appeared")
                    self.fold.endTransientReveal()
                    return
                }
                self.report("[sweep] \(target) item \(self.box(frame)) quietInterval=\(self.quietInterval)")
                self.awaitQuiet(within: 6) { _ in
                    let settled = MenuBarAgentInventory.items(ofBundle: target).first?.frame ?? frame
                    self.report("[sweep] settled \(self.box(settled))")
                    self.sweep(target, frame: settled, x: settled.minX, hits: [])
                }
            }
        }
    }

    private func sweep(_ target: String, frame: CGRect, x: CGFloat, hits: [CGFloat]) {
        guard x <= frame.maxX else {
            report("[sweep] \(target): hits at x = \(hits.map { String(format: "%.0f", $0) }.joined(separator: " "))"
                   + (hits.isEmpty ? "  ← none: not reachable by a synthetic click" : ""))
            fold.endTransientReveal()
            after(1.0) { [weak self] in
                self?.report("[sweep] re-hidden: icon still on the menu bar="
                             + "\(!MenuBarAgentInventory.items(ofBundle: target).isEmpty)  ← expect false")
            }
            return
        }

        let before = windowOwners()
        let point = CGPoint(x: x, y: frame.midY)
        let barBefore = FloatingBarController.shared.isVisible
        let ownFrame = MenuBarAgentInventory.items(ofBundle: FoldController.ownBundleID).first?.frame
        StatusItemOpener.click(at: point)
        after(0.55) { [weak self] in
            guard let self else { return }
            let barNow = FloatingBarController.shared.isVisible
            let opened = self.newWindows(since: before)
                .filter { !$0.hasPrefix("Window Server@") && !$0.contains("21474836") }
            self.report("[sweep]   x=\(String(format: "%.0f", x)) "
                        + "→ \(opened.isEmpty ? "nothing" : opened.sorted().joined(separator: " "))"
                        + "  bar=\(barBefore)→\(barNow)\(barNow != barBefore ? "  ← HIT OUR OWN ICON" : "")"
                        + "  own=\(ownFrame.map(self.box) ?? "-")")
            if !opened.isEmpty { self.pressEscape() }
            FloatingBarController.shared.hide()
            self.after(0.45) {
                self.sweep(target, frame: frame, x: x + 4,
                           hits: opened.isEmpty ? hits : hits + [x])
            }
        }
    }

    /// The window owners that appeared since `before` — the "did anything open" signal.
    private func newWindows(since before: Set<String>) -> Set<String> {
        windowOwners().subtracting(before)
    }

    /// Puts one hidden icon back on the menu bar and tries to open its own menu.
    ///
    /// This measures the whole "click a folded icon and its own menu opens" path, because the
    /// dump above proves the element has to exist before it can be pressed. One app per run:
    /// the bundle comes from `/tmp/menubarkeeper-opentarget`, so an earlier app's open menu
    /// cannot be mistaken for this one's.
    ///
    /// It is a control experiment, because "the press succeeded and nothing happened" is
    /// ambiguous on its own. **Control**: press MenuBarKeeper's own status item, whose effect
    /// is known — the floating bar toggles — so if that fails the mechanism is wrong and
    /// nothing below it can be believed. **Treatment**: reveal a hidden app and drive it both
    /// ways, an accessibility press and a synthetic click, reporting what opened after each.
    ///
    /// Everything waits for `awaitQuiet` first. This is what the first attempts got wrong:
    /// acting the moment an element appeared, while MenuBarAgent was still re-laying the bar
    /// out, made the control *that cannot fail* fail — it pressed our own icon with no
    /// effect — and sent the investigation after the wrong suspect entirely.
    private func runRevealCheck() {
        guard claim("revealcheck") else { return }
        awaitQuiet(within: 6) { [weak self] quiet in
            guard let self else { return }
            self.report("[reveal] menu bar quiet=\(quiet) collapsed=\(self.fold.isCollapsed) "
                        + "quietInterval=\(self.quietInterval)")

            let own = MenuBarAgentInventory.items(ofBundle: FoldController.ownBundleID)
            self.report("[reveal] control: own items=\(own.count) "
                        + "actions=\(own.first.map { $0.actions.joined(separator: ",") } ?? "-")")
            let barBefore = FloatingBarController.shared.isVisible
            guard let item = own.first else {
                self.report("[reveal] control: own item not found, skipping")
                self.runRevealTreatment()
                return
            }
            let sent = MenuBarAgentInventory.perform(MenuBarAgentInventory.pressAction, on: item.element)
            self.after(0.8) {
                let now = FloatingBarController.shared.isVisible
                self.report("[reveal] control A. press sent=\(sent) bar \(barBefore) → \(now) "
                            + "toggled=\(now != barBefore)  ← expect true")
                FloatingBarController.shared.hide()
                self.after(0.8) { self.runClickControl(item) }
            }
        }
    }

    /// The second control: the **pointer** route the treatment uses, aimed at our own status
    /// item, whose effect is known.
    ///
    /// The press control validates the accessibility route; this one validates everything the
    /// click route depends on — that an `AXPosition` is in the coordinate space a `CGEvent`
    /// wants, that clamping the point into the menu bar strip lands on the item rather than
    /// beside it, and that a synthetic click reaches a status item at all. Without it, "the
    /// target app's menu did not open" has too many explanations to choose between.
    private func runClickControl(_ item: MenuBarAgentInventory.Node) {
        report("[reveal] control B. own item \(item.frame.map(box) ?? "no-frame")")
        guard let frame = item.frame, let point = StatusItemOpener.clickPoint(for: frame) else {
            report("[reveal] control B. not clickable, skipping")
            runRevealTreatment()
            return
        }
        let before = FloatingBarController.shared.isVisible
        report("[reveal] control B. clicking \(point)")
        StatusItemOpener.click(at: point)
        after(0.8) { [weak self] in
            guard let self else { return }
            let now = FloatingBarController.shared.isVisible
            self.report("[reveal] control B. bar \(before) → \(now) toggled=\(now != before)  ← expect true")
            FloatingBarController.shared.hide()
            self.after(0.8) { self.runRevealTreatment() }
        }
    }

    /// The treatment half: reveal a hidden app, then try to open its menu two ways.
    ///
    /// The accessibility press is tried **after** the bar has gone quiet, not the moment the
    /// item appears. That distinction matters: the first attempt pressed the item a tenth of a
    /// second after it came back and concluded from one app that `AXPress` does not work on
    /// third-party items — when it may simply not work on an item the menu bar has not
    /// finished re-laying out around.
    private func runRevealTreatment() {
        guard let target = targetBundle() else {
            report("[reveal] nothing to test, skipping")
            return
        }
        report("[reveal] target=\(target)")

        let windowsBefore = windowOwners()
        let started = ProcessInfo.processInfo.systemUptime
        fold.beginTransientReveal(target)

        awaitItem(ofBundle: target, within: 5) { [weak self] items in
            guard let self else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            self.report(String(format: "[reveal] appeared after %.2fs items=%d", elapsed, items.count))
            guard let item = items.first, let frame = item.frame else {
                self.report("[reveal] never appeared; reverting")
                self.fold.endTransientReveal()
                return
            }
            self.report("[reveal] item \(self.box(frame)) "
                        + "actions=[\(item.actions.joined(separator: ","))]")

            self.awaitQuiet(within: 6) { settled in
                let wait = ProcessInfo.processInfo.systemUptime - started
                self.report(String(format: "[reveal] settled after %.2fs quiet=%@", wait, settled ? "yes" : "no"))
                guard let fresh = MenuBarAgentInventory.items(ofBundle: target).first,
                      let freshFrame = fresh.frame else {
                    self.report("[reveal] item vanished before the press; reverting")
                    self.fold.endTransientReveal()
                    return
                }
                self.report("[reveal] item now \(self.box(freshFrame))")
                // Our own item's frame is reported too: if the reveal moves it on top of the
                // target, the click lands on us and the target's silence is explained.
                self.report("[reveal] own item "
                            + "\(MenuBarAgentInventory.items(ofBundle: FoldController.ownBundleID).first?.frame.map(self.box) ?? "not found")")

                // Route A: an accessibility press needs nothing from the pointer, so if it
                // works it is the whole feature with none of the aiming.
                DispatchQueue.global().asyncAfter(deadline: .now() + 3.5) { self.pressEscape() }
                let pressed = MenuBarAgentInventory.perform(MenuBarAgentInventory.pressAction,
                                                            on: fresh.element)
                self.report("[reveal] A. AXPress sent=\(pressed)")
                self.after(0.9) {
                    let opened = self.newWindows(since: windowsBefore)
                    self.report("[reveal] A. opened=\(opened.sorted())")
                    guard opened.isEmpty else {
                        // A route that already opened something makes route B unmeasurable —
                        // the next click would land in the open menu, not on the item.
                        self.report("[reveal] B. skipped: A opened \(opened.sorted())")
                        self.finishTreatment(target, since: windowsBefore)
                        return
                    }
                    guard let point = StatusItemOpener.clickPoint(for: freshFrame) else {
                        self.report("[reveal] B. no click point for \(self.box(freshFrame))")
                        self.finishTreatment(target, since: windowsBefore)
                        return
                    }
                    self.report("[reveal] B. clicking \(point)")
                    StatusItemOpener.click(at: point)
                    self.after(0.9) {
                        self.report("[reveal] B. opened=\(self.newWindows(since: windowsBefore).sorted())")
                        self.finishTreatment(target, since: windowsBefore)
                    }
                }
            }
        }
    }

    /// Hides the revealed icon again and reports whether anything opened, plus whether the
    /// selection survived — the two things a click must not get wrong.
    private func finishTreatment(_ target: String, since windowsBefore: Set<String>) {
        fold.endTransientReveal()
        after(1.0) { [weak self] in
            guard let self else { return }
            self.report("[reveal] after re-hide: icon still on the menu bar="
                        + "\(!MenuBarAgentInventory.items(ofBundle: target).isEmpty)  ← expect false")
            self.report("[reveal] after re-hide: still open="
                        + "\(self.newWindows(since: windowsBefore).sorted())")
            self.report("[reveal] after re-hide: hidden=\(self.fold.hiddenBundles.contains(target)) "
                        + "released=\(self.fold.releasedBundles.contains(target)) "
                        + "isCollapsed=\(self.fold.isCollapsed) "
                        + "lastError=\(self.fold.lastError ?? "nil")")
        }
    }

    /// The bundle to act on: the one named in `/tmp/menubarkeeper-opentarget`, else the first
    /// app in the hidden area. One target per launch keeps a previous app's open menu from
    /// being mistaken for this one's.
    private func targetBundle() -> String? {
        if let named = (try? String(contentsOfFile: "/tmp/menubarkeeper-opentarget",
                                     encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines), !named.isEmpty {
            return named
        }
        return fold.foldedApplications.first.map { $0.bundleIdentifier ?? "" }
    }

    private func box(_ rect: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0f×%.0f)", rect.minX, rect.minY, rect.width, rect.height)
    }

    /// A number passed in through a file, or nil if the file is absent or unreadable.
    ///
    /// The probes need knobs — how long to wait, which app to act on — and `open -a` does not
    /// carry the shell's environment into the app, so a file is the channel that works.
    private func contentsOf(_ path: String) -> Double? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The click shape for this launch, from `/tmp/menubarkeeper-gesture`, else the shipped one.
    ///
    /// Format: `state:moveToDown:downToUp:tap`, e.g. `hid:0.08:0.10:cghid`. Anything missing
    /// falls back to `Gesture.standard`, so an empty file means "what the app does".
    private func gesture() -> StatusItemOpener.Gesture {
        var shape = StatusItemOpener.Gesture.standard
        guard let text = try? String(contentsOfFile: "/tmp/menubarkeeper-gesture",
                                     encoding: .utf8) else { return shape }
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
            .map(String.init)
        if parts.count > 0 {
            switch parts[0] {
            case "hid": shape.stateID = .hidSystemState
            case "combined": shape.stateID = .combinedSessionState
            case "private": shape.stateID = .privateState
            default: break
            }
        }
        if parts.count > 1, let value = Double(parts[1]) { shape.moveToDown = value }
        if parts.count > 2, let value = Double(parts[2]) { shape.downToUp = value }
        if parts.count > 3 {
            switch parts[3] {
            case "cghid": shape.location = .cghidEventTap
            case "session": shape.location = .cgSessionEventTap
            case "annotated": shape.location = .cgAnnotatedSessionEventTap
            default: break
            }
        }
        return shape
    }

    /// Polls the accessibility tree until the app owns a menu bar item, or gives up.
    ///
    /// Polling rather than a fixed delay: the reveal is applied by the system
    /// asynchronously and the delay is not documented anywhere, so the honest thing is to
    /// wait for the condition and record how long it took.
    private func awaitItem(ofBundle bundle: String,
                           within deadline: TimeInterval,
                           then body: @escaping ([MenuBarAgentInventory.Node]) -> Void) {
        let limit = Date().addingTimeInterval(deadline)
        func poll() {
            guard Date() < limit else {
                body([])
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let items = MenuBarAgentInventory.items(ofBundle: bundle)
                DispatchQueue.main.async {
                    if items.isEmpty {
                        self.after(0.1, poll)
                    } else {
                        body(items)
                    }
                }
            }
        }
        poll()
    }

    /// How long the menu bar has to hold still before a probe will touch it.
    ///
    /// Read from `/tmp/menubarkeeper-openquiet` when present, so the threshold can be swept
    /// without a rebuild — which is the only way to find out what the threshold actually is.
    private var quietInterval: TimeInterval {
        guard let text = try? String(contentsOfFile: "/tmp/menubarkeeper-openquiet",
                                     encoding: .utf8),
              let value = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 1.2
        }
        return value
    }

    /// Waits until the menu bar stops changing shape, then calls back with whether it really
    /// did go quiet (as opposed to the deadline arriving first).
    ///
    /// The tree is a *model*, and it settles well before the window server does: an item can
    /// report its final frame while MenuBarAgent is still re-laying the bar out around it, and
    /// a click during that is simply swallowed. Waiting for the model to stop changing is the
    /// closest thing to a readiness signal the system offers, and it turned a control that
    /// failed for no visible reason into one that passes every time.
    private func awaitQuiet(within deadline: TimeInterval, then body: @escaping (Bool) -> Void) {
        let limit = Date().addingTimeInterval(deadline)
        var lastSignature = ""
        var stableSince = Date()

        func poll() {
            DispatchQueue.global(qos: .userInitiated).async {
                // Position and width only: enough to notice a re-layout, and integers so that
                // sub-pixel jitter cannot keep the bar "changing" forever.
                let signature = MenuBarAgentInventory.walk()
                    .compactMap { node -> String? in
                        guard let frame = node.frame else { return nil }
                        return "\(node.bundleIdentifier ?? "-")@\(Int(frame.minX)),"
                            + "\(Int(frame.minY)),\(Int(frame.width))"
                    }
                    .joined(separator: "|")
                DispatchQueue.main.async {
                    if signature != lastSignature {
                        lastSignature = signature
                        stableSince = Date()
                    }
                    let quiet = Date().timeIntervalSince(stableSince) >= self.quietInterval
                    guard quiet || Date() >= limit else {
                        self.after(0.15, poll)
                        return
                    }
                    body(quiet)
                }
            }
        }
        poll()
    }

    /// Drives the real "click a folded icon" path for several apps and checks the result.
    ///
    /// The control experiment above establishes that the mechanism works; this one covers the
    /// code that ships, app by app, because "one app opens its menu" is not "clicking the bar
    /// opens menus". It runs three apps rather than one on purpose: the third-party status
    /// items in a menu bar are written by different people and there is no guarantee they all
    /// behave alike, so a single pass would be a sample, not a check.
    ///
    /// Three things are asserted, and the third is the one most likely to rot:
    ///
    /// * a menu window belonging to the app appeared,
    /// * the icon is gone again afterwards — the reveal really is transient,
    /// * the user's selection is **untouched**. A reveal must not read as a release: if it
    ///   did, the app would stop being folded on the next launch, and the symptom would only
    ///   show up tomorrow.
    private func runOpenCheck() {
        guard claim("opencheck") else { return }
        let selectionBefore = fold.selection
        // One target per launch, so the measurement is not contaminated by the previous
        // app's menu still being up. The bundle comes from a file rather than an environment
        // variable because `open` does not carry the shell's environment across.
        let requested = (try? String(contentsOfFile: "/tmp/menubarkeeper-opentarget",
                                     encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let targets: [String]
        if let requested, !requested.isEmpty {
            targets = [requested]
        } else {
            targets = Array(fold.foldedApplications.compactMap(\.bundleIdentifier).prefix(3))
        }
        guard !targets.isEmpty else {
            report("[open] nothing hidden, skipping")
            return
        }
        report("[open] collapsed=\(fold.isCollapsed) targets=\(targets)")
        walk(targets, index: 0, selectionBefore: selectionBefore)
    }

    private func walk(_ targets: [String], index: Int, selectionBefore: FoldController.Selection) {
        guard index < targets.count else {
            after(1.2) { [weak self] in
                guard let self else { return }
                let after = self.fold.selection
                self.report("[open] settled: isCollapsed=\(self.fold.isCollapsed) "
                            + "hidden=\(after.hidden.count) released=\(after.released.count) "
                            + "unchanged=\(after == selectionBefore)  ← expect true")
                self.report("[open] settled: still folded off the menu bar = "
                            + "\(targets.allSatisfy { MenuBarAgentInventory.items(ofBundle: $0).isEmpty }) "
                            + "  ← expect true")
                self.report("[open] lastError=\(self.fold.lastError ?? "nil")")
            }
            return
        }

        let bundle = targets[index]
        // Whatever is already open is reported, so a stray window from an earlier step shows
        // up as such instead of being read as this app's menu.
        let windowsBefore = windowOwners()
        report("[open] \(bundle): before: \(windowsBefore.sorted().joined(separator: " "))")

        var clicked: Bool?
        // The timeline starts before the click, not after, because the questions are about
        // when things happen: whether a menu appeared at all, and whether the re-hide at
        // +0.45 s is what took it away.
        recordTimeline(since: windowsBefore, for: 3.5) { [weak self] timeline in
            guard let self else { return }
            self.report("[open] \(bundle): clicked=\(clicked.map(String.init) ?? "-") "
                        + "timeline=\(timeline)")
            self.awaitOffMenuBar(bundle, within: 4.0) { gone in
                self.report("[open] \(bundle): icon back off the menu bar=\(gone)  ← expect true")
                self.report("[open] \(bundle): now open: "
                            + "\(self.newWindows(since: windowsBefore).sorted().joined(separator: " "))")
                self.pressEscape()
                self.after(0.9) {
                    self.walk(targets, index: index + 1, selectionBefore: selectionBefore)
                }
            }
        }
        StatusItemOpener.open(bundleIdentifier: bundle) { clicked = $0 }
    }

    /// Samples the window owners every 50 ms and reports only the changes, as
    /// `seconds:what appeared`.
    ///
    /// A single "did a menu open" check cannot tell "never opened" from "opened and was
    /// closed again", and those two need opposite fixes — one is the click missing, the other
    /// is the re-hide being too eager. Sampling the whole window over time is what separates
    /// them, at the cost of a poll that a slide of a few milliseconds either way cannot
    /// mislead.
    private func recordTimeline(since before: Set<String>,
                                for duration: TimeInterval,
                                then body: @escaping (String) -> Void) {
        let start = ProcessInfo.processInfo.systemUptime
        var events: [String] = []
        var last: Set<String> = []

        func tick() {
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let now = newWindows(since: before)
            if now != last {
                events.append(String(format: "%.2f:%@", elapsed,
                                     now.isEmpty ? "—" : now.sorted().joined(separator: "+")))
                last = now
            }
            guard elapsed < duration else {
                body(events.joined(separator: "   "))
                return
            }
            after(0.05, tick)
        }
        tick()
    }

    /// Polls until the app owns no item on the menu bar. `false` means it never left.
    private func awaitOffMenuBar(_ bundle: String,
                                 within deadline: TimeInterval,
                                 then body: @escaping (Bool) -> Void) {
        let limit = Date().addingTimeInterval(deadline)
        func poll() {
            DispatchQueue.global(qos: .userInitiated).async {
                let gone = MenuBarAgentInventory.items(ofBundle: bundle).isEmpty
                DispatchQueue.main.async {
                    guard !gone, Date() < limit else {
                        body(gone)
                        return
                    }
                    self.after(0.2, poll)
                }
            }
        }
        poll()
    }


    /// The owner and layer of every window on screen.
    ///
    /// Used as "did a menu open?" evidence: a menu is a window belonging to the app that
    /// owns the status item, so it shows up here as an owner that was not there before.
    /// Owner names and layers need no Screen Recording permission — only window *titles*
    /// do, and they are not used.
    private func windowOwners() -> Set<String> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return Set(list.compactMap { info in
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  let layer = info[kCGWindowLayer as String] as? Int else { return nil }
            return "\(owner)@\(layer)"
        })
    }

    // MARK: - Interaction probes

    /// Walks one app through select → release and reports whether the release was
    /// recorded.
    ///
    /// That record is what stops the next launch's auto-detection from folding the app
    /// straight back in, so it is worth exercising rather than inferring. Leaves the app
    /// released, which is the state a released app is supposed to be in.
    private func runReleaseCheck() {
        let before = MenuBarScanner.scan()
        guard let target = before.first(where: { $0.canFold && $0.isObservable })?.bundleIdentifier
                ?? fold.hiddenBundles.subtracting(fold.releasedBundles).sorted().first else {
            report("[release] no suitable target, skipping")
            return
        }
        report("[release] target=\(target)")

        fold.setHidden(true, for: target)
        report("[release] after select: hidden=\(fold.hiddenBundles.contains(target)) "
               + "released=\(fold.releasedBundles.contains(target))  ← expect true false")

        after(0.6) { [weak self] in
            guard let self else { return }
            self.fold.setHidden(false, for: target)
            self.report("[release] after release: hidden=\(self.fold.hiddenBundles.contains(target)) "
                        + "released=\(self.fold.releasedBundles.contains(target))  ← expect false true")
            let defaults = UserDefaults.standard
            self.report("[release] persisted hidden="
                        + "\(defaults.stringArray(forKey: FoldController.Keys.hidden) ?? [])")
            self.report("[release] persisted released="
                        + "\(defaults.stringArray(forKey: FoldController.Keys.released) ?? [])")
            self.report("[release] isCollapsed=\(self.fold.isCollapsed) "
                        + "lastError=\(self.fold.lastError ?? "nil")")
        }
    }

    /// Clicks the status item three times and asserts the floating bar toggles.
    ///
    /// The bug this guards against: the click is seen by the outside-click monitor
    /// first, which hides the panel, and only then does the status item action fire
    /// and show it again — so the second click appears to do nothing. Calling
    /// `toggle()` directly cannot detect that, because it skips the monitors.
    private func runToggleCheck() {
        guard let window = delegate.statusItemWindow else {
            report("[toggle] no statusWindow, skipping")
            return
        }
        let bar = FloatingBarController.shared
        let point = NSPoint(x: window.frame.midX, y: window.frame.midY)
        report("[toggle] axTrusted=\(AccessibilityInventory.isTrusted)")
        report("[toggle] icon frame=\(window.frame) initial isVisible=\(bar.isVisible)")

        click(at: point)
        after(0.8) { [weak self] in
            guard let self else { return }
            self.report("[toggle] after click 1: isVisible=\(bar.isVisible)  ← expect true")
            self.click(at: point)
            self.after(0.8) {
                self.report("[toggle] after click 2: isVisible=\(bar.isVisible)  ← expect false")
                self.click(at: point)
                self.after(0.8) {
                    self.report("[toggle] after click 3: isVisible=\(bar.isVisible)  ← expect true")
                }
            }
        }
    }

    /// Opens the context menu of the first hidden app and logs its structure.
    ///
    /// The menu runs a synchronous event-tracking loop, so this call blocks until
    /// the menu closes; an Escape is queued in advance to end it.
    private func runMenuCheck() {
        FloatingBarController.shared.show()
        after(0.5) { [weak self] in
            guard let self else { return }
            // The main thread is parked inside menu tracking, so the Escape has to be
            // posted from a background queue.
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                self.pressEscape()
            }
            let opened = FloatingBarController.shared.debugOpenFirstIconMenu()
            self.report("[menu] menu closed (opened=\(opened))")
        }
    }

    /// Toggles the collapsed state once and checks that the floating bar's toggle
    /// button flipped. This also exercises `onStateChange → refreshIfVisible`.
    private func runBarToggleCheck() {
        let bar = FloatingBarController.shared
        bar.show()
        guard let initial = bar.debugToggleSymbol() else {
            report("[bartoggle] no toggle button in the bar, skipping")
            return
        }
        report("[bartoggle] before: isCollapsed=\(fold.isCollapsed) symbol=\(initial)")

        fold.toggleCollapsed()
        after(1.5) { [weak self] in
            guard let self else { return }
            let updated = bar.debugToggleSymbol() ?? "nil"
            self.report("[bartoggle] after: isCollapsed=\(self.fold.isCollapsed) symbol=\(updated)")
            self.report("[bartoggle] flipped = \(updated != initial)  ← expect true")
            self.report("[bartoggle] lastError=\(self.fold.lastError ?? "nil")")
            self.fold.toggleCollapsed()
            self.after(1.2) {
                self.report("[bartoggle] restored: isCollapsed=\(self.fold.isCollapsed)")
            }
        }
    }

    // MARK: - Layout

    /// Logs the geometry of the app list.
    ///
    /// Geometry is the one thing a screenshot cannot report. Ten rows laid out on top of
    /// each other look exactly like a single row, and "the list did not render" is
    /// indistinguishable by eye from "the list rendered as a pile at the origin". Reading
    /// the frames back turns both into numbers that can be compared before and after a fix.
    private func runLayoutDump() {
        delegate.showMainWindow()
        after(1.5) { [weak self] in
            guard let self else { return }
            guard let window = NSApp.windows.first(where: {
                $0.isVisible && $0.title == L("window.title")
            }), let content = window.contentView else {
                self.report("[layout] no main window; titles=\(NSApp.windows.map(\.title))")
                return
            }
            guard let scroll = self.firstDescendant(of: content, as: NSScrollView.self),
                  let document = scroll.documentView else {
                self.report("[layout] no list found under the content view")
                return
            }

            self.report("[layout] content  \(self.box(content))")
            self.report("[layout] scroll   \(self.box(scroll))")
            self.report("[layout] clip     \(self.box(scroll.contentView))")
            self.report("[layout] document \(self.box(document))")

            guard let stack = document.subviews.first(where: { $0 is NSStackView })
                    as? NSStackView else {
                self.report("[layout] document has no stack; subviews="
                            + "\(document.subviews.map { "\(type(of: $0))" })")
                return
            }
            self.report("[layout] stack    \(self.box(stack)) arranged=\(stack.arrangedSubviews.count) "
                        + "hidden=\(stack.arrangedSubviews.filter(\.isHidden).count) "
                        + "fit=\(stack.fittingSize) "
                        + "orientation=\(stack.orientation == .vertical ? "vertical" : "horizontal") "
                        + "alignment=\(stack.alignment.rawValue)")

            let rows = stack.arrangedSubviews.compactMap { $0 as? AppRowView }
            self.report("[layout] rows=\(rows.count) of \(stack.arrangedSubviews.count) arranged")
            for (index, row) in rows.enumerated() {
                self.report("[layout]   row[\(index)] \(self.box(row)) "
                            + "fit=\(row.fittingSize) marked=\(row.isMarked)")
            }
            if let first = rows.first, let inner = first.subviews.first {
                self.report("[layout]   row[0] content \(self.box(inner)) type=\(type(of: inner))")
                for (index, piece) in inner.subviews.enumerated() {
                    self.report("[layout]     piece[\(index)] \(type(of: piece)) \(self.box(piece))")
                }
            }
            self.reportFooterControls(content)
        }
    }

    /// Reports the footer controls' frames and whether any two of them collide.
    ///
    /// Overlap is the one layout fault that leaves no trace: every constraint can be
    /// satisfied while two controls sit on top of each other, and AppKit logs nothing —
    /// a row of controls anchored from the left and from the right with nothing linking
    /// them simply passes through one another once the strings grow. Comparing frames is
    /// what turns "the buttons overlap in English" into a number that can be checked
    /// before and after a fix.
    ///
    /// The same comparison now covers the title row, which gained the language tab: a
    /// truncated headline and an overlapping one are different faults and both are visible
    /// here.
    private func reportFooterControls(_ content: NSView) {
        // Direct children only: the row checkboxes live inside the scroll view and would
        // otherwise be counted as footer controls.
        let controls = content.subviews.compactMap { $0 as? NSControl }
        for control in controls {
            report("[layout] control \(name(of: control)) \(box(control))")
        }
        reportHeadlineFit(in: content)

        var collisions: [String] = []
        for i in controls.indices {
            for j in controls.indices where j > i {
                let overlap = controls[i].frame.intersection(controls[j].frame)
                if !overlap.isNull, overlap.width > 0, overlap.height > 0 {
                    collisions.append("\(name(of: controls[i]))⟷\(name(of: controls[j]))")
                }
            }
        }
        report("[layout] control overlap = \(!collisions.isEmpty)"
               + (collisions.isEmpty ? "" : "  ← \(collisions.joined(separator: " "))"))
    }

    /// Reports how much of the state headline survives beside the language tab, and whether
    /// that tab agrees with the language actually in force.
    ///
    /// The headline gives way when the two do not both fit, and that is invisible in a frame
    /// dump: a clipped label reports the width it was handed, not the width its text wants, so
    /// the only way to see the clipping is to compare the two. A negative `spare` means
    /// characters are being cut off — which, for the sentence that is the window's whole
    /// headline, is worth failing on rather than discovering by eye.
    ///
    /// The agreement check guards the other half of the tab's contract. It resolves from the
    /// *effective* language rather than the stored one, so an unselected tab or one showing the
    /// wrong half would send the user clicking to find out which language they are in — and a
    /// click costs a restart.
    private func reportHeadlineFit(in content: NSView) {
        guard let label = findControl("stateHeadline", in: content) as? NSTextField else {
            report("[layout] state headline not found")
            return
        }
        let wanted = label.intrinsicContentSize.width
        let spare = label.frame.width - wanted
        report("[layout] headline given=\(Int(label.frame.width)) wanted=\(Int(wanted)) "
               + "spare=\(Int(spare)) truncated=\(spare < -0.5)")
        report("[layout] headline text=\"\(label.stringValue)\"")

        guard let tabs = findControl("languageTabs", in: content) as? NSSegmentedControl else {
            report("[layout] language tab not found")
            return
        }
        let chosen = tabs.selectedSegment >= 0
            ? (tabs.label(forSegment: tabs.selectedSegment) ?? "?")
            : "none"
        let expected = L10n.effectiveCode.hasPrefix("zh") ? "中" : "EN"
        report("[layout] language tab shows=\(chosen) effective=\(L10n.effectiveCode) "
               + "override=\(L10n.language.rawValue) agrees=\(chosen == expected)")
    }

    private func name(of control: NSControl) -> String {
        if let segmented = control as? NSSegmentedControl {
            return "segmented[selected=\(segmented.selectedSegment)]"
        }
        if let popup = control as? NSPopUpButton {
            return "popup[\(popup.titleOfSelectedItem ?? "-")]"
        }
        if let button = control as? NSButton {
            return "button[\(button.title)]"
        }
        return "\(type(of: control))"
    }

    /// Writes a PNG of the main window, rendered straight from the view hierarchy.
    ///
    /// Frames being right is not the same as the window drawing: a row can be laid out
    /// correctly and still paint nothing.
    private func runWindowShot() {
        delegate.showMainWindow()
        // Deliberately patient. Hiding is applied by the system a second or two after the
        // submission, so a shot taken too early shows a window mid-settle — including the
        // "it does not look applied" state that the window is about to correct itself out of.
        after(4.0) { [weak self] in
            self?.writeWindowShot(to: "/tmp/menubarkeeper-window.png")
        }
    }

    /// Writes a PNG of the main window, rendered straight from the view hierarchy.
    ///
    /// Nothing has to be in front of the window and no Screen Recording permission is needed,
    /// which also makes it repeatable.
    ///
    /// The bitmap starts transparent and the content view paints no background of its own, so
    /// the window's own colour is laid down first. Without it a dark-appearance window renders
    /// as light text over nothing: the PNG composites onto white and every label disappears,
    /// which is indistinguishable from a layout that has collapsed. Painting the background in
    /// the appearance the views will actually be drawn in is what keeps light and dark both
    /// readable, instead of pinning the shot to one theme and being wrong half the time.
    private func writeWindowShot(to path: String) {
        let window = NSApp.windows.first { $0.isVisible && $0.title == L("window.title") }
        guard let view = window?.contentView else {
            report("[shot] no main window; titles=\(NSApp.windows.map(\.title))")
            return
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            report("[shot] could not allocate a bitmap for \(view.bounds)")
            return
        }

        let appearance = view.effectiveAppearance
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            appearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                NSRect(origin: .zero, size: view.bounds.size).fill()
            }
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        view.cacheDisplay(in: view.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            report("[shot] PNG encoding failed")
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            report("[shot] wrote \(path) \(rep.pixelsWide)×\(rep.pixelsHigh) "
                   + "appearance=\(appearance.name.rawValue)")
        } catch {
            report("[shot] write failed: \(error.localizedDescription)")
        }
    }

    /// Opens and closes the system section and reports what the list did.
    ///
    /// The section is presentational — nothing is submitted to the system — but "the group
    /// did not open" is invisible in a frame dump of a window whose rows all live in one
    /// list, and a row can be un-hidden, laid out correctly and still sit below the fold.
    /// This drives the real control through its target/action and reports the row counts
    /// plus whether the section ends up on screen.
    private func runSectionCheck() {
        delegate.showMainWindow()
        after(2.2) { [weak self] in
            guard let self,
                  let window = NSApp.windows.first(where: {
                      $0.isVisible && $0.title == L("window.title")
                  }),
                  let content = window.contentView,
                  let button = self.sectionHeader(in: content) else {
                self?.report("[section] no disclosure header found, skipping")
                return
            }
            self.report("[section] before: \(self.sectionState(in: content)) "
                        + "header frame=\(button.frame)")

            // `performClick` rather than a posted mouse click: a click goes to whatever
            // window is frontmost at those coordinates, and a probe running in the
            // background has no way to guarantee that is this one — the app can be behind
            // the window the user is working in. This still runs the real target/action
            // path, which is the part that can break. Coordinates are only trustworthy for
            // a window the probe itself just brought to the front.
            button.performClick(nil)
            self.after(0.7) {
                self.report("[section] after click 1: \(self.sectionState(in: content))  ← expect 4 more shown")
                self.reportRowColumns(in: content)
                self.writeWindowShot(to: "/tmp/menubarkeeper-window-expanded.png")
                button.performClick(nil)
                self.after(0.7) {
                    self.report("[section] after click 2: \(self.sectionState(in: content))  ← expect back to 4 hidden")
                }
            }
        }
    }

    /// The section header, found by identifier.
    private func sectionHeader(in view: NSView) -> NSButton? {
        findControl("systemSectionHeader", in: view) as? NSButton
    }

    /// Finds a control the window labelled for the probe. Looking a control up any other way
    /// does not work: one built from an SF Symbol has no image name to match on, and matching
    /// a label by its font size is a guess that breaks the moment the design changes.
    private func findControl(_ identifier: String, in view: NSView) -> NSControl? {
        if let control = view as? NSControl, control.identifier?.rawValue == identifier {
            return control
        }
        for sub in view.subviews {
            if let found = findControl(identifier, in: sub) { return found }
        }
        return nil
    }

    private func sectionState(in content: NSView) -> String {
        guard let stack = listStack(in: content),
              let scroll = firstDescendant(of: content, as: NSScrollView.self),
              let document = scroll.documentView else { return "no list" }
        let rows = stack.arrangedSubviews.compactMap { $0 as? AppRowView }
        let shown = rows.filter { !$0.isHidden }.count
        // Whether the last row is on screen, measured against the part of the document the
        // scroll view is actually showing. Converting a row into the clip view does *not*
        // account for the scroll offset — a row reported at 560..604 with a 433 pt viewport
        // looked off-screen while the window was showing it.
        let visibleRect = scroll.contentView.documentVisibleRect
        let last = rows.last.map { $0.convert($0.bounds, to: document) }
        let lastVisible = last.map { visibleRect.intersects($0) } ?? false
        return "rows=\(rows.count) shown=\(shown) hidden=\(rows.count - shown) "
            + "document=\(Int(document.frame.height)) "
            + "showing=\(Int(visibleRect.minY))..\(Int(visibleRect.maxY)) "
            + "lastRowAt=\(last.map { String(format: "%.0f..%.0f", $0.minY, $0.maxY) } ?? "-") "
            + "lastRowVisible=\(lastVisible)"
    }

    /// Reports the x of the count label in a row of each kind.
    ///
    /// The two sections share one list, so their counts have to sit in the same column.
    /// A row without a checkbox has to reserve that column, and "reserved" is only correct
    /// if the numbers line up — which is a measurement, not an assumption.
    private func reportRowColumns(in content: NSView) {
        guard let stack = listStack(in: content) else { return }
        let rows = stack.arrangedSubviews.compactMap { $0 as? AppRowView }
        for (kind, row) in [("foldable", rows.first { $0.entry.canFold }),
                            ("locked", rows.first { !$0.entry.canFold })] {
            guard let row else { continue }
            // The inner stack holds the icon, the (nested) title stack, the count label and
            // the checkbox-or-spacer. Only the count label is a direct text field.
            let pieces = row.subviews.first?.subviews ?? []
            guard let count = pieces.compactMap({ $0 as? NSTextField }).first else {
                report("[section] \(kind) row: no count label")
                continue
            }
            report("[section] \(kind) row count label at x=\(count.frame.origin.x) "
                   + "right=\(count.frame.maxX) pieces=\(pieces.count)")
        }
    }

    private func listStack(in content: NSView) -> NSStackView? {
        guard let scroll = firstDescendant(of: content, as: NSScrollView.self),
              let document = scroll.documentView else { return nil }
        return document.subviews.first(where: { $0 is NSStackView }) as? NSStackView
    }

    private func box(_ view: NSView) -> String {
        let frame = view.frame
        return String(format: "(%.1f,%.1f %.1f×%.1f) tamic=%@",
                      frame.origin.x, frame.origin.y, frame.width, frame.height,
                      view.translatesAutoresizingMaskIntoConstraints ? "Y" : "n")
    }

    private func firstDescendant<T: NSView>(of view: NSView, as type: T.Type) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews {
            if let found = firstDescendant(of: sub, as: type) { return found }
        }
        return nil
    }

    /// Every view of a type below this one, in the order they were added — the list rows, or
    /// the state buttons they contain, rather than just the first of them.
    private func descendants<T: NSView>(of view: NSView, as type: T.Type) -> [T] {
        var found: [T] = []
        if let match = view as? T { found.append(match) }
        for sub in view.subviews { found.append(contentsOf: descendants(of: sub, as: type)) }
        return found
    }

    private func firstAncestor<T: NSView>(of view: NSView, as type: T.Type) -> T? {
        var current = view.superview
        while let view = current {
            if let match = view as? T { return match }
            current = view.superview
        }
        return nil
    }

    /// Every label under a view, in drawing order. Enough to see what a row is saying without
    /// the probe having to know which field is which, which is the point: a row is a picture
    /// plus some words, and the words are the part a check can read.
    private func texts(of view: NSView) -> String {
        descendants(of: view, as: NSTextField.self).map(\.stringValue).joined(separator: " | ")
    }

    // MARK: - Synthetic input

    private func after(_ delay: TimeInterval, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body)
    }

    /// Posts a synthetic mouse click. `point` is in AppKit **screen** coordinates with a
    /// bottom-left origin — which is what `NSWindow.convertPoint(toScreen:)` returns, and
    /// *not* what a view's frame is in. The conversion to the top-left origin CGEvent
    /// expects is why passing a window-local point looks like it works on a window parked
    /// in the top-left corner of the screen and fails anywhere else.
    private func click(at point: NSPoint, rightButton: Bool = false) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let target = CGPoint(x: point.x, y: top - point.y)
        let button: CGMouseButton = rightButton ? .right : .left
        let down: CGEventType = rightButton ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = rightButton ? .rightMouseUp : .leftMouseUp

        post(.mouseMoved, source: source, at: target, button: .left)
        Thread.sleep(forTimeInterval: 0.02)
        post(down, source: source, at: target, button: button)
        Thread.sleep(forTimeInterval: 0.02)
        post(up, source: source, at: target, button: button)
    }

    private func post(_ type: CGEventType, source: CGEventSource,
                      at point: CGPoint, button: CGMouseButton) {
        CGEvent(mouseEventSource: source, mouseType: type,
                mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
    }

    /// Posts one Escape key press — a less intrusive way to dismiss a menu than
    /// clicking somewhere on screen.
    private func pressEscape() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let escape: CGKeyCode = 53
        for isDown in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: escape, keyDown: isDown)?
                .post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Bundle version helpers

extension Bundle {

    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var buildVersion: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
