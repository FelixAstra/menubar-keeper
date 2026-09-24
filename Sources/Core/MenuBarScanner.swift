import AppKit

/// How one app occupies the menu bar — an app may own several icons.
struct MenuBarAppEntry {
    let bundleIdentifier: String
    let appName: String
    let icon: NSImage?
    let itemCount: Int
    /// Horizontal position on the menu bar; nil when hidden or unavailable.
    let leftmostX: CGFloat?
    /// Whether the app can still be observed. Hiding an app removes it from the
    /// accessibility tree, so this doubles as the "did it work" signal.
    let isObservable: Bool
    let isSystemApp: Bool
    let isSelf: Bool

    /// System components (clock, Control Center, …) and MenuBarKeeper itself stay out
    /// of folding, so the user can never lock themselves out of the controls.
    var canFold: Bool { !isSystemApp && !isSelf }

    var displayName: String { appName.isEmpty ? bundleIdentifier : appName }

    var subtitle: String {
        if isSelf { return L("row.subtitle.self", bundleIdentifier) }
        if isSystemApp { return L("row.subtitle.system", bundleIdentifier) }
        return bundleIdentifier
    }
}

/// Reads the menu bar and aggregates what it finds by app.
enum MenuBarScanner {

    /// Which discovery path this system uses, shown in the main window.
    static var discoveryDescription: String {
        MenuBarAgentInventory.isApplicable ? L("discovery.agent") : L("discovery.legacy")
    }

    /// Scans and groups by app. Takes roughly 0.2–1 s — never call it on the main thread.
    static func scan() -> [MenuBarAppEntry] {
        var aggregated: [String: (name: String, count: Int, leftmostX: CGFloat?)] = [:]

        if MenuBarAgentInventory.isApplicable {
            for item in MenuBarAgentInventory.snapshot() {
                merge(bundle: item.bundleIdentifier,
                      name: item.appName,
                      x: item.locationX,
                      into: &aggregated)
            }
        } else {
            for item in AccessibilityInventory.snapshot() {
                guard let bundle = item.bundleIdentifier, !bundle.isEmpty else { continue }
                merge(bundle: bundle,
                      name: item.appName ?? bundle,
                      x: item.frame.minX,
                      into: &aggregated)
            }
        }

        // A hidden app disappears from the accessibility tree, but the user still has
        // to see and manage it — add back anything saved in the hidden area.
        for bundle in FoldController.shared.hiddenBundles where aggregated[bundle] == nil {
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
            aggregated[bundle] = (name: app?.localizedName ?? bundle, count: 0, leftmostX: nil)
        }

        // `FoldController.ownBundleID` rather than `Bundle.main.bundleIdentifier`: it
        // carries a fallback, so "is this us?" cannot silently answer no and let the user
        // mark the app's own icon for hiding.
        let ownBundle = FoldController.ownBundleID
        let entries: [MenuBarAppEntry] = aggregated.map { bundle, info in
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
            return MenuBarAppEntry(
                bundleIdentifier: bundle,
                appName: app?.localizedName ?? info.name,
                icon: app?.icon ?? icon(forBundle: bundle),
                itemCount: info.count,
                leftmostX: info.leftmostX,
                isObservable: info.count > 0,
                isSystemApp: bundle.hasPrefix("com.apple."),
                isSelf: bundle == ownBundle
            )
        }
        // Items still on the menu bar first, in their real left-to-right order;
        // hidden ones after them.
        return entries.sorted { lhs, rhs in
            if lhs.isObservable != rhs.isObservable { return lhs.isObservable }
            return (lhs.leftmostX ?? .greatestFiniteMagnitude)
                < (rhs.leftmostX ?? .greatestFiniteMagnitude)
        }
    }

    private static func merge(bundle: String,
                              name: String,
                              x: CGFloat?,
                              into map: inout [String: (name: String, count: Int, leftmostX: CGFloat?)]) {
        guard !bundle.isEmpty else { return }
        if var existing = map[bundle] {
            existing.count += 1
            if let x { existing.leftmostX = min(existing.leftmostX ?? x, x) }
            map[bundle] = existing
        } else {
            map[bundle] = (name: name, count: 1, leftmostX: x)
        }
    }

    private static func icon(forBundle bundle: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
