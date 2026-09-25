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
    }

    let entry: MenuBarAppEntry
    /// The state word and the state daisy, which together say what this row is doing.
    private let metaLabel = NSTextField(labelWithString: "")
    private let stateButton = StateDaisyButton()

    /// Called when the selection changes, so the change can be applied and persisted.
    var onMarkChange: ((AppRowView) -> Void)?

    /// Whether this app is in the hidden area.
    ///
    /// The state lives on the row rather than in one of its controls. There used to be a
    /// checkbox holding it, but a checkbox and a daisy three points apart both answering "is
    /// this app folded away?" is two marks for one fact — the blue box only made the row look
    /// busier than what it has to say. Clicking anywhere on the row and clicking the daisy are
    /// two ways into this one setter, so nothing can change the state without the word and the
    /// mark following.
    var isMarked: Bool {
        get { marked }
        set {
            marked = newValue
            // The daisy and the word follow the selection rather than the last scan. The row
            // is one answer to one question — "is this app folded away?" — so both of its
            // controls have to agree; the scan cannot refresh for another second, and a row
            // that disagrees with its own state for that second reads as broken. Whether
            // the system actually applied it is the headline's job, not the row's.
            syncState()
        }
    }

    private var marked = false

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

        // The daisy and the word are one control between them: the word says the state, the
        // daisy shows it, and clicking the daisy changes it. The daisy is also the row's only
        // control, and so the only way in from the keyboard — it is the mark that shows the
        // state and the button that changes it, in one 20 pt target.
        stateButton.isInteractive = entry.canFold
        stateButton.onActivate = { [weak self] in self?.toggleMark() }

        // Every row ends the same way, whether or not its app can be hidden: the state word and
        // the daisy. A locked row's daisy is a plain sleeping mark with nothing to click, which
        // is what its own section header already says in words — so the two sections still line
        // up down the right-hand edge without a placeholder column holding a space open.
        let content: [NSView] = [iconView, textStack, metaLabel, stateButton]

        let row = NSStackView(views: content)
        row.orientation = .horizontal
        row.alignment = .centerY
        // Not the default. `NSStackView` still defaults to `.gravityAreas`, which only packs
        // the views and never stretches one — so the slack width stayed as empty space after
        // the last control instead of being absorbed by the text stack, and every control sat
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
    /// The selection is the state; these are its two faces. `isMarked`'s setter and `build()`
    /// are the only callers, so there is no path that changes one and forgets the other.
    private func syncState() {
        let folded = isMarked
        stateButton.isFolded = folded
        metaLabel.stringValue = L(folded ? "row.state.folded" : "row.state.unfolded")
        // Dimmer when folded: a folded app is the quiet case — it is doing nothing on the menu
        // bar — while a visible one is the row the user is most likely looking for.
        metaLabel.textColor = folded ? .tertiaryLabelColor : .secondaryLabelColor
        // The daisy has to say the state out loud, and the picture cannot: the button's own
        // label is the action ("fold this away" / "dig it back out"), so the state it is
        // currently reporting goes in the value, where a checkbox kept it before.
        stateButton.setAccessibilityValue(metaLabel.stringValue)
    }

    // MARK: - Selection

    /// Clicking anywhere on the row toggles the selection — easier to hit than the small mark
    /// alone. The state daisy does the same thing through the same path.
    override func mouseDown(with event: NSEvent) {
        toggleMark()
    }

    private func toggleMark() {
        guard entry.canFold else { return }
        isMarked.toggle()
        onMarkChange?(self)
    }
}
