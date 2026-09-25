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
        /// Side of the state daisy between the count and the checkbox.
        static let daisySize: CGFloat = 18
    }

    let entry: MenuBarAppEntry
    private let markCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    /// Called when the selection changes, so the change can be applied and persisted.
    var onMarkChange: ((AppRowView) -> Void)?

    /// Whether this app is in the hidden area.
    var isMarked: Bool {
        get { markCheckbox.state == .on }
        set { markCheckbox.state = newValue ? .on : .off }
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
        let meta = makeMetaLabel()
        let daisy = makeDaisyView()

        markCheckbox.target = self
        markCheckbox.action = #selector(checkboxToggled)
        markCheckbox.toolTip = L("row.checkbox.tooltip")
        markCheckbox.setContentHuggingPriority(.required, for: .horizontal)

        // A row that cannot be hidden shows no checkbox at all — a disabled one still reads
        // as "click here to hide this", which is the one thing the row cannot do. A column
        // of greyed-out boxes also made the list look broken rather than deliberate. These
        // rows live in their own section, which says the same thing in words.
        var content: [NSView] = [iconView, textStack, meta, daisy]
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

    /// A hidden app no longer appears in the accessibility tree, so its item count is
    /// zero — describe that state in words instead of showing "0".
    private func makeMetaLabel() -> NSTextField {
        let text: String
        if entry.itemCount == 0 {
            text = L("row.meta.folded")
        } else {
            text = L10n.plural(entry.itemCount, singular: "row.meta.one", plural: "row.meta.many")
        }
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = entry.itemCount == 0 ? .tertiaryLabelColor : .secondaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    /// The state daisy at the row's right end: coloured and smiling when this app is
    /// folded away, grey and asleep while it is on the menu bar.
    ///
    /// The picture carries the state at a glance — which is its whole value, since the
    /// words beside it are small and monochrome. A missing asset simply leaves the view
    /// empty; the words still say what the state is.
    private func makeDaisyView() -> NSView {
        let view = NSImageView()
        view.image = AppIcons.daisy(folded: entry.itemCount == 0)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Metrics.daisySize),
            view.heightAnchor.constraint(equalToConstant: Metrics.daisySize),
        ])
        return view
    }

    // MARK: - Selection

    /// Clicking anywhere on the row toggles the selection — easier to hit than the
    /// small checkbox alone.
    override func mouseDown(with event: NSEvent) {
        guard entry.canFold else { return }
        isMarked.toggle()
        onMarkChange?(self)
    }

    @objc private func checkboxToggled() {
        onMarkChange?(self)
    }
}
