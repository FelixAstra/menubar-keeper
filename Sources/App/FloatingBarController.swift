import AppKit

/// The floating bar below the menu bar: the hidden apps' icons, laid out in a row.
///
/// It is a **self-drawn standalone window** and does not occupy a menu bar slot, which
/// is precisely why it is **not subject to the menu bar visibility allow-list**. Even
/// when the system hides MenuBarKeeper's own menu bar icon, this bar still works —
/// that is its value over simply expanding the menu bar temporarily.
final class FloatingBarController: NSObject {

    static let shared = FloatingBarController()

    /// Metrics, grouped so the bar's proportions are easy to tune in one place.
    /// Deliberately tight: this is a transient tool surface, so it should take as
    /// little room as possible.
    private enum Metrics {
        static let iconSize: CGFloat = 20
        static let itemSize: CGFloat = 28
        static let barHeight: CGFloat = 40
        static let edgeInset: CGFloat = 12
        static let cornerRadius: CGFloat = 11
        static let actionIconSize: CGFloat = 14
        static let appIconSize: CGFloat = 17
        static let stackInsets = NSEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        static let separatorHeight: CGFloat = 16
        static let minimumWidth: CGFloat = 140
        static let gapBelowMenuBar: CGFloat = 6
        static let borderAlpha: CGFloat = 0.08
    }

    private var panel: NSPanel?
    private var contentStack: NSStackView?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Briefly ignores "outside" clicks right after opening, otherwise the click that
    /// opened the bar would immediately close it.
    private var ignoreOutsideClicksUntil: TimeInterval = 0

    /// While a context menu is open, clicks on it must not count as clicking outside —
    /// the menu is a separate window, so selecting an item would otherwise close the
    /// bar the moment it opened.
    private var isTrackingContextMenu = false

    /// The menu bar icon that triggered this presentation, in screen coordinates. When
    /// present the bar hangs directly below it; without one (a keyboard shortcut, say)
    /// it falls back to the top-right of the screen. Refreshed on every show.
    private var anchorFrame: NSRect?

    /// Returns the current position of MenuBarKeeper's own menu bar icon. Injected by
    /// `AppDelegate`.
    ///
    /// This closure is what fixes "clicking the icon again does not close the bar": the
    /// click is seen first by our outside-click monitor, which hides the panel, and only
    /// then does the status item action fire and toggle it open again — so the second
    /// click appears to do nothing. Excluding clicks that land on the icon leaves the
    /// action as the only decision maker.
    var statusItemHitRect: (() -> NSRect?)?

    /// Called by the bar's "open main window" button. Injected by `AppDelegate`.
    var onOpenMainWindow: (() -> Void)?

    private(set) var isVisible = false

    private override init() {
        super.init()
    }

    // MARK: - Show / hide

    func toggle() { isVisible ? hide() : show() }

    /// Triggered by the menu bar icon: starts a short click-immunity window so the
    /// outside-click monitor does not close the bar immediately. `anchor` is that
    /// icon's frame in screen coordinates, used to hang the panel underneath it.
    func toggleFromStatusItem(anchor: NSRect?) {
        ignoreOutsideClicksUntil = Date().timeIntervalSince1970 + 0.25
        if anchor != nil { anchorFrame = anchor }
        toggle()
    }

    func show() {
        let panel = ensurePanel()
        rebuildContent()
        let size = contentSize()
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        panel.orderFrontRegardless()
        isVisible = true
        installOutsideClickMonitors()
        DebugLog.write("[bar] show size=\(Int(size.width))×\(Int(size.height)) "
                       + "frame=\(panel.frame) screen=\(panel.screen?.localizedName ?? "nil") "
                       + "apps=\(FoldController.shared.foldedApplications.count)",
                       when: "bar")
    }

    func hide() {
        removeOutsideClickMonitors()
        panel?.orderOut(nil)
        isVisible = false
        DebugLog.write("[bar] hide", when: "bar")
    }

    /// Rebuilds when the collapsed state changes, so the caption and the toggle button
    /// follow the menu bar.
    func refreshIfVisible() {
        guard isVisible, let panel else { return }
        rebuildContent()
        let size = contentSize()
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
    }

    // MARK: - Diagnostics hook

    /// Opens the context menu of the first icon exactly as a right-click would, and logs
    /// the menu structure. Uses the same code path as a real right-click, so "does the
    /// menu open and is it clickable" is genuinely covered.
    ///
    /// **Blocking** — returns once the menu closes.
    @discardableResult
    func debugOpenFirstIconMenu() -> Bool {
        guard let stack = contentStack,
              let icon = stack.arrangedSubviews.compactMap({ $0 as? IconButton }).first else {
            DebugLog.write("[menu] no icon to right-click", when: "bar")
            return false
        }
        let titles = icon.contextMenu?.items.map { $0.isSeparatorItem ? "---" : $0.title } ?? []
        DebugLog.write("[menu] items = \(titles.joined(separator: " | "))", when: "bar")
        icon.openMenu()
        return true
    }

    /// The symbol of the current show/hide toggle button. Used by `Diagnostics`.
    func debugToggleSymbol() -> String? {
        guard let stack = contentStack else { return nil }
        let prefix = "toggle:"
        return stack.arrangedSubviews
            .compactMap { ($0 as? NSButton)?.identifier?.rawValue }
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }

    // MARK: - Panel

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.minimumWidth, height: Metrics.barHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Metrics.cornerRadius
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(Metrics.borderAlpha).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 1
        stack.edgeInsets = Metrics.stackInsets
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        panel.contentView = effect
        self.panel = panel
        self.contentStack = stack
        return panel
    }

    private func rebuildContent() {
        guard let contentStack else { return }
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let apps = FoldController.shared.foldedApplications
        if apps.isEmpty {
            contentStack.addArrangedSubview(makeCaption(L("bar.caption.empty")))
        } else {
            // The caption always says "hidden": this bar lists exactly the hidden apps.
            // Whether the menu bar is collapsed right now is expressed by the toggle
            // button's direction and tint, which avoids the self-contradictory reading of
            // "N shown" next to N hidden apps.
            contentStack.addArrangedSubview(makeCaption(L("bar.caption.count", apps.count)))
            contentStack.addArrangedSubview(makeSeparator())
            for app in apps {
                contentStack.addArrangedSubview(makeIconButton(for: app))
            }
        }

        contentStack.addArrangedSubview(makeSeparator())
        contentStack.addArrangedSubview(makeToggleBarButton())
        contentStack.addArrangedSubview(makeAppButton(
            tooltip: L("bar.openMainWindow"),
            action: #selector(openMainWindow)))
    }

    private func contentSize() -> NSSize {
        guard let contentStack else {
            return NSSize(width: Metrics.minimumWidth, height: Metrics.barHeight)
        }
        contentStack.layoutSubtreeIfNeeded()
        let fitting = contentStack.fittingSize
        return NSSize(width: max(fitting.width, Metrics.minimumWidth),
                      height: max(fitting.height, Metrics.barHeight))
    }

    // MARK: - Positioning

    /// Hangs below the menu bar: centred on the anchor icon when there is one,
    /// otherwise flush with the right edge of the screen.
    private func origin(for size: NSSize) -> NSPoint {
        let screen: NSScreen? = anchorFrame.flatMap { anchor in
            NSScreen.screens.first { $0.frame.intersects(anchor) }
        } ?? panel?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return .zero }

        // AppKit's origin is bottom-left, so visibleFrame.maxY is the bottom edge of the
        // menu bar.
        let y = screen.visibleFrame.maxY - size.height - Metrics.gapBelowMenuBar

        let desiredX: CGFloat
        if let anchor = anchorFrame {
            desiredX = anchor.midX - size.width / 2
        } else {
            desiredX = screen.frame.maxX - size.width - Metrics.edgeInset
        }
        let minX = screen.frame.minX + Metrics.edgeInset
        let maxX = screen.frame.maxX - size.width - Metrics.edgeInset
        return NSPoint(x: min(max(desiredX, minX), max(minX, maxX)), y: y)
    }

    // MARK: - Controls

    private func makeCaption(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeSeparator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.separatorColor.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 1),
            view.heightAnchor.constraint(equalToConstant: Metrics.separatorHeight),
        ])
        return view
    }

    private func makeIconButton(for app: NSRunningApplication) -> NSView {
        let button = IconButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        if let icon = app.icon?.copy() as? NSImage {
            icon.size = NSSize(width: Metrics.iconSize, height: Metrics.iconSize)
            button.image = icon
        }
        let name = app.localizedName ?? app.bundleIdentifier ?? L("common.thisApp")
        button.target = self
        button.action = #selector(iconClicked(_:))
        button.toolTip = L("bar.icon.tooltip", name)
        button.identifier = NSUserInterfaceItemIdentifier(app.bundleIdentifier ?? "")
        button.contextMenu = contextMenu(for: app)
        button.onMenuTracking = { [weak self] tracking in
            self?.isTrackingContextMenu = tracking
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Metrics.itemSize),
            button.heightAnchor.constraint(equalToConstant: Metrics.itemSize),
        ])
        return button
    }

    private func makeActionButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
            image.isTemplate = true
            image.size = NSSize(width: Metrics.actionIconSize, height: Metrics.actionIconSize)
            button.image = image
        }
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Metrics.itemSize),
            button.heightAnchor.constraint(equalToConstant: Metrics.itemSize),
        ])
        return button
    }

    /// The menu bar show/hide toggle.
    ///
    /// One button going both ways — clicking again puts things back, with no second
    /// control to hunt for. The symbol direction and the accent tint both express the
    /// current state: highlighted means the icons are on the menu bar right now.
    private func makeToggleBarButton() -> NSView {
        let collapsed = FoldController.shared.isCollapsed
        let symbol = collapsed ? "arrow.up.left.and.arrow.down.right"
                               : "arrow.down.right.and.arrow.up.left"
        let button = makeActionButton(
            symbol: symbol,
            tooltip: L(collapsed ? "bar.toggle.expand" : "bar.toggle.collapse"),
            action: #selector(toggleMenuBar))
        button.contentTintColor = collapsed ? .controlAccentColor : .secondaryLabelColor
        // The identifier doubles as a diagnostics probe: the checks rely on it to confirm
        // the button really follows the state.
        button.identifier = NSUserInterfaceItemIdentifier("toggle:" + symbol)
        return button
    }

    /// The "open main window" button uses the app's own icon rather than a generic
    /// symbol: it is the one place on this surface that stands for MenuBarKeeper itself.
    /// Falls back to an SF Symbol so the button always works.
    private func makeAppButton(tooltip: String, action: Selector) -> NSView {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        if let icon = NSApp.applicationIconImage?.copy() as? NSImage {
            icon.size = NSSize(width: Metrics.appIconSize, height: Metrics.appIconSize)
            button.image = icon
        } else if let fallback = NSImage(systemSymbolName: "slider.horizontal.3",
                                         accessibilityDescription: tooltip) {
            fallback.isTemplate = true
            fallback.size = NSSize(width: Metrics.actionIconSize, height: Metrics.actionIconSize)
            button.image = fallback
            button.contentTintColor = .secondaryLabelColor
        }
        button.target = self
        button.action = action
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Metrics.itemSize),
            button.heightAnchor.constraint(equalToConstant: Metrics.itemSize),
        ])
        return button
    }

    // MARK: - Per-icon context menu

    /// A hidden app cannot expose its own menu (the icon is gone from the accessibility
    /// tree too), so the common actions are provided here; for the full original menu,
    /// "Restore to menu bar" puts the icon back first.
    private func contextMenu(for app: NSRunningApplication) -> NSMenu {
        let name = app.localizedName ?? L("common.thisApp")
        let menu = NSMenu()
        // Auto-enabling has to be off: the panel is not a key window, so AppKit's
        // automatic validation would disable every item.
        menu.autoenablesItems = false

        menu.addItem(contextItem(L("bar.menu.open", name), #selector(activateApp(_:)), app: app))

        let trusted = AccessibilityInventory.isTrusted
        let preferences = contextItem(L("bar.menu.preferences"), #selector(openPreferences(_:)), app: app)
        preferences.isEnabled = trusted
        preferences.toolTip = L(trusted ? "bar.menu.preferences.tooltip"
                                        : "bar.menu.preferences.tooltip.denied")
        menu.addItem(preferences)

        menu.addItem(.separator())
        menu.addItem(contextItem(L("bar.menu.reveal"), #selector(revealInMenuBar(_:)), app: app))
        menu.addItem(contextItem(L("bar.menu.hide"), #selector(hideApp(_:)), app: app))
        menu.addItem(contextItem(L("bar.menu.revealInFinder"), #selector(revealInFinder(_:)), app: app))

        menu.addItem(.separator())
        menu.addItem(contextItem(L("bar.menu.quit", name), #selector(terminateApp(_:)), app: app))
        menu.addItem(contextItem(L("bar.menu.forceQuit"), #selector(forceQuitApp(_:)), app: app))
        return menu
    }

    private func contextItem(_ title: String, _ action: Selector,
                             app: NSRunningApplication) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = app
        return item
    }

    // MARK: - Actions

    @objc private func iconClicked(_ sender: NSButton) {
        let bundle = sender.identifier?.rawValue ?? ""
        hide()
        guard !bundle.isEmpty else { return }
        // Activate only, never launch: the icon stands for an app that is already
        // running. The panel does not take activation, so this app never becomes
        // frontmost and the activation is not refused.
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            .first?
            .activate()
    }

    /// The show/hide menu bar toggle. Showing leaves things shown — there is no timer to
    /// put them back, because there is now an explicit button for that.
    @objc private func toggleMenuBar() {
        let fold = FoldController.shared
        // The state change triggers onStateChange → refreshIfVisible, so the panel stays
        // up and the user can toggle straight back from the same spot.
        fold.isCollapsed ? fold.restore() : fold.collapse()
    }

    @objc private func openMainWindow() {
        hide()
        onOpenMainWindow?()
    }

    @objc private func activateApp(_ sender: NSMenuItem) {
        guard let app = app(from: sender) else { return }
        hide()
        AppActions.activate(app)
    }

    @objc private func openPreferences(_ sender: NSMenuItem) {
        guard let app = app(from: sender) else { return }
        hide()
        AppActions.openPreferences(app)
    }

    /// Moves just this app out of the hidden area — its icon returns to the menu bar
    /// immediately, and the user can then right-click it as usual and use the app's own
    /// full menu.
    @objc private func revealInMenuBar(_ sender: NSMenuItem) {
        guard let app = app(from: sender), let bundle = app.bundleIdentifier else { return }
        hide()
        FoldController.shared.setHidden(false, for: bundle)
    }

    @objc private func hideApp(_ sender: NSMenuItem) {
        guard let app = app(from: sender) else { return }
        hide()
        AppActions.hide(app)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let app = app(from: sender) else { return }
        hide()
        AppActions.revealInFinder(app)
    }

    @objc private func terminateApp(_ sender: NSMenuItem) {
        guard let app = app(from: sender) else { return }
        hide()
        AppActions.terminate(app)
    }

    @objc private func forceQuitApp(_ sender: NSMenuItem) {
        guard let app = app(from: sender) else { return }
        let name = app.localizedName ?? L("common.thisApp")
        hide()
        // A force quit gives the app no chance to save, so it must be confirmed.
        let alert = NSAlert()
        alert.messageText = L("bar.forceQuit.title", name)
        alert.informativeText = L("bar.forceQuit.body")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("bar.forceQuit.confirm"))
        alert.addButton(withTitle: L("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AppActions.forceTerminate(app)
    }

    private func app(from item: NSMenuItem) -> NSRunningApplication? {
        item.representedObject as? NSRunningApplication
    }

    // MARK: - Dismiss on outside click

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.handleOutsideClick()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            // Clicks inside the panel are fine; only clicks elsewhere close it.
            if event.window === self.panel { return event }
            self.handleOutsideClick()
            return event
        }
    }

    private func removeOutsideClickMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isTrackingContextMenu = false
    }

    private func handleOutsideClick() {
        // A context menu is open — clicking it is not clicking outside.
        guard !isTrackingContextMenu else { return }
        // The click landed on our own menu bar icon: let the status item action toggle
        // the panel. Without this the panel is hidden here and then shown again by the
        // action, so a click appears to do nothing.
        if let rect = statusItemHitRect?(), rect.contains(NSEvent.mouseLocation) { return }
        guard Date().timeIntervalSince1970 > ignoreOutsideClicksUntil else { return }
        hide()
    }
}

/// An app icon on the floating bar.
///
/// A subclass purely for **right-click**: the icons stand for status items the system
/// has hidden, so they cannot be clicked on the user's behalf and the app's own menu is
/// unreachable. A context menu stands in for it.
private final class IconButton: NSButton {

    var contextMenu: NSMenu?

    /// Reports menu tracking so that clicks during it are not treated as clicks outside.
    var onMenuTracking: ((Bool) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        guard contextMenu != nil else {
            super.rightMouseDown(with: event)
            return
        }
        openMenu()
    }

    /// Opens the context menu. Diagnostics go through this too, so the real code path is
    /// what gets verified.
    func openMenu() {
        guard let contextMenu else { return }
        onMenuTracking?(true)
        // popUp runs a synchronous event-tracking loop and returns only once the menu
        // closes, so these two calls bracket the menu's whole lifetime.
        contextMenu.popUp(positioning: nil,
                          at: NSPoint(x: 0, y: bounds.height + 2),
                          in: self)
        onMenuTracking?(false)
    }
}
