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
        schedule(after: 3.0, when: "verify") { [weak self] in
            self?.runFoldVerification()
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
        report("[selftest] collapseOnLaunch=\(defaults.bool(forKey: keys.collapseOnLaunch))")
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
        let original = fold.hiddenBundles
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
                        for bundle in original { self.fold.setHidden(true, for: bundle) }
                        self.report("[verify] restored: \(original.sorted())")
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

    // MARK: - Synthetic input

    private func after(_ delay: TimeInterval, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body)
    }

    /// Posts a synthetic mouse click. `point` uses AppKit's bottom-left origin, which
    /// is converted to the top-left origin CGEvent expects.
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
