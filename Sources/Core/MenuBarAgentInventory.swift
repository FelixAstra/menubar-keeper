import AppKit
import ApplicationServices

/// Menu bar ownership discovery on macOS 27.
///
/// Why the old approach no longer works: since macOS 27 the entire menu bar is drawn
/// by `com.apple.MenuBarAgent` as a **single window**, and apps no longer own an
/// `AXExtrasMenuBar` element of their own. Walking each app's menu bar therefore
/// returns nothing. The direction has to be reversed — read the accessibility tree of
/// MenuBarAgent, then ask `AXUIElementGetPid` which process each element belongs to,
/// which reconstructs "which app occupies the menu bar".
///
/// The other consequence is granularity: macOS 27 shows or hides an app **as a
/// whole**, so a single icon cannot be hidden on its own. That happens to line up
/// exactly with the system visibility allow-list, which is keyed by bundle identifier.
///
/// Requires Accessibility permission; without it (or on an unsupported system) the
/// scan returns an empty array and the caller falls back.
enum MenuBarAgentInventory {

    static let agentBundleID = "com.apple.MenuBarAgent"

    struct Entry {
        let bundleIdentifier: String
        let appName: String
        /// Horizontal position, used to restore the real left-to-right order.
        let locationX: CGFloat?
    }

    /// Whether this discovery path applies to the running system.
    static var isApplicable: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    /// Reads the apps currently occupying the menu bar.
    ///
    /// No de-duplication: an app with several icons produces several entries, which
    /// is how the caller counts them. Ordered left to right; entries without a
    /// position come last.
    static func snapshot() -> [Entry] {
        guard AXIsProcessTrusted(),
              let agent = NSRunningApplication
                .runningApplications(withBundleIdentifier: agentBundleID).first else { return [] }

        let root = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)

        var items: [Entry] = []
        var budget = traversalBudget
        for window in children(of: root) {
            guard string(of: window, kAXRoleAttribute) == "AXWindow" else { continue }
            for group in children(of: window) {
                collect(group,
                        agentPID: agent.processIdentifier,
                        depth: 0,
                        items: &items,
                        budget: &budget)
            }
        }
        return items.sorted {
            ($0.locationX ?? .greatestFiniteMagnitude) < ($1.locationX ?? .greatestFiniteMagnitude)
        }
    }

    // MARK: - Recursive collection

    /// Caps the walk so an unexpected tree shape cannot make the scan hang.
    private static let traversalBudget = 256
    private static let maximumDepth = 4

    private static func collect(_ element: AXUIElement,
                                agentPID: pid_t,
                                depth: Int,
                                items: inout [Entry],
                                budget: inout Int) {
        guard depth <= maximumDepth, budget > 0 else { return }
        budget -= 1

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)

        // Reached an element owned by some app: that is an occupant. Record it and stop
        // descending — the host app also exposes its ordinary menus, which are not menu
        // bar items.
        if pid != agentPID, let bundle = app?.bundleIdentifier, !bundle.isEmpty {
            items.append(Entry(bundleIdentifier: bundle,
                               appName: app?.localizedName ?? bundle,
                               locationX: positionX(of: element)))
            return
        }

        // System items (clock, Wi-Fi, Control Center, …) are managed by the system and
        // are not ours to touch.
        if let identifier = string(of: element, kAXIdentifierAttribute),
           identifier.hasPrefix("com.apple.menuextra.") {
            return
        }

        for child in children(of: element) {
            collect(child, agentPID: agentPID, depth: depth + 1, items: &items, budget: &budget)
        }
    }

    // MARK: - Accessibility helpers

    private static func rawAttribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(of element: AXUIElement, _ key: String) -> String? {
        rawAttribute(element, key) as? String
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = rawAttribute(element, kAXChildrenAttribute) else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func positionX(of element: AXUIElement) -> CGFloat? {
        guard let value = rawAttribute(element, kAXPositionAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgPoint, &point) else { return nil }
        return point.x
    }
}
