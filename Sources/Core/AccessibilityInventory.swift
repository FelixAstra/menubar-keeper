import AppKit
import ApplicationServices

/// One menu bar icon, with its position and owning app.
struct MenuBarItemInfo {
    let bundleIdentifier: String?
    let appName: String?
    /// Accessibility coordinate space (origin at the top left).
    let frame: CGRect
}

/// Enumerates menu bar icons through the public Accessibility API. Used on macOS 26
/// and earlier, where each app still owns an `AXExtrasMenuBar`.
///
/// The walk visits every running process that is an `.app` bundle and reads the
/// children of its `AXExtrasMenuBar`; each child is one status item. Requires
/// Accessibility permission, and is unavailable inside a sandbox (the sandbox denies
/// the mach lookup to `axserver`).
enum AccessibilityInventory {

    /// Round-trip timeout for a single app. The default runs to several seconds, and
    /// one unresponsive app would stall the whole scan.
    private static let messagingTimeout: Float = 0.1

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks the system to show its permission prompt (at most once per launch).
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Scans every menu bar icon synchronously. Takes about a second — call it off the
    /// main thread.
    static func snapshot() -> [MenuBarItemInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Only .app bundles can own status items. Skipping the many WebKit/XPC helper
        // processes brings the scan down from ~3 s to ~1 s.
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ownPID && $0.bundleURL?.pathExtension == "app"
        }

        var result: [MenuBarItemInfo] = []
        for app in apps {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, messagingTimeout)

            guard let bar = extrasMenuBar(of: element),
                  let children = copyChildren(of: bar) else { continue }

            for child in children {
                guard let frame = frame(of: child) else { continue }
                result.append(MenuBarItemInfo(bundleIdentifier: app.bundleIdentifier,
                                              appName: app.localizedName,
                                              frame: frame))
            }
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    // MARK: - Accessibility helpers

    private static func extrasMenuBar(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &value) == .success,
              let bar = value,
              // The attribute is undocumented and comes from an arbitrary process; check
              // what it actually is before casting, or a surprise type is a crash rather
              // than a skipped app.
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        return (bar as! AXUIElement)
    }

    private static func copyChildren(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, let sizeValue = sizeRef,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue((positionValue as! AXValue), .cgPoint, &position)
        AXValueGetValue((sizeValue as! AXValue), .cgSize, &size)

        // Zero-width or negatively positioned entries are system placeholders.
        guard size.width > 0, position.x >= 0 else { return nil }
        return CGRect(origin: position, size: size)
    }
}
