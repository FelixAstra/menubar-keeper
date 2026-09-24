import AppKit

/// A top-down container: `NSScrollView`'s document view needs a flipped coordinate
/// system to lay rows out from the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The MenuBarKeeper window: menu bar icons grouped by app, with a checkbox per app to
/// move it into the hidden area.
///
/// Views are created as stored properties rather than assigned in `build()` through
/// implicitly-unwrapped optionals, and the ones that need a target are wired up after
/// `super.init()` — so nothing here can be nil at runtime.
final class KeeperWindowController: NSObject {

    private enum Metrics {
        static let windowSize = NSSize(width: 620, height: 560)
        static let padding: CGFloat = 16
        static let listPadding: CGFloat = 8
        static let brandSpacing: CGFloat = 10
        static let lineSpacing: CGFloat = 4
        static let buttonSpacing: CGFloat = 10
        static let controlsBottomInset: CGFloat = 14
    }

    // MARK: - Views

    private let window: NSWindow
    private let brandIcon = NSImageView()
    private let stateLabel = NSTextField(labelWithString: "")
    private let mechanismLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let listStack = NSStackView()
    private let listContainer = FlippedView()
    private let scrollView = NSScrollView()
    private let hintLabel = NSTextField(labelWithString: "")
    private let autoCollapseCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let languagePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private let restoreButton = NSButton(title: "", target: nil, action: nil)
    private let collapseButton = NSButton(title: "", target: nil, action: nil)

    private var rows: [AppRowView] = []
    private var lastEntries: [MenuBarAppEntry] = []
    private var isScanning = false

    override init() {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Metrics.windowSize),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered,
                          defer: false)
        super.init()
        configureWindow()
        configureViews()
        layoutViews()
        wireActions()
        syncControls()
    }

    // MARK: - Presentation

    var isVisible: Bool { window.isVisible }

    func toggle() {
        isVisible ? window.orderOut(nil) : show()
    }

    func show() {
        // Re-assert the size on every show: an autosaved frame from an earlier (broken)
        // build can otherwise come back as a 480 pt wide column.
        window.setContentSize(Metrics.windowSize)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        refresh()
    }

    /// Called by `AppDelegate` when the collapsed state changes. A single owner for the
    /// state-change callback avoids the two of them overwriting each other.
    func syncFromModel() {
        syncControls()
    }

    // MARK: - Construction

    private func configureWindow() {
        window.title = L("window.title")

        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MenuBarKeeperWindow")
        // Fixed-size utility window: both the floor and the size are pinned, so Auto Layout
        // never gets a say in how big the window is. The app list scrolls instead.
        window.contentMinSize = Metrics.windowSize
        window.setContentSize(Metrics.windowSize)
        window.center()
    }

    private func configureViews() {
        let content = NSView()
        window.contentView = content

        // This floor is what actually decides the window's size. AppKit sizes a window to
        // its content view's *fitting* size, and the fitting size is the smallest box that
        // satisfies the required constraints — with a width chain made of truncating labels
        // and a scroll view, that resolves to ~86 pt and the window collapses. Pinning a
        // required floor makes the fitting size equal the intended size, so everything
        // agrees and nothing has to be broken at layout time.
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: Metrics.windowSize.width),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.windowSize.height),
        ])

        brandIcon.imageScaling = .scaleProportionallyDown
        brandIcon.image = AppIcons.brandMark()

        stateLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stateLabel.lineBreakMode = .byTruncatingTail

        mechanismLabel.font = .systemFont(ofSize: 10.5)
        mechanismLabel.textColor = .secondaryLabelColor
        mechanismLabel.lineBreakMode = .byTruncatingTail
        mechanismLabel.maximumNumberOfLines = 2

        summaryLabel.font = .systemFont(ofSize: 10.5)
        summaryLabel.textColor = .tertiaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.stringValue = L("window.summary.preparing")

        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 0

        listContainer.addSubview(listStack)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = listContainer

        hintLabel.font = .systemFont(ofSize: 10.5)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 2
        hintLabel.stringValue = L("window.hint")

        autoCollapseCheckbox.toolTip = L("window.autoCollapse.tooltip")

        languagePopUp.toolTip = L("language.label")
        languagePopUp.addItems(withTitles: L10n.Language.allCases.map(\.endonym))
        languagePopUp.selectItem(at: L10n.Language.allCases.firstIndex(of: L10n.language) ?? 0)

        refreshButton.bezelStyle = .rounded
        restoreButton.bezelStyle = .rounded
        restoreButton.toolTip = L("window.expandAll")
        collapseButton.bezelStyle = .rounded
        collapseButton.keyEquivalent = "\r"
    }

    private func layoutViews() {
        guard let content = window.contentView else { return }
        let allViews: [NSView] = [
            brandIcon, stateLabel, mechanismLabel, summaryLabel, scrollView, hintLabel,
            autoCollapseCheckbox, languagePopUp, refreshButton, restoreButton, collapseButton,
        ]
        for view in allViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }

        let menuBarSize = AppIcons.menuBarSize
        NSLayoutConstraint.activate([
            brandIcon.topAnchor.constraint(equalTo: content.topAnchor, constant: Metrics.padding),
            brandIcon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Metrics.padding),
            brandIcon.widthAnchor.constraint(equalToConstant: menuBarSize.width),
            brandIcon.heightAnchor.constraint(equalToConstant: menuBarSize.height),

            stateLabel.centerYAnchor.constraint(equalTo: brandIcon.centerYAnchor),
            stateLabel.leadingAnchor.constraint(equalTo: brandIcon.trailingAnchor,
                                                constant: Metrics.brandSpacing),
            stateLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                                 constant: -Metrics.padding),

            mechanismLabel.topAnchor.constraint(equalTo: stateLabel.bottomAnchor,
                                                constant: Metrics.lineSpacing),
            mechanismLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                                    constant: Metrics.padding),
            mechanismLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                                     constant: -Metrics.padding),

            summaryLabel.topAnchor.constraint(equalTo: mechanismLabel.bottomAnchor,
                                              constant: Metrics.lineSpacing),
            summaryLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                                  constant: Metrics.padding),
            summaryLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                                   constant: -Metrics.padding),

            scrollView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                                constant: Metrics.listPadding),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                                 constant: -Metrics.listPadding),
            scrollView.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -10),

            listContainer.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            listContainer.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            listContainer.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            listStack.topAnchor.constraint(equalTo: listContainer.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),

            hintLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Metrics.padding),
            hintLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Metrics.padding),
            hintLabel.bottomAnchor.constraint(equalTo: collapseButton.topAnchor, constant: -12),

            autoCollapseCheckbox.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                                          constant: Metrics.padding),
            autoCollapseCheckbox.centerYAnchor.constraint(equalTo: collapseButton.centerYAnchor),

            languagePopUp.leadingAnchor.constraint(equalTo: autoCollapseCheckbox.trailingAnchor,
                                                   constant: Metrics.padding),
            languagePopUp.centerYAnchor.constraint(equalTo: collapseButton.centerYAnchor),

            collapseButton.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                                     constant: -Metrics.padding),
            collapseButton.bottomAnchor.constraint(equalTo: content.bottomAnchor,
                                                   constant: -Metrics.controlsBottomInset),

            restoreButton.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor,
                                                    constant: -Metrics.buttonSpacing),
            restoreButton.centerYAnchor.constraint(equalTo: collapseButton.centerYAnchor),

            refreshButton.trailingAnchor.constraint(equalTo: restoreButton.leadingAnchor,
                                                    constant: -Metrics.buttonSpacing),
            refreshButton.centerYAnchor.constraint(equalTo: collapseButton.centerYAnchor),
        ])
    }

    private func wireActions() {
        autoCollapseCheckbox.target = self
        autoCollapseCheckbox.action = #selector(autoCollapseToggled)
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged)
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
        restoreButton.target = self
        restoreButton.action = #selector(restoreClicked)
        collapseButton.target = self
        collapseButton.action = #selector(collapseClicked)
    }

    // MARK: - Scanning and rendering

    func refresh() {
        guard !isScanning else { return }

        guard AccessibilityInventory.isTrusted else {
            rebuild(entries: nil)
            summaryLabel.stringValue = L("window.summary.noPermission")
            return
        }

        isScanning = true
        summaryLabel.stringValue = L("window.summary.scanning")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = MenuBarScanner.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isScanning = false
                self.rebuild(entries: entries)
                self.updateSummary(entries)
            }
        }
    }

    private func updateSummary(_ entries: [MenuBarAppEntry]) {
        let icons = entries.reduce(0) { $0 + $1.itemCount }
        summaryLabel.stringValue = L("window.summary.count",
                                     icons, entries.count, entries.filter(\.canFold).count)
    }

    /// `entries == nil` means there is no permission — render the guidance instead.
    private func rebuild(entries: [MenuBarAppEntry]?) {
        clearList()
        lastEntries = entries ?? []

        guard let entries else {
            addPermissionHint()
            syncControls()
            return
        }
        guard !entries.isEmpty else {
            addHint(L("window.empty"))
            syncControls()
            return
        }

        let fold = FoldController.shared
        for entry in entries {
            let row = AppRowView(entry: entry)
            row.isMarked = fold.isHidden(entry.bundleIdentifier) && entry.canFold
            row.onMarkChange = { [weak self] changed in self?.markChanged(changed) }
            listStack.addArrangedSubview(row)
            rows.append(row)
        }
        syncControls()
    }

    private func clearList() {
        for view in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rows.removeAll()
    }

    /// Adds a centred message wrapped in a padded container.
    private func addHint(_ text: String, extraViews: [NSView] = []) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)

        var constraints = [
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 36),
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 30),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -30),
        ]

        if extraViews.isEmpty {
            constraints.append(label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -36))
        } else {
            let buttons = NSStackView(views: extraViews)
            buttons.orientation = .horizontal
            buttons.spacing = Metrics.buttonSpacing
            buttons.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(buttons)
            constraints.append(contentsOf: [
                buttons.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 18),
                buttons.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                buttons.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -36),
            ])
        }

        NSLayoutConstraint.activate(constraints)
        listStack.addArrangedSubview(wrapper)
    }

    private func addPermissionHint() {
        let settingsButton = NSButton(title: L("window.permission.openSettings"),
                                      target: self, action: #selector(openPermissionSettings))
        settingsButton.bezelStyle = .rounded

        // macOS only reads this permission at process start, so offer a one-click restart
        // instead of making the user hunt for Quit in the menu bar.
        let restartButton = NSButton(title: L("window.permission.restart"),
                                     target: self, action: #selector(restartApp))
        restartButton.bezelStyle = .rounded
        restartButton.keyEquivalent = "\r"

        addHint(L("window.permission.body"), extraViews: [settingsButton, restartButton])
    }

    // MARK: - Actions

    @objc private func refreshClicked() { refresh() }

    @objc private func openPermissionSettings() {
        AccessibilityInventory.requestTrust()
        AccessibilityInventory.openSystemSettings()
    }

    /// Restarts the app. Required after granting Accessibility permission, because macOS
    /// only reads it at process start.
    @objc private func restartApp() {
        Installation.relaunch(at: Bundle.main.bundlePath)
    }

    @objc private func languageChanged() {
        let index = languagePopUp.indexOfSelectedItem
        guard L10n.Language.allCases.indices.contains(index) else { return }
        L10n.select(L10n.Language.allCases[index])
    }

    @objc private func autoCollapseToggled() {
        FoldController.shared.collapsesOnLaunch = autoCollapseCheckbox.state == .on
    }

    /// Changing the selection hides or shows an app immediately, then rescans. The short
    /// delay matters: the app disappears from the accessibility tree only after the
    /// system has applied the change.
    private func markChanged(_ row: AppRowView) {
        FoldController.shared.setHidden(row.isMarked, for: row.entry.bundleIdentifier)
        refreshAfterSystemApplies()
    }

    @objc private func collapseClicked() {
        FoldController.shared.collapse()
        refreshAfterSystemApplies()
    }

    @objc private func restoreClicked() {
        FoldController.shared.restore()
        refreshAfterSystemApplies()
    }

    private func refreshAfterSystemApplies() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, self.window.isVisible, !self.isScanning else { return }
            self.refresh()
        }
    }

    // MARK: - State synchronisation

    private func syncControls() {
        let fold = FoldController.shared
        updateMechanismLabel(fold)

        let marked = rows.filter(\.isMarked).count
        if fold.isCollapsed {
            stateLabel.stringValue = L("window.state.collapsed", fold.hiddenBundles.count)
        } else if marked > 0 {
            stateLabel.stringValue = L("window.state.marked", marked)
        } else {
            stateLabel.stringValue = L("window.state.idle")
        }

        let usable = fold.isMechanismAvailable
        collapseButton.title = marked > 0 ? L("window.collapse.count", marked) : L("window.collapse")
        collapseButton.isEnabled = usable && marked > 0
        restoreButton.isEnabled = usable && fold.isCollapsed
        refreshButton.title = L("window.refresh")
        restoreButton.title = L("window.expandAll")
        autoCollapseCheckbox.title = L("window.autoCollapse")
        autoCollapseCheckbox.isEnabled = usable
        autoCollapseCheckbox.state = fold.collapsesOnLaunch ? .on : .off
    }

    /// Reports what the hiding mechanism is doing, in priority order. The verification
    /// branch is the interesting one: after collapsing, the selected apps should have
    /// disappeared from the accessibility tree. Checking that gives a conclusion without
    /// relying on the user's eyes, so a silent failure becomes a visible one.
    private func updateMechanismLabel(_ fold: FoldController) {
        if !Installation.isInApplications {
            // Highest priority: running from outside /Applications means the app's own
            // icon gets hidden too, and the user loses their controls. That is worth
            // saying before anything else.
            mechanismLabel.stringValue = L("window.notInApplications")
            mechanismLabel.textColor = .systemOrange
            return
        }
        if let problem = fold.availabilityMessage {
            mechanismLabel.stringValue = L("window.mechanism.unavailable", problem)
            mechanismLabel.textColor = .systemRed
            return
        }
        if let error = fold.lastError {
            mechanismLabel.stringValue = L("window.mechanism.rejected", error)
            mechanismLabel.textColor = .systemRed
            return
        }

        // Selected apps that are still running — the candidates whose disappearance can
        // actually be observed.
        let selected = lastEntries.filter {
            fold.isHidden($0.bundleIdentifier)
                && NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleIdentifier)
                    .first != nil
        }
        let stillVisible = selected.filter(\.isObservable)

        switch (fold.isCollapsed, selected.isEmpty, stillVisible.isEmpty) {
        case (true, false, false):
            mechanismLabel.stringValue = L("window.mechanism.ineffective", stillVisible.count)
            mechanismLabel.textColor = .systemOrange
        case (true, false, true):
            mechanismLabel.stringValue = L("window.mechanism.verified", selected.count)
            mechanismLabel.textColor = .systemGreen
        default:
            mechanismLabel.stringValue = L("window.mechanism.ok", MenuBarScanner.discoveryDescription)
            mechanismLabel.textColor = .secondaryLabelColor
        }
    }
}
