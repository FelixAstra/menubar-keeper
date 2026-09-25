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
        schedule(after: 1.4, when: "windowshot") { [weak self] in
            self?.runWindowShot()
        }
        schedule(after: 1.4, when: "sectiontest") { [weak self] in
            self?.runSectionCheck()
        }
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

        func describe(_ image: NSImage?) -> String {
            guard let image else { return "nil" }
            let reps = image.representations.map { "\($0.pixelsWide)×\($0.pixelsHigh)px" }
            return "\(image.size.width)×\(image.size.height)pt template=\(image.isTemplate) "
                + "reps=[\(reps.joined(separator: ","))]"
        }
        report("[selftest] appIcon=\(describe(AppIcons.appIcon))")
        report("[selftest] menuBar.expanded=\(describe(AppIcons.menuBar(collapsed: false)))")
        report("[selftest] menuBar.collapsed=\(describe(AppIcons.menuBar(collapsed: true)))")
        report("[selftest] statusButton.image=\(describe(delegate.statusItemImage))")

        defaults.set("ok", forKey: "MenuBarKeeper.selftest")
        report("[selftest] writeReadback=\(defaults.string(forKey: "MenuBarKeeper.selftest") ?? "nil")")
        defaults.removeObject(forKey: "MenuBarKeeper.selftest")
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
