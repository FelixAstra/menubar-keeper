import AppKit

/// Icon assets. The files live in `Resources/` and are copied into the bundle's
/// `Contents/Resources/` by `Scripts/build.sh`.
///
/// ## The menu bar mark is a choice, and the two options are not interchangeable
///
/// `MenuBarTemplate.png` is a pure-black capsule marked as a *template*, so macOS
/// recolours it to match the menu bar. The daisies are the opposite: the whole point of
/// that design is the colour — a **coloured, smiling** daisy when icons are folded away,
/// a **grey, sleeping** one when everything is on the bar. That distinction cannot survive
/// template recolouring (both would become the same monochrome shape), so the daisies load
/// as ordinary full-colour images. Their white petals need a subtle outline against a
/// light menu bar; the sleeping artwork also needs more opacity there. Both treatments
/// are applied at draw time so the original artwork stays intact on dark backgrounds.
///
/// Which one is drawn is the user's call — see `MenuBarIconStyle`. The capsule is the
/// default, so an install that never touches the control looks exactly as it did before
/// the daisies existed.
///
/// ## Lookup order
///
/// `menuBar(collapsed:style:)` resolves the chosen style, and each branch falls back to
/// the *other* artwork when its own is missing. Nothing in the app depends on artwork
/// being present in order to work.
enum AppIcons {

    /// Logical size of the menu bar icon in points, matching the 44×18 px 1x asset.
    static let menuBarSize = NSSize(width: 44, height: 18)

    /// Side of the square daisy shown in the menu bar and in the list rows.
    static let daisySize: CGFloat = 18

    /// Application icon, used by Finder, the Accessibility list and every alert.
    static var appIcon: NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarKeeper", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    /// Brand mark shown next to the title in the main window. Always the base
    /// `MenuBarTemplate`, never a state variant: it is an identity mark, not a state
    /// indicator.
    static func brandMark(size: NSSize = menuBarSize) -> NSImage? {
        guard let image = loadTemplate(named: "MenuBarTemplate")?.copy() as? NSImage else { return nil }
        image.size = size
        return image
    }

    /// Menu bar icon for the given state, in the style the user picked.
    ///
    /// `style` decides *which* mark is drawn; `collapsed` only changes the daisy, the one
    /// of the two that reports the fold state. The capsule ignores it — it is an identity
    /// mark, not a state indicator.
    ///
    /// Each branch falls back to the other mark first, so a missing asset degrades to a
    /// usable icon rather than nothing; `AppDelegate` has an SF Symbol behind that.
    static func menuBar(collapsed: Bool, style: MenuBarIconStyle = .current) -> NSImage? {
        switch style {
        case .capsule:
            return capsule(collapsed: collapsed) ?? daisy(folded: collapsed)
        case .daisy:
            return daisy(folded: collapsed) ?? capsule(collapsed: collapsed)
        }
    }

    /// The brand capsule, as a template image so macOS tints it for the menu bar.
    ///
    /// The `MenuBarTemplateCollapsed` / `Expanded` variants are still probed first: they
    /// were never drawn, and the intent is that dropping either one in is all it takes to
    /// give the capsule its own two states.
    static func capsule(collapsed: Bool) -> NSImage? {
        let variants = collapsed
            ? ["MenuBarTemplateCollapsed", "MenuBarTemplate"]
            : ["MenuBarTemplateExpanded", "MenuBarTemplate"]
        return variants.lazy.compactMap { loadTemplate(named: $0) }.first
    }

    /// The state daisy: coloured and smiling when the app is folded away, grey and
    /// asleep when it is on the menu bar.
    ///
    /// Full colour on purpose — see the type's header for why these are never
    /// template images.
    static func daisy(folded: Bool, size: CGFloat = daisySize) -> NSImage? {
        guard let artwork = loadArtwork(named: folded ? "DaisyHidden" : "DaisyVisible", size: size) else {
            return nil
        }
        let image = NSImage(size: artwork.size, flipped: false) { rect in
            let appearance = NSAppearance.currentDrawing()
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if !isDark {
                // A thin sticker-like edge preserves the original petal shape and smile.
                // The sleeping PNG is intentionally translucent; layering it on light
                // backgrounds makes its grey readable without changing its colour.
                let passes = folded ? 1 : 3
                let silhouette = NSImage(size: artwork.size, flipped: false) { bounds in
                    for _ in 0..<passes {
                        artwork.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
                    }
                    if let context = NSGraphicsContext.current?.cgContext {
                        context.saveGState()
                        context.setBlendMode(.sourceIn)
                        context.setFillColor(NSColor(calibratedRed: 0.39, green: 0.45, blue: 0.51,
                                                     alpha: folded ? 0.72 : 0.86).cgColor)
                        context.fill(bounds)
                        context.restoreGState()
                    }
                    return true
                }
                let edge: CGFloat = 0.45
                for offset in [NSPoint(x: edge, y: 0), NSPoint(x: -edge, y: 0),
                               NSPoint(x: 0, y: edge), NSPoint(x: 0, y: -edge)] {
                    silhouette.draw(in: rect.offsetBy(dx: offset.x, dy: offset.y),
                                    from: .zero, operation: .sourceOver, fraction: 1)
                }
                for _ in 0..<passes {
                    artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                }
            } else {
                artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The garden trowel, marking the actions that put an app back on the menu bar.
    static func trowel(size: CGFloat = daisySize) -> NSImage? {
        loadArtwork(named: "RestoreTrowel", size: size)
    }

    /// Loads a full-colour image at a consistent size, preferring the @2x file so the
    /// icon is pixel-accurate on Retina displays.
    private static func loadArtwork(named name: String, size: CGFloat) -> NSImage? {
        for candidate in ["\(name)@2x", name] {
            guard let url = Bundle.main.url(forResource: candidate, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { continue }
            image.size = NSSize(width: size, height: size)
            image.isTemplate = false
            return image
        }
        return nil
    }

    /// Loads a template image at a consistent size: the @2x file is preferred so the
    /// icon is pixel-accurate on Retina displays.
    private static func loadTemplate(named name: String) -> NSImage? {
        for candidate in ["\(name)@2x", name] {
            guard let url = Bundle.main.url(forResource: candidate, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { continue }
            image.size = menuBarSize
            image.isTemplate = true
            return image
        }
        return nil
    }
}
