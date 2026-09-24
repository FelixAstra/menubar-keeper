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

        markCheckbox.target = self
        markCheckbox.action = #selector(checkboxToggled)
        markCheckbox.isEnabled = entry.canFold
        markCheckbox.toolTip = L(entry.canFold ? "row.checkbox.tooltip" : "row.checkbox.tooltip.locked")
        markCheckbox.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [iconView, textStack, meta, markCheckbox])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Metrics.spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            row.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.verticalInset),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.verticalInset),
        ])

        toolTip = L(entry.canFold ? "row.tooltip" : "row.checkbox.tooltip.locked")
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
