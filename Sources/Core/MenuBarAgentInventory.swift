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
        walk()
            .filter(\.isOccupant)
            .map { Entry(bundleIdentifier: $0.bundleIdentifier ?? "",
                         appName: $0.appName ?? $0.bundleIdentifier ?? "",
                         locationX: $0.locationX) }
    }

    // MARK: - Walk

    /// One element visited during the walk, with everything needed to decide what it is
    /// and — for items — to act on it.
    ///
    /// The element is retained on purpose. `AXUIElementPerformAction` is how a status
    /// item's menu is opened without a synthetic click, and it needs the element itself;
    /// an identifier is not enough to get it back.
    struct Node {
        let element: AXUIElement
        let depth: Int
        let pid: pid_t
        let bundleIdentifier: String?
        let appName: String?
        let role: String?
        let identifier: String?
        /// Accessibility coordinates (origin top-left), nil when unreadable.
        let frame: CGRect?

        /// Actions the element accepts, read on demand.
        ///
        /// Deliberately not read during the walk: it is one extra round-trip per node and
        /// the walk visits up to 256 of them, while only the handful of items that are
        /// about to be acted on ever need the answer.
        var actions: [String] { actionNames(of: element) }

        /// Horizontal position alone, for the scans that only order and display it.
        /// Cheaper than `frame` and tolerant of a zero-size element.
        var locationX: CGFloat? { positionX(of: element) }

        /// Owned by an app rather than by the menu bar agent.
        var isOccupant: Bool { bundleIdentifier != nil }

        /// A system extra — clock, Wi-Fi, Control Center and friends.
        var isSystemItem: Bool { (identifier ?? "").hasPrefix("com.apple.menuextra.") }
    }

    /// Walks the agent's accessibility tree and returns every element it visits.
    ///
    /// Depth-first, left to right, stopping at occupants: a host app also exposes its
    /// ordinary menus below its menu bar item, and those are not items.
    ///
    /// Takes roughly 0.1–0.3 s. Never call it on the main thread.
    static func walk() -> [Node] {
        guard AXIsProcessTrusted(),
              let agent = NSRunningApplication
                .runningApplications(withBundleIdentifier: agentBundleID).first else { return [] }

        let root = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)

        var nodes: [Node] = []
        var budget = traversalBudget
        for window in children(of: root) {
            guard string(of: window, kAXRoleAttribute) == "AXWindow" else { continue }
            for group in children(of: window) {
                collect(group,
                        agentPID: agent.processIdentifier,
                        depth: 0,
                        nodes: &nodes,
                        budget: &budget)
            }
        }
        // Ordered by position, with unpositioned elements last, so callers that care about
        // left-to-right order get it and the ones that do not are unaffected.
        return nodes.sorted {
            ($0.frame?.minX ?? .greatestFiniteMagnitude) < ($1.frame?.minX ?? .greatestFiniteMagnitude)
        }
    }

    /// The menu bar items belonging to `bundle`, in left-to-right order.
    ///
    /// This is the lookup behind "make a hidden icon clickable": the element is what gets
    /// acted on, and an app may own more than one item.
    static func items(ofBundle bundle: String) -> [Node] {
        guard !bundle.isEmpty else { return [] }
        return walk().filter { $0.isOccupant && $0.bundleIdentifier == bundle && !$0.isSystemItem }
    }

    /// What sits under a point in accessibility coordinates — "what would a click hit?".
    ///
    /// The answer to a question the tree walk cannot answer. Walking down from the menu bar
    /// agent tells you where an item *reports* it is; hit-testing tells you what actually
    /// receives a click there. When those disagree, every conclusion drawn from the reported
    /// rectangles is wrong — which is exactly the trap this exists to avoid: a click aimed
    /// from the tree can land on a neighbouring icon and look, from the outside, like the
    /// target app ignoring it.
    static func describeElement(at point: CGPoint) -> String {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),
                                               Float(point.x), Float(point.y),
                                               &element) == .success,
              let element else { return "none" }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            ?? "pid-\(pid)"
        let role = string(of: element, kAXRoleAttribute) ?? "?"
        let rect = frame(of: element).map { box($0) } ?? "no-frame"
        return "\(bundle)[\(role)] \(rect)"
    }

    private static func box(_ rect: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0f×%.0f)",
               rect.minX, rect.minY, rect.width, rect.height)
    }

    /// The menu bars an app currently has open, by title.
    ///
    /// The direct answer to "did clicking the icon open the app's menu?". Watching for a window
    /// to appear is indirect and got it wrong twice: a menu is not always a window an app owns
    /// in a way `CGWindowListCopyWindowInfo` distinguishes from the app's ordinary windows, and
    /// an app that opens its main window on a status-item click looks identical to one opening
    /// a menu. An open menu is `AXMenu` in the app's own accessibility tree, and nothing else
    /// is — so this counts it rather than inferring it.
    static func openMenus(ofBundle bundle: String) -> [String] {
        guard !bundle.isEmpty,
              let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundle).first else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)

        var found: [String] = []
        var budget = 64
        collectMenus(root, depth: 0, into: &found, budget: &budget)
        return found
    }

    private static func collectMenus(_ element: AXUIElement,
                                     depth: Int,
                                     into found: inout [String],
                                     budget: inout Int) {
        // Menus hang off the app element itself rather than being nested deep inside it, so a
        // shallow walk is enough and keeps this cheap enough to poll.
        guard depth <= 2, budget > 0 else { return }
        budget -= 1
        for child in children(of: element) {
            if string(of: child, kAXRoleAttribute) == kAXMenuRole as String {
                found.append(string(of: child, kAXTitleAttribute) ?? "(untitled)")
                continue
            }
            collectMenus(child, depth: depth + 1, into: &found, budget: &budget)
        }
    }

    // MARK: - Recursive collection

    /// Caps the walk so an unexpected tree shape cannot make the scan hang.
    private static let traversalBudget = 256
    private static let maximumDepth = 4

    private static func collect(_ element: AXUIElement,
                                agentPID: pid_t,
                                depth: Int,
                                nodes: inout [Node],
                                budget: inout Int) {
        guard depth <= maximumDepth, budget > 0 else { return }
        budget -= 1

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)

        nodes.append(Node(element: element,
                          depth: depth,
                          pid: pid,
                          bundleIdentifier: app?.bundleIdentifier,
                          appName: app?.localizedName,
                          role: string(of: element, kAXRoleAttribute),
                          identifier: string(of: element, kAXIdentifierAttribute),
                          frame: frame(of: element)))

        // Reached an element owned by some app: that is an occupant. Stop descending — the
        // host app also exposes its ordinary menus, which are not menu bar items.
        if pid != agentPID, let bundle = app?.bundleIdentifier, !bundle.isEmpty { return }

        // System items (clock, Wi-Fi, Control Center, …) are managed by the system and
        // are not ours to touch. Recorded above so a dump can show them; not descended.
        if let identifier = string(of: element, kAXIdentifierAttribute),
           identifier.hasPrefix("com.apple.menuextra.") {
            return
        }

        for child in children(of: element) {
            collect(child, agentPID: agentPID, depth: depth + 1, nodes: &nodes, budget: &budget)
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

    /// Position *and* size, in accessibility coordinates (origin at the top-left).
    ///
    /// Unlike `positionX` this demands a readable, non-empty size: the result is used to
    /// aim a click, and a zero-sized rectangle would land on whatever is at the origin.
    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = rawAttribute(element, kAXPositionAttribute),
              let sizeValue = rawAttribute(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// The names of the actions the element accepts. Empty when the element refuses to
    /// answer — notably once the system has hidden it, which is itself the signal that
    /// there is nothing left to press.
    private static func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    /// Asks the element to perform an accessibility action.
    ///
    /// This is how a status item's menu is opened without moving the pointer. An
    /// `AXPress` on a menu bar item is the same request a real click makes, minus the
    /// click — which matters here because the item may not be where a click could
    /// reasonably be aimed.
    @discardableResult
    static func perform(_ action: String, on element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// The press action, as reported by the system.
    static let pressAction = kAXPressAction as String
}
