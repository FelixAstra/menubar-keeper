import AppKit

/// The daisy at the right end of a list row — a control, not a picture.
///
/// At rest it reports the state: coloured and smiling while the app is folded away, grey and
/// asleep while it is on the menu bar. That is the whole reason the artwork is full colour.
///
/// Under the pointer it becomes the *action* instead. A folded row swaps the daisy for the
/// trowel and its tooltip says what a click will do, because "dig this one back out" is exactly
/// the action and the state is already spelled out by the word beside it.
///
/// The swap happens only on a folded row, and that asymmetry is deliberate: a row on the menu
/// bar has no garden mark for "put it away" — the trowel means the opposite — so there the
/// pointer adds the highlight and the tooltip and nothing else. The rule that holds in both
/// cases is that this control never shows a mark for an action it cannot perform.
///
/// Clicking it does exactly what clicking the row does, which is what the checkbox does: one
/// state, three ways in. The row owns that state, so this only asks for it to change.
final class StateDaisyButton: NSButton {

    /// Which mark is on the control.
    ///
    /// Named for what each one means rather than for the file it comes from, because size and
    /// colour cannot tell them apart — all three are 18 pt full-colour images and none of them
    /// is a template. Anything checking that the swap happened needs a name to check.
    enum Mark: String {
        /// Folded away: coloured, smiling.
        case smiling
        /// On the menu bar: grey, asleep.
        case sleeping
        /// The pointer is over a folded row — this click digs it back out.
        case trowel
    }

    private enum Metrics {
        /// Side of the control. Larger than the artwork so the click target and the highlight
        /// have somewhere to live: an 18 pt square is a small thing to hit.
        static let side: CGFloat = 20
        static let cornerRadius: CGFloat = 5
        /// Highlight alpha, as a fraction of the label colour. Deliberately low — no other part
        /// of the row reacts to the pointer, so this has to read as "this bit is clickable" and
        /// nothing louder.
        static let highlightAlpha: CGFloat = 0.10
    }

    /// Whether the app this row describes is folded away.
    var isFolded = false {
        didSet { if isFolded != oldValue { updateAppearance() } }
    }

    /// Whether the pointer is over the control.
    ///
    /// The tracking area drives this in normal use. The `rowstatecheck` probe sets it directly,
    /// because a hover cannot be synthesised the way a click can: there is no event to post
    /// that AppKit will deliver as `mouseEntered`, so the only honest way to check the hover
    /// look is to put the control in the state the pointer would.
    var isHovering = false {
        didSet { if isHovering != oldValue { updateAppearance() } }
    }

    /// Rows whose app can never be hidden get a plain mark: no highlight, no swap, no click.
    var isInteractive = true {
        didSet { if isInteractive != oldValue { updateAppearance() } }
    }

    /// What a click should do.
    var onActivate: (() -> Void)?

    private(set) var mark: Mark = .sleeping
    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyUpOrDown
        // A focus ring around a picture button inside a list reads as a selected control, and
        // the row already answers to the keyboard through the checkbox.
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = Metrics.cornerRadius
        target = self
        action = #selector(activate)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Metrics.side),
            heightAnchor.constraint(equalToConstant: Metrics.side),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("StateDaisyButton is never loaded from a nib") }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // `.inVisibleRect` keeps the area in step with the control's own frame, so there is no
        // rectangle to recompute when the list is laid out again.
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    // MARK: - Appearance

    private func updateAppearance() {
        mark = isInteractive && isHovering && isFolded ? .trowel : (isFolded ? .smiling : .sleeping)
        // A missing trowel falls back to the state daisy rather than to an empty button: the
        // row still says something when an asset is absent from the bundle.
        image = artwork(for: mark) ?? artwork(for: isFolded ? .smiling : .sleeping)

        let highlighted = isInteractive && isHovering
        layer?.backgroundColor = highlighted
            ? NSColor.labelColor.withAlphaComponent(Metrics.highlightAlpha).cgColor
            : NSColor.clear.cgColor

        toolTip = isInteractive ? L(isFolded ? "row.state.restore.tooltip" : "row.state.fold.tooltip") : nil
        setAccessibilityLabel(toolTip)
    }

    private func artwork(for mark: Mark) -> NSImage? {
        switch mark {
        case .smiling: return AppIcons.daisy(folded: true, size: AppIcons.daisySize)
        case .sleeping: return AppIcons.daisy(folded: false, size: AppIcons.daisySize)
        case .trowel: return AppIcons.trowel(size: AppIcons.daisySize)
        }
    }

    @objc private func activate() {
        guard isInteractive else { return }
        onActivate?()
    }
}
