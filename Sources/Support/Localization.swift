import AppKit

/// String lookup for everything the user can read.
///
/// The bundle ships `en.lproj` and `zh-Hans.lproj` tables. macOS picks the one
/// matching the user's *Language & Region* preference automatically; a manual
/// override chosen from the main window is stored in `UserDefaults` and takes
/// precedence — see `Language`.
///
/// A missing key returns the key itself, so a gap shows up immediately in the UI
/// instead of silently rendering an empty label.
enum L10n {

    // MARK: - Language

    /// A language the app ships a translation for.
    ///
    /// `system` means "follow macOS" and is the default. Anything else pins the app to
    /// that language regardless of the system setting — which is what the 中 / EN tab in
    /// the main window's title row writes.
    enum Language: String {
        case system
        case english = "en"
        case simplifiedChinese = "zh-Hans"

        /// The `.lproj` folder this choice resolves to, or nil for `system`.
        var resourceCode: String? {
            self == .system ? nil : rawValue
        }
    }

    private static let overrideKey = "MenuBarKeeper.language"

    /// User's explicit choice, or `.system` when they have never picked one.
    static var language: Language {
        get {
            guard let raw = UserDefaults.standard.string(forKey: overrideKey),
                  let choice = Language(rawValue: raw) else { return .system }
            return choice
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: overrideKey) }
    }

    /// The code that is actually in effect right now, after resolving `.system`.
    static var effectiveCode: String {
        if let pinned = language.resourceCode { return pinned }
        // `preferredLocalizations` is computed by Foundation from the .lproj folders
        // present in the bundle and the user's ordered language preference.
        return Bundle.main.preferredLocalizations.first ?? Language.english.rawValue
    }

    // MARK: - Lookup

    /// Bundle the active language's tables are read from. Cached per language so a
    /// long-running process does not hit the filesystem on every lookup.
    private static var cached: (code: String, bundle: Bundle)?

    private static var table: Bundle {
        let code = effectiveCode
        if let cached, cached.code == code { return cached.bundle }
        let resolved = Bundle.main.path(forResource: code, ofType: "lproj")
            .flatMap(Bundle.init(path:))
            ?? Bundle.main
        cached = (code, resolved)
        return resolved
    }

    /// Looks up `key` in the active language's table.
    static func t(_ key: String) -> String {
        table.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Looks up `key` and substitutes its `%d` / `%@` placeholders.
    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: arguments)
    }

    /// Picks between two keys based on `count`.
    ///
    /// A singular/plural pair is enough for the two languages we ship. Languages
    /// with richer plural rules would need a `.stringsdict` instead.
    static func plural(_ count: Int, singular: String, plural many: String) -> String {
        t(count == 1 ? singular : many, count)
    }

    // MARK: - Switching

    /// Persists a new choice and restarts the app.
    ///
    /// A restart rather than a live refresh: window content, menu titles and the
    /// status item tooltip are all built once and would otherwise be left in the
    /// previous language. Restarting keeps the result honest and predictable.
    ///
    /// The restart is skipped when the visible language would not change — picking the
    /// segment that is already in effect, because `.system` happened to resolve to it. That
    /// is a real case now that the switcher is a two-segment tab: on a Chinese Mac the tab
    /// already shows 中, and clicking it would otherwise raise "Language changed", relaunch
    /// the app and land on exactly the same window.
    static func select(_ choice: Language) {
        guard choice != language else { return }
        let changesWhatYouSee = choice.resourceCode != effectiveCode
        language = choice
        guard changesWhatYouSee else { return }

        let alert = NSAlert()
        alert.messageText = t("language.changed.title")
        alert.informativeText = t("language.changed.body")
        alert.addButton(withTitle: t("common.ok"))
        alert.runModal()

        Installation.relaunch(at: Bundle.main.bundlePath)
    }
}

/// Shorthand for `L10n.t`. Kept deliberately short because it appears hundreds of
/// times across the UI code.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    arguments.isEmpty ? L10n.t(key) : L10n.t(key, arguments)
}
