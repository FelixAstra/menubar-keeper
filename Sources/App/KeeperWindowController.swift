import AppKit

/// A top-down container: `NSScrollView`'s document view needs a flipped coordinate
/// system to lay rows out from the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The MenuBarKeeper window: menu bar icons grouped by app, with a state daisy per app to
/// move it into the hidden area.
///
/// Views are created as stored properties rather than assigned in `build()` through
/// implicitly-unwrapped optionals, and the ones that need a target are wired up after
/// `super.init()` — so nothing here can be nil at runtime.
final class KeeperWindowController: NSObject {

    private enum Metrics {
        /// Tall enough for the single footer row *and* nine list rows plus the section header.
        /// The footer briefly needed two rows to keep its controls apart; the language picker
        /// has since moved up into the title row and the *Detect and hide on launch* checkbox
        /// now shares the button row, so the height the second row was taking goes back to
        /// the list — the part that has to stay fully visible.
        static let windowSize = NSSize(width: 620, height: 602)
        static let padding: CGFloat = 16
        static let listPadding: CGFloat = 8
        static let brandSpacing: CGFloat = 10
        static let lineSpacing: CGFloat = 4
        static let buttonSpacing: CGFloat = 10
        /// Gap between the trailing controls of the title row — the icon-style picker and the
        /// language tab — and the headline they sit beside. One value for the whole row: the
        /// three of them read as a single group, and the small gap is what keeps the headline
        /// from looking like it belongs to the picker.
        static let iconStyleGap: CGFloat = 8
        static let controlsBottomInset: CGFloat = 14
        /// Leading inset of the section header's content, matching the list rows.
        static let rowInset: CGFloat = 12
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
    /// The 中 / EN switcher, parked in the trailing corner of the title row.
    ///
    /// Its two labels are literals rather than lookups, for the same reason the old picker
    /// hardcoded them: an endonym is written in its own language, so "中" and "EN" read the
    /// same whichever language is active — translating them would make the control hardest to
    /// use exactly when the user needs it.
    private let languageTabs = NSSegmentedControl(labels: ["中", "EN"],
                                                  trackingMode: .selectOne,
                                                  target: nil,
                                                  action: nil)
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private let restoreButton = NSButton(title: "", target: nil, action: nil)
    private let collapseButton = NSButton(title: "", target: nil, action: nil)
    /// Chooses which mark the menu bar wears — the brand capsule or the state daisy.
    ///
    /// A pull-down rather than a segmented control: the two options are pictures, and a
    /// two-cell tab showing both at once would cost twice the width for a control nobody
    /// touches twice. This one shows the mark that is in effect, and the alternatives are
    /// one click away with their names spelled out.
    private let iconStylePicker = NSPopUpButton(frame: .zero, pullsDown: false)

    /// The "never hidden" section: a rule, a disclosure button and the rows behind it.
    /// Built once and added to or removed from the list per scan.
    private let systemHeaderRow = NSView()
    private let systemHeaderButton = NSButton(title: "", target: nil, action: nil)

    /// Rows the user can act on. The system section is tracked separately — those rows
    /// can never be selected, so they must not take part in the "how many are selected"
    /// count.
    private var rows: [AppRowView] = []
    private var systemRows: [AppRowView] = []
    /// Whether the system section is open. Collapsed by default: those rows are reference
    /// material, not part of the task.
    private var showsSystemItems = false
    private var lastEntries: [MenuBarAppEntry] = []
    private var isScanning = false
    /// Guards the single extra scan that follows a submission. See `recheckAfterCollapse`.
    private var didRecheck = false

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
        // Any new submission — at launch, from a hot key, or from this window — earns a
        // fresh verification scan. See `recheckAfterCollapse`.
        didRecheck = false
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

        // The window's size is pinned exactly, not floored. AppKit sizes a window to its
        // content view's *fitting* size, and a floor only raises that — it cannot lower it.
        // So any subview that prefers more room than the window stretches it: once the list
        // started reporting real widths, the mechanism label's full sentence (about 620 pt
        // of text, longer or shorter depending on the state) pushed the window out to 651.
        // An equality makes the fitting size the intended size, and the long labels
        // truncate instead — which is exactly what their line-break mode asks for.
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: Metrics.windowSize.width),
            content.heightAnchor.constraint(equalToConstant: Metrics.windowSize.height),
        ])

        brandIcon.imageScaling = .scaleProportionallyDown
        brandIcon.image = AppIcons.brandMark()

        stateLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        stateLabel.lineBreakMode = .byTruncatingTail
        // The language tab outranks the headline, because they share a row and the tab is
        // already as small as it goes. At the default resistance a long translation would
        // push the tab towards the edge instead of shortening itself; dropping this lets the
        // sentence be clipped, which still reads, and keeps the control where it belongs.
        stateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Named for the layout probe, which has to measure how much of this sentence the
        // language tab leaves room for.
        stateLabel.identifier = NSUserInterfaceItemIdentifier("stateHeadline")

        mechanismLabel.font = .systemFont(ofSize: 10.5)
        mechanismLabel.textColor = .secondaryLabelColor
        mechanismLabel.lineBreakMode = .byTruncatingTail
        mechanismLabel.maximumNumberOfLines = 2

        summaryLabel.font = .systemFont(ofSize: 10.5)
        summaryLabel.textColor = .tertiaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.stringValue = L("window.summary.preparing")

        listStack.orientation = .vertical
        // Rows are pinned to the stack's width (in `rebuild`) rather than stretched by
        // `alignment`. The value that reads as "fill the width" is not stored by this SDK:
        // assigning `.width` leaves the stack reporting `notAnAttribute`, and the rows come
        // out at their natural width, flush right — which is not what a list wants.
        listStack.alignment = .leading
        listStack.spacing = 0

        listContainer.addSubview(listStack)

        // Both take part in the constraint chain `layoutViews` installs, and neither is in
        // that method's list of views to switch over to Auto Layout. Left at their default,
        // the engine silently ignores every constraint naming them: the document view stays
        // 0×0, so all the rows land on the same coordinates at the origin and the list draws
        // as a single untitled line. Nothing is logged — a view with this flag on has handed
        // its frame back to its superview, so there is no frame for the engine to fight.
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        listStack.translatesAutoresizingMaskIntoConstraints = false

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

        // `small`, and deliberately so: the title row is sized by the 18 pt brand mark, and a
        // regular-size segmented control would add ten points of height to every window to
        // say two characters.
        languageTabs.controlSize = .small
        languageTabs.segmentStyle = .rounded
        languageTabs.toolTip = L("language.tooltip")
        // Pinned rigid, because the tab is the one control in this row that must never
        // stretch. Left at its defaults an `NSSegmentedControl` hugs its content less than the
        // text field beside it does, so the row's spare width goes to the tab: two
        // single-character labels came out 264 pt wide, a blue bar across a third of the
        // window. The headline is the right thing to absorb that width instead — it is
        // left-aligned, so an over-wide frame is invisible, and it is the only view here that
        // has anything useful to do with the room.
        languageTabs.setContentHuggingPriority(.required, for: .horizontal)
        languageTabs.setContentCompressionResistancePriority(.required, for: .horizontal)
        // Named for the layout probe, which reports every control it finds on the content view.
        languageTabs.identifier = NSUserInterfaceItemIdentifier("languageTabs")

        // The icon-style picker, parked immediately left of the language tab: both answer
        // "how should this look", and neither fits in the footer, which has no spare width
        // left in English. `small` for the same reason the tab is — the title row is sized
        // by the 18 pt brand mark.
        iconStylePicker.controlSize = .small
        iconStylePicker.bezelStyle = .rounded
        // The button shows the mark, not a word: the two options *are* the two pictures, so
        // the artwork labels the control better than a translated noun would — and it keeps
        // the picker narrow enough to share the row with the headline and the tab. The names
        // are still spelled out inside the menu, where there is room for them.
        iconStylePicker.imagePosition = .imageOnly
        // Pinned rigid, like the tab beside it. Both must take their natural width, or the
        // row's spare width goes to the control instead of to the headline — which is how
        // the language tab once became a 264 pt blue bar.
        iconStylePicker.setContentHuggingPriority(.required, for: .horizontal)
        iconStylePicker.setContentCompressionResistancePriority(.required, for: .horizontal)
        // Named for the layout probe, which reports every control on the content view.
        iconStylePicker.identifier = NSUserInterfaceItemIdentifier("iconStylePicker")
        buildIconStyleMenu()

        refreshButton.bezelStyle = .rounded
        restoreButton.bezelStyle = .rounded
        restoreButton.toolTip = L("window.expandAll")
        collapseButton.bezelStyle = .rounded
        collapseButton.keyEquivalent = "\r"

        // The footer's labels give way before its controls do. Two groups are anchored from
        // opposite edges of one row — the launch checkbox from the left, the three buttons
        // from the right — and without this nothing stops them meeting in the middle once a
        // translation grows. Dropping the compression resistance of the two most expendable
        // titles makes the engine shorten those instead of letting anything overlap, and both
        // already carry a tooltip, so nothing is lost by truncating.
        for label in [autoCollapseCheckbox, refreshButton] {
            label.cell?.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        systemHeaderButton.isBordered = false
        systemHeaderButton.alignment = .left
        systemHeaderButton.controlSize = .small
        systemHeaderButton.font = .systemFont(ofSize: 11, weight: .semibold)
        systemHeaderButton.contentTintColor = .secondaryLabelColor
        systemHeaderButton.imagePosition = .imageLeading
        systemHeaderButton.image = Self.disclosureImage(expanded: false)
        // Identifies the control for the layout probe, which has to click it for real to
        // check that the section opens. Looking it up by its image name does not work:
        // an image built from an SF Symbol has no name.
        systemHeaderButton.identifier = NSUserInterfaceItemIdentifier("systemSectionHeader")

        // The rule is what separates "apps you can hide" from "system items you cannot".
        // Without it the section reads as three more rows that happen to be broken.
        let rule = NSBox()
        rule.boxType = .separator

        for view in [rule, systemHeaderButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            systemHeaderRow.addSubview(view)
        }
        NSLayoutConstraint.activate([
            rule.topAnchor.constraint(equalTo: systemHeaderRow.topAnchor, constant: 10),
            rule.leadingAnchor.constraint(equalTo: systemHeaderRow.leadingAnchor,
                                          constant: Metrics.rowInset),
            rule.trailingAnchor.constraint(equalTo: systemHeaderRow.trailingAnchor,
                                           constant: -Metrics.rowInset),

            systemHeaderButton.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: 7),
            systemHeaderButton.leadingAnchor.constraint(equalTo: systemHeaderRow.leadingAnchor,
                                                        constant: Metrics.rowInset),
            systemHeaderButton.trailingAnchor.constraint(lessThanOrEqualTo: systemHeaderRow.trailingAnchor,
                                                         constant: -Metrics.rowInset),
            systemHeaderButton.bottomAnchor.constraint(equalTo: systemHeaderRow.bottomAnchor),
        ])
    }

    private static func disclosureImage(expanded: Bool) -> NSImage? {
        NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: nil)
    }

    /// Fills the picker's menu: one item per style, each showing the mark it selects.
    ///
    /// Built once, at construction. The titles are lookups, so they follow the language tab —
    /// and since that restarts the app, they are rebuilt in the new language with everything
    /// else. The action lives on the items rather than on the button, because "which of these
    /// two do you want" is exactly what `representedObject` is for.
    private func buildIconStyleMenu() {
        let menu = NSMenu()
        for style in MenuBarIconStyle.allCases {
            let item = NSMenuItem(title: L(style.localizationKey),
                                  action: #selector(iconStyleChanged(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.image = iconStyleThumbnail(style)
            menu.addItem(item)
        }
        iconStylePicker.menu = menu
    }

    /// A menu-bar-proportioned thumbnail of a mark, for the picker's button and its menu.
    ///
    /// Both marks are drawn at the same *height* so the control keeps one width whichever
    /// style is in effect. The capsule is 44×18 and the daisy is square, so letting each keep
    /// its own scale would resize the button every time the user switched — and shift the
    /// headline beside it, which is the one view that has no business moving.
    ///
    /// The daisy shown here is always the coloured one: this menu is about which *mark* the
    /// menu bar wears, and the state that changes the colour is a separate matter — the
    /// tooltip spells out the state, and so does the row list.
    private func iconStyleThumbnail(_ style: MenuBarIconStyle) -> NSImage? {
        let height: CGFloat = 14
        switch style {
        case .capsule:
            guard let image = AppIcons.capsule(collapsed: false)?.copy() as? NSImage else { return nil }
            let ratio = AppIcons.menuBarSize.width / AppIcons.menuBarSize.height
            image.size = NSSize(width: (height * ratio).rounded(), height: height)
            return image
        case .daisy:
            return AppIcons.daisy(folded: true, size: height)
        }
    }

    private func layoutViews() {
        guard let content = window.contentView else { return }
        let allViews: [NSView] = [
            brandIcon, stateLabel, mechanismLabel, summaryLabel, scrollView, hintLabel,
            autoCollapseCheckbox, iconStylePicker, languageTabs, refreshButton, restoreButton,
            collapseButton,
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
            // The headline stops at the icon-style picker instead of running to the window
            // edge, because the title row's trailing corner now carries two controls. It is
            // the headline that gives way (see the compression resistance above).
            stateLabel.trailingAnchor.constraint(equalTo: iconStylePicker.leadingAnchor,
                                                 constant: -Metrics.iconStyleGap),

            // The picker leads the tab, and the tab closes the row: same baseline as the brand
            // mark, flush with the right-hand margin everything else lines up on. Putting the
            // tab here rather than in the footer is what buys the footer its single row.
            iconStylePicker.centerYAnchor.constraint(equalTo: brandIcon.centerYAnchor),
            iconStylePicker.trailingAnchor.constraint(equalTo: languageTabs.leadingAnchor,
                                                      constant: -Metrics.iconStyleGap),

            languageTabs.centerYAnchor.constraint(equalTo: brandIcon.centerYAnchor),
            languageTabs.trailingAnchor.constraint(equalTo: content.trailingAnchor,
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

            // One row, not two: the launch checkbox on the left edge, the three actions on the
            // right. This row only fits because the language picker left it — an earlier build
            // put the picker between the two groups, which needed about 617 pt of the 588 pt
            // available in English and drew the 29 pt that did not fit on top of Refresh.
            // Nothing is logged when that happens: two views anchored from opposite edges —
            // one from the left, one from the right — satisfy every constraint while
            // occupying the same space. Hence the guard below, which makes an overlap
            // impossible rather than merely absent.
            autoCollapseCheckbox.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                                          constant: Metrics.padding),
            autoCollapseCheckbox.centerYAnchor.constraint(equalTo: collapseButton.centerYAnchor),
            // The guard, not a nicety: with each group pinned to its own edge it is the *only*
            // constraint that keeps them apart. It cannot be broken, so a longer translation
            // has to shorten a label instead of overlapping one.
            autoCollapseCheckbox.trailingAnchor.constraint(
                lessThanOrEqualTo: refreshButton.leadingAnchor,
                constant: -Metrics.padding
            ),

            hintLabel.bottomAnchor.constraint(equalTo: collapseButton.topAnchor, constant: -12),

            collapseButton.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                                     constant: -Metrics.padding),
            collapseButton.bottomAnchor.constraint(equalTo: content.bottomAnchor,
                                                   constant: -Metrics.controlsBottomInset),

            restoreButton.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor,
                                                    constant: -Metrics.buttonSpacing),
            restoreButton.centerYAnchor.constraint(equalTo: collapseButton.centerYAnchor),

            // Refresh leads the action group, immediately left of *Show all*. The chain runs
            // right to left from the primary button, so each of the three keeps its natural
            // width and the group stays flush against the trailing margin.
            refreshButton.trailingAnchor.constraint(equalTo: restoreButton.leadingAnchor,
                                                    constant: -Metrics.buttonSpacing),
            refreshButton.centerYAnchor.constraint(equalTo: collapseButton.centerYAnchor),
        ])
    }

    private func wireActions() {
        autoCollapseCheckbox.target = self
        autoCollapseCheckbox.action = #selector(autoCollapseToggled)
        languageTabs.target = self
        languageTabs.action = #selector(languageChanged)
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
        restoreButton.target = self
        restoreButton.action = #selector(restoreClicked)
        collapseButton.target = self
        collapseButton.action = #selector(collapseClicked)
        systemHeaderButton.target = self
        systemHeaderButton.action = #selector(systemSectionToggled)
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

        // Two sections. Everything the user can act on goes in the main list. The system's
        // own menu bar items — and MenuBarKeeper itself — can never be hidden, so they move
        // behind a disclosure at the bottom rather than sitting in the list as rows that
        // look selectable, count towards the list, and do nothing when clicked.
        rows = entries.filter(\.canFold).map(addRow)

        let locked = entries.filter { !$0.canFold }
        if !locked.isEmpty {
            // A header is only worth its space if there is something to collapse it behind.
            // On a Mac where *nothing* is foldable there is not, so the section stays open.
            if !rows.isEmpty {
                systemHeaderButton.title = L("window.system.header", locked.count)
                systemHeaderButton.toolTip = L("window.system.tooltip")
                listStack.addArrangedSubview(systemHeaderRow)
                systemHeaderRow.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            }
            systemRows = locked.map(addRow)
            updateSystemSection()
        }
        syncControls()
    }

    /// Adds a row to the list and returns it.
    private func addRow(_ entry: MenuBarAppEntry) -> AppRowView {
        let row = AppRowView(entry: entry)
        row.isMarked = entry.canFold && FoldController.shared.isHidden(entry.bundleIdentifier)
        row.onMarkChange = { [weak self] changed in self?.markChanged(changed) }
        listStack.addArrangedSubview(row)
        // One row spans the whole list, so clicking anywhere on it toggles the app and
        // the state daisy lines up down the right-hand edge. Activated after the row joins
        // the hierarchy — before that the two anchors have no common ancestor and
        // activating throws.
        row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        return row
    }

    /// Shows or hides the system section.
    ///
    /// `NSStackView` drops hidden arranged subviews from its layout, so the list closes up
    /// instead of leaving a gap where the section used to be.
    private func updateSystemSection() {
        // With no header there is nothing to collapse behind, so the section stays open.
        let expanded = systemHeaderRow.superview == nil || showsSystemItems
        for row in systemRows { row.isHidden = !expanded }
        systemHeaderButton.image = Self.disclosureImage(expanded: expanded)
    }

    private func clearList() {
        for view in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rows.removeAll()
        systemRows.removeAll()
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
        // ⌥-click returns to following macOS. It is the only sensible place for that state to
        // live: a two-segment tab has no third cell to put it in, and dropping it entirely
        // would mean that picking a language once pins the app for good, with no way back.
        guard NSApp.currentEvent?.modifierFlags.contains(.option) != true else {
            L10n.select(.system)
            return
        }
        L10n.select(languageTabs.selectedSegment == 0 ? .simplifiedChinese : .english)
    }

    /// Applies the picked mark on the spot.
    ///
    /// Unlike the language tab this needs no relaunch: it changes one image, and none of the
    /// window's strings depend on it. The menu bar is redrawn before the picker's own button
    /// is updated, so the control can never show a mark the menu bar is not wearing.
    @objc private func iconStyleChanged(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = MenuBarIconStyle(rawValue: raw) else { return }
        MenuBarIconStyle.current = style
        (NSApp.delegate as? AppDelegate)?.applyIconStyle()
        syncIconStylePicker()
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

    /// Opens or closes the system section. Purely presentational — nothing here is ever
    /// submitted to the system — so there is no rescan to follow it.
    @objc private func systemSectionToggled() {
        showsSystemItems.toggle()
        updateSystemSection()
        guard showsSystemItems else { return }
        // Deferred by one turn. Un-hiding a row only *marks* the stack for layout, and the
        // document view keeps reporting its pre-section height until that pass runs — so a
        // scroll issued now is measured against a height that has not been applied yet and
        // moves nothing.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window.contentView?.layoutSubtreeIfNeeded()
            self.revealSystemSection()
        }
    }

    /// Scrolls the opened section into view.
    ///
    /// The list grows downwards into rows that were hidden, and a scroll view keeps its
    /// scroll position — so the rows appear below the visible area and the disclosure looks
    /// like it did nothing. Scrolling to the end shows the whole section, since the section
    /// is shorter than the list.
    private func revealSystemSection() {
        let clip = scrollView.contentView
        let overflow = listContainer.frame.height - clip.bounds.height
        guard overflow > 0 else { return }
        clip.scroll(to: NSPoint(x: 0, y: overflow))
        scrollView.reflectScrolledClipView(clip)
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

    /// Scans once more, a moment later, when a scan concludes the hide did not take.
    ///
    /// The system applies the restriction a second or two *after* the submission, so a scan
    /// taken immediately after it still sees the selected apps on the menu bar. Without this
    /// the window greets the user with an orange "it does not look applied — check the
    /// Accessibility permission" that is simply wrong, which is worse than saying nothing:
    /// it sends them to System Settings to fix something that is not broken. One extra scan
    /// settles it. It runs at most once per submission — reset in `syncFromModel` — so a
    /// genuine failure still gets reported as one instead of rescanning in a loop.
    private func recheckAfterCollapse() {
        guard !didRecheck else { return }
        didRecheck = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
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
        applyLanguageSelection()
        syncIconStylePicker()
    }

    /// Points the tab at the language that is actually on screen.
    ///
    /// Not at `L10n.language`, which is `.system` on a fresh install and has no segment of its
    /// own. Resolving it to the code being displayed is what makes the tab tell the truth: on
    /// a Chinese Mac *Follow System* resolves to 简体中文, so the tab must show 中 selected. A
    /// tab with nothing highlighted would read as broken, and one showing the wrong half would
    /// be worse — clicking it would be the only way to find out.
    private func applyLanguageSelection() {
        languageTabs.selectedSegment = L10n.effectiveCode.hasPrefix("zh") ? 0 : 1
    }

    /// Points the picker at the style actually in effect, and stamps that mark on the control
    /// itself.
    ///
    /// Reading the preference back — rather than trusting the item that was clicked — is what
    /// keeps the control honest: the same path runs at launch, when nothing was clicked at
    /// all, and it picks up a value written by an earlier run of the app.
    private func syncIconStylePicker() {
        let style = MenuBarIconStyle.current
        if let index = MenuBarIconStyle.allCases.firstIndex(of: style) {
            iconStylePicker.selectItem(at: index)
        }
        iconStylePicker.image = iconStyleThumbnail(style)
        iconStylePicker.imagePosition = .imageOnly
        iconStylePicker.toolTip = L("window.iconStyle.tooltip", L(style.localizationKey))
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
            recheckAfterCollapse()
        case (true, false, true):
            mechanismLabel.stringValue = L("window.mechanism.verified", selected.count)
            mechanismLabel.textColor = .systemGreen
        default:
            mechanismLabel.stringValue = L("window.mechanism.ok", MenuBarScanner.discoveryDescription)
            mechanismLabel.textColor = .secondaryLabelColor
        }
    }
}
