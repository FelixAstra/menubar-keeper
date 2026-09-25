import AppKit

/// Which mark MenuBarKeeper wears in the menu bar.
///
/// Two things want this one slot, and they pull in opposite directions:
///
/// * `.capsule` — the shipping brand mark (`MenuBarTemplate`: the black capsule with a
///   back-chevron and three dots). It says *what the app is*, and it is what every
///   existing install already shows.
/// * `.daisy` — the garden daisies, which say *what the state is*: a coloured, smiling
///   daisy while icons are folded away, a grey, sleeping one while everything is on the
///   bar. The colour is the whole message, so these are never template images.
///
/// Neither is wrong, so the user picks. `.capsule` is the default **on purpose**: an
/// install that never opens this control has to look exactly the way it looked before the
/// daisies existed. Adding an option must not repaint anyone's menu bar behind their back.
///
/// The choice is purely cosmetic — both marks are legible, and nothing in the app depends
/// on which one is drawn — so it applies immediately, without the relaunch the language
/// tab needs.
enum MenuBarIconStyle: String, CaseIterable {

    /// The brand capsule. Template image, so macOS tints it for the menu bar.
    case capsule

    /// The state daisy: coloured when folded away, grey when everything is visible.
    case daisy

    /// `UserDefaults` key. Not private: `Diagnostics` reports it.
    static let defaultsKey = "MenuBarKeeper.menuBarIconStyle"

    /// The style in effect right now.
    ///
    /// Anything unset — a fresh install, or a value written by a future build this one
    /// does not know — resolves to `.capsule`, the mark the app has always shipped with.
    /// A missing key must never be the reason the menu bar changes appearance.
    static var current: MenuBarIconStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else { return .capsule }
            return MenuBarIconStyle(rawValue: raw) ?? .capsule
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// Localisation key for the label shown in the picker and its menu.
    var localizationKey: String {
        switch self {
        case .capsule: return "window.iconStyle.capsule"
        case .daisy: return "window.iconStyle.daisy"
        }
    }
}
