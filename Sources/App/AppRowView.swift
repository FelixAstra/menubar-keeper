import AppKit

/// One row of the app list: a single app that owns at least one menu bar icon.
final class AppRowView: NSView {

    /// Layout constants, grouped so the row's metrics are easy to tune in one place.
    private enum Metrics {
        static let iconSize: CGFloat = 22
        static let iconCornerRadius: CGFloat = 5
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 7
        static let spacing: CGFloat = 10
        /// Width of the checkbox column, reserved on rows that have no checkbox so the
        /// counts stay in line across both sections of the list. Matches the width the
        /// stack actually gives the checkbox — measured, not guessed.
        static let choiceColumn: CGFloat = 16
    }

    let entry: MenuBarAppEntry
    private let markCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    /// The state word and the state daisy, which together say what this row is doing.
    private let metaLabel = NSTextField(labelWithString: "")
    private let stateButton = StateDaisyButton()

    /// Called when the selection changes, so the change can be applied and persisted.
    var onMarkChange: ((AppRowView) -> Void)?

    /// Whether this app is in the hidden area.
    var isMarked: Bool {
        get { markCheckbox.state == .on }
        set {
            markCheckbox.state = newValue ? .on : .off
            // The daisy and the word follow the selection rather than the last scan. The row
            // is one answer to one question — "is this app folded away?" — so all three of its
            // controls have to agree; the scan cannot refresh for another second, and a row
            // that disagrees with its own checkbox for that second reads as broken. Whether
            // the system actually applied it is the headline's job, not the row's.
            syncState()
        }
    }

    init(entry: MenuBarAppEntry) {
        self.entry = entry
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AppRowView is never loaded from a nib") }

    // MARK: - Construction

    private func build() {
        let iconView = makeIconView()
        let textStack = makeTextStack()
        makeMetaLabel()

        markCheckbox.target = self
        markCheckbox.action = #selector(checkboxToggled)
        markCheckbox.toolTip = L("row.checkbox.tooltip")
        markCheckbox.setContentHuggingPriority(.required, for: .horizontal)

        // The daisy and the word are one control between them: the word says the state, the
        // daisy shows it, and clicking the daisy changes it. Both sit to the left of the
        // checkbox, so the column that lines up down the right-hand edge keeps lining up.
        stateButton.isInteractive = entry.canFold
        stateButton.onActivate = { [weak self] in self?.toggleMark() }

        // A row that cannot be hidden shows no checkbox at all — a disabled one still reads
        // as "click here to hide this", which is the one thing the row cannot do. A column
        // of greyed-out boxes also made the list look broken rather than deliberate. These
        // rows live in their own section, which says the same thing in words.
        var content: [NSView] = [iconView, textStack, metaLabel, stateButton]
        content.append(entry.canFold ? markCheckbox : reservedChoiceColumn())

        let row = NSStackView(views: content)
        row.orientation = .horizontal
        row.alignment = .centerY
        // Not the default. `NSStackView` still defaults to `.gravityAreas`, which only packs
        // the views and never stretches one — so the slack width stayed as empty space after
        // the checkbox instead of being absorbed by the text stack, and every control sat
        // bunched against the left edge. `.fill` hands the slack to the view with the lowest
        // hugging priority, which is the text stack.
        row.distribution = .fill
        row.spacing = Metrics.spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            row.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.verticalInset),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.verticalInset),
        ])

        syncState()
        toolTip = L(entry.canFold ? "row.tooltip" : "row.tooltip.locked")
    }

    /// An empty box the width of the checkbox, so a row without one still ends its count
    /// column in the same place as the rows above it.
    private func reservedChoiceColumn() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: Metrics.choiceColumn).isActive = true
        spacer.setContentHuggingPriority(.required, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.required, for: .horizontal)
        return spacer
    }

    private func makeIconView() -> NSView {
        let view = NSImageView()
        view.image = entry.icon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = Metrics.iconCornerRadius
        view.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            view.heightAnchor.constraint(equalToConstant: Metrics.iconSize),
        ])
        return view
    }

    private func makeTextStack() -> NSView {
        let title = NSTextField(labelWithString: entry.displayName)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitle = NSTextField(labelWithString: entry.subtitle)
        subtitle.font = .systemFont(ofSize: 10.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }

    /// The state word: folded away, or on the menu bar.
    ///
    /// It used to report the app's icon count while the app was on the bar and only switched to
    /// a word once it was hidden, so the same column answered two different questions and the
    /// two states did not look like each other. A state word in both states is the one thing
    /// the column can say that is true of the row rather than of the scan.
    private func makeMetaLabel() {
        metaLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        metaLabel.setContentHuggingPriority(.required, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    /// Puts the row's controls in step with `isMarked`.
    ///
    /// The checkbox is the state; these are its two other faces. `isMarked`'s setter and
    /// `build()` are the only callers, so there is no path that changes one and forgets the
    /// others.
    private func syncState() {
        let folded = isMarked
        stateButton.isFolded = folded
        metaLabel.stringValue = L(folded ? "row.state.folded" : "row.state.unfolded")
        // Dimmer when folded: a folded app is the quiet case — it is doing nothing on the menu
        // bar — while a visible one is the row the user is most likely looking for.
        metaLabel.textColor = folded ? .tertiaryLabelColor : .secondaryLabelColor
    }

    // MARK: - Selection

    /// Clicking anywhere on the row toggles the selection — easier to hit than the
    /// small checkbox alone. The state daisy does the same thing through the same path.
    override func mouseDown(with event: NSEvent) {
        toggleMark()
    }

    @objc private func checkboxToggled() {
        onMarkChange?(self)
    }

    private func toggleMark() {
        guard entry.canFold else { return }
        isMarked.toggle()
        onMarkChange?(self)
    }
}
