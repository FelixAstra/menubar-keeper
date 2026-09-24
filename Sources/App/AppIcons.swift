import AppKit

/// Icon assets. The files live in `Resources/` and are copied into the bundle's
/// `Contents/Resources/` by `Scripts/build.sh`.
///
/// ## Why the menu bar icon is a template image
///
/// `MenuBarTemplate.png` is pure black with transparent cut-outs: a solid capsule
/// with the arrows, divider and dots punched out of it. Marked as a *template*,
/// macOS replaces the opaque pixels with the current menu bar foreground colour —
/// a white capsule on a dark menu bar, a black one on a light menu bar. One file
/// therefore covers both appearances, and no per-appearance artwork is needed.
///
/// ## Lookup order
///
/// State-specific art is looked up first so it can be dropped in later without any
/// code change: `MenuBarTemplateCollapsed` / `MenuBarTemplateExpanded`, falling
/// back to `MenuBarTemplate`. When neither exists the accessor returns nil and the
/// caller falls back to an SF Symbol — **the app never depends on artwork being
/// present in order to work**.
enum AppIcons {

    /// Logical size of the menu bar icon in points, matching the 44×18 px 1x asset.
    static let menuBarSize = NSSize(width: 44, height: 18)

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
    static func menuBar(collapsed: Bool) -> NSImage? {
        let variants = collapsed
            ? ["MenuBarTemplateCollapsed", "MenuBarTemplate"]
            : ["MenuBarTemplateExpanded", "MenuBarTemplate"]
        return variants.lazy.compactMap { loadTemplate(named: $0) }.first
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
