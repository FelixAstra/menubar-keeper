import AppKit

/// Owns the menu bar icon, the context menu, global shortcuts and the app lifecycle.
///
/// Diagnostics and self-tests live in `Diagnostics` so this type stays about
/// production behaviour only.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private enum Shortcut {
        /// Physical key codes, not characters: characters shift with the keyboard layout
        /// and input source, key codes do not.
        static let m: UInt16 = 46
        static let backslash: UInt16 = 42
    }

    private enum DefaultsKey {
        static let hasLaunchedBefore = "MenuBarKeeper.hasLaunchedBefore"
    }

    private var statusItem: NSStatusItem?
    private let windowController = KeeperWindowController()
    private let fold = FoldController.shared
    private lazy var diagnostics = Diagnostics(delegate: self)

    /// Global shortcut monitors. These are the fallback entry point for the case where
    /// the menu bar icon itself gets hidden, so they deliberately do not go through the
    /// menu bar.
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Gives every alert the app icon automatically, instead of setting it on each one.
        if let icon = AppIcons.appIcon { NSApp.applicationIconImage = icon }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()

        fold.onStateChange = { [weak self] in
            DispatchQueue.main.async {
                self?.syncStatusIcon()
                self?.windowController.syncFromModel()
                // Keep the floating bar in step: its caption and its toggle button both
                // depend on the current state.
                FloatingBarController.shared.refreshIfVisible()
            }
        }

        configureFloatingBar()
        installHotKeys()

        // Apply the saved selection at launch, once the menu bar has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.fold.prepareOnLaunch()
        }

        presentOnboardingIfNeeded()
        diagnostics.startIfRequested()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Always restore before quitting: the menu bar is never left restricted.
        FloatingBarController.shared.hide()
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        globalKeyMonitor = nil
        localKeyMonitor = nil
        fold.shutdown()
    }

    private func configureFloatingBar() {
        // The floating bar is the second entry point: it occupies no menu bar slot, so the
        // visibility allow-list cannot affect it.
        FloatingBarController.shared.onOpenMainWindow = { [weak self] in
            self?.windowController.show()
        }
        // Lets the bar know where its own menu bar icon is, so it can exclude clicks on it
        // from "outside clicks" — otherwise clicking the icon is swallowed by the
        // outside-click monitor and then re-opened by the action.
        FloatingBarController.shared.statusItemHitRect = { [weak self] in
            self?.statusItemWindow?.frame
        }
    }

    /// Opens the window on the very first launch so a new user is not left staring at a
    /// menu bar icon with no idea what to do next.
    private func presentOnboardingIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.hasLaunchedBefore) else { return }
        defaults.set(true, forKey: DefaultsKey.hasLaunchedBefore)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.windowController.show()
        }
    }

    // MARK: - Diagnostics access

    /// Exposed for `Diagnostics`; not part of the app's own logic.
    var statusItemWindow: NSWindow? { statusItem?.button?.window }
    var isStatusItemVisible: Bool { statusItem?.isVisible ?? false }
    var statusItemImage: NSImage? { statusItem?.button?.image }
    func showMainWindow() { windowController.show() }

    // MARK: - Status item

    private func configureButton() {
        guard let button = statusItem?.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        syncStatusIcon()
    }

    private func syncStatusIcon() {
        guard let button = statusItem?.button else { return }
        let collapsed = fold.isCollapsed

        if let image = AppIcons.menuBar(collapsed: collapsed) {
            button.image = image
            button.title = ""
            // Deliberately no alpha change per state: this is the solid mark from the
            // design. Dimming it muddies the artwork. State is carried by the tooltip and
            // by the floating bar; if `MenuBarTemplateCollapsed` / `Expanded` are ever
            // added, this picks them up automatically.
            button.alphaValue = 1.0
        } else {
            // Assets missing: fall back to an SF Symbol. The icon is decoration and must
            // never decide whether the app works.
            let symbol = collapsed ? "rectangle.compress.vertical" : "menubar.rectangle"
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: L("app.name")) {
                image.isTemplate = true
                button.image = image
                button.title = ""
            } else {
                button.title = collapsed ? "▤" : "◧"
            }
            button.alphaValue = 1.0
        }

        button.toolTip = collapsed
            ? L("status.tooltip.collapsed", fold.hiddenBundles.count)
            : L("status.tooltip.idle")
    }

    // MARK: - Click handling

    /// Screen position of the menu bar icon; nil when unavailable (the floating bar then
    /// falls back to the top-right corner).
    private var statusItemAnchor: NSRect? { statusItemWindow?.frame }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.option) == true

        if isSecondary {
            presentMenu()
            return
        }
        // Left click: open on first click, close on the next. The toggle is decided here
        // alone, because the outside-click monitor already ignores clicks on this icon.
        // With nothing hidden there is nothing to reveal, so open the window instead.
        if fold.hiddenBundles.isEmpty {
            windowController.toggle()
        } else {
            FloatingBarController.shared.toggleFromStatusItem(anchor: statusItemAnchor)
        }
    }

    private func presentMenu() {
        // Hide the floating bar first so two entry points are never open at once.
        FloatingBarController.shared.hide()

        let menu = NSMenu()
        menu.delegate = self
        // Opening the window also rescans, so a separate "Refresh" entry would be
        // indistinguishable from "Open".
        menu.addItem(menuItem(L("menu.open"), #selector(openWindow)))
        menu.addItem(.separator())

        if fold.isCollapsed {
            menu.addItem(menuItem(L("menu.showBar"), #selector(showFloatingBar)))
            menu.addItem(menuItem(L("menu.expandAll"), #selector(restoreAll)))
            menu.addItem(menuItem(L("menu.peek"), #selector(peek)))
        } else {
            let title = fold.hiddenBundles.isEmpty
                ? L("menu.collapse.none")
                : L("menu.collapse.count", fold.hiddenBundles.count)
            let collapse = menuItem(title, #selector(collapseAll))
            collapse.isEnabled = !fold.hiddenBundles.isEmpty && fold.isMechanismAvailable
            menu.addItem(collapse)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem(L("menu.accessibility"), #selector(openPermissionSettings)))
        menu.addItem(menuItem(L("menu.help"), #selector(showHelp)))
        if !Installation.isInApplications {
            menu.addItem(.separator())
            menu.addItem(menuItem(L("menu.moveToApplications"), #selector(moveToApplications)))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem(L("menu.quit"), #selector(quit), key: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }

    /// Assigning `statusItem.menu` and clicking is the supported way to show a menu from a
    /// status item action; clearing it afterwards restores normal click handling.
    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func openWindow() { windowController.show() }

    @objc private func showFloatingBar() {
        // Coming from the context menu the panel is always hidden, so this shows it.
        FloatingBarController.shared.toggleFromStatusItem(anchor: statusItemAnchor)
    }

    @objc private func collapseAll() { fold.collapse() }
    @objc private func restoreAll() { fold.restore() }
    @objc private func peek() { fold.expandTemporarily(for: 10) }

    @objc private func openPermissionSettings() {
        AccessibilityInventory.requestTrust()
        AccessibilityInventory.openSystemSettings()
    }

    /// Copies the app to /Applications and restarts it.
    ///
    /// This is functional, not housekeeping: the system only protects the menu bar icon of
    /// an app installed in a standard location. Run from the Desktop, the app's own icon
    /// is hidden along with everything else and the user loses their controls.
    @objc private func moveToApplications() {
        let alert = NSAlert()
        alert.messageText = L("alert.move.title")
        alert.informativeText = L("alert.move.body")
        alert.addButton(withTitle: L("alert.move.confirm"))
        alert.addButton(withTitle: L("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let error = Installation.copyToApplications() {
            let failure = NSAlert()
            failure.messageText = L("alert.copyFailed.title")
            failure.informativeText = error
            failure.addButton(withTitle: L("common.ok"))
            failure.runModal()
            return
        }
        Installation.relaunch(at: "\(Installation.applicationsDirectory)/\(Installation.currentName)")
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = L("help.title")

        let status = fold.isCollapsed
            ? L("help.status.collapsed", fold.hiddenBundles.count)
            : L("help.status.expanded")
        let mechanism = fold.availabilityMessage.map { L("help.mechanism.unavailable", $0) }
            ?? L("help.mechanism.available")
            + (fold.lastError.map { L("help.mechanism.lastError", $0) } ?? "")

        alert.informativeText = "\(status)\n\(mechanism)\n\n" + L("help.body")
        alert.addButton(withTitle: L("common.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Global shortcuts

    private func installHotKeys() {
        let mask: NSEvent.EventTypeMask = [.keyDown]
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleHotKey(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleHotKey(event)
            return event
        }
    }

    /// ⌥⌘M reveals or hides the floating bar, ⌥⌘\ hides or shows the menu bar icons.
    private func handleHotKey(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.option, .command] else { return }
        switch event.keyCode {
        case Shortcut.m:
            DispatchQueue.main.async { FloatingBarController.shared.toggle() }
        case Shortcut.backslash:
            DispatchQueue.main.async { FoldController.shared.toggleCollapsed() }
        default:
            break
        }
    }
}
