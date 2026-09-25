import AppKit

/// Icon assets. The files live in `Resources/` and are copied into the bundle's
/// `Contents/Resources/` by `Scripts/build.sh`.
///
/// ## Why the menu bar icon is no longer a template image
///
/// `MenuBarTemplate.png` was a pure-black capsule marked as a *template*, so macOS
/// recoloured it to match the menu bar. The state icons are daisies now, and the
/// whole point of the design is the colour: a **coloured, smiling** daisy when icons
/// are folded away, a **grey, sleeping** one when everything is on the bar. That
/// distinction cannot survive template recolouring — both would become the same
/// monochrome shape — so the daisies load as ordinary full-colour images. They were
/// drawn for a menu bar (white petals read on dark; the grey stays legible on light),
/// and the state they express matters more than adapting to the theme.
///
/// ## Lookup order
///
/// The daisies are tried first; the template capsule remains as the fallback when
/// they are missing. Nothing in the app depends on artwork being present in order
/// to work.
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

    /// Menu bar icon for the given state.
    ///
    /// Collapsed — the user's icons are folded away — shows the coloured smiling
    /// daisy (`DaisyHidden`: the daisy standing for hidden apps); expanded shows the
    /// grey sleeping one (`DaisyVisible`). The template capsule is the fallback so a
    /// missing asset degrades to the old look instead of nothing.
    static func menuBar(collapsed: Bool) -> NSImage? {
        daisy(folded: collapsed) ?? {
            let variants = collapsed
                ? ["MenuBarTemplateCollapsed", "MenuBarTemplate"]
                : ["MenuBarTemplateExpanded", "MenuBarTemplate"]
            return variants.lazy.compactMap { loadTemplate(named: $0) }.first
        }()
    }

    /// The state daisy: coloured and smiling when the app is folded away, grey and
    /// asleep when it is on the menu bar.
    ///
    /// Full colour on purpose — see the type's header for why these are never
    /// template images.
    static func daisy(folded: Bool, size: CGFloat = daisySize) -> NSImage? {
        loadArtwork(named: folded ? "DaisyHidden" : "DaisyVisible", size: size)
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
