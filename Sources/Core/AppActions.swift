import AppKit

/// What can be done to an app living in the hidden area.
///
/// Why this layer has to exist: once an icon is hidden it leaves the accessibility tree
/// completely, so there is no element to query — see `StatusItemOpener` for the measurement
/// and for how the app's own status menu is reached anyway. What is left for this type is
/// everything that is *not* the status item: quitting, hiding, revealing in Finder, and the
/// standard ⌘, that opens Preferences.
enum AppActions {

    /// Brings the app to the front. Activation only — the icon already represents a
    /// running app, so it is never launched.
    static func activate(_ app: NSRunningApplication) {
        app.activate()
    }

    /// Hides the app's windows (equivalent to ⌘H). Only the windows go away; the
    /// process keeps running.
    static func hide(_ app: NSRunningApplication) {
        if !app.hide() {
            DebugLog.write("[app] hide refused for \(identifier(of: app))")
        }
    }

    /// Normal quit: the app gets to save documents and show its own confirmation.
    static func terminate(_ app: NSRunningApplication) {
        if !app.terminate() {
            DebugLog.write("[app] terminate refused for \(identifier(of: app))")
        }
    }

    /// Force quit (SIGKILL semantics). Destructive — **the caller must confirm first**.
    static func forceTerminate(_ app: NSRunningApplication) {
        if !app.forceTerminate() {
            DebugLog.write("[app] forceTerminate refused for \(identifier(of: app))")
        }
    }

    /// Reveals the app in Finder.
    static func revealInFinder(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens the app's Preferences.
    ///
    /// There is no public API to open an arbitrary app's preferences. The portable
    /// approach is to bring the app forward and then send ⌘, — the standard shortcut
    /// defined by Apple's Human Interface Guidelines, which almost every app honours.
    /// The cost is Accessibility permission, because it needs a synthetic key event.
    static func openPreferences(_ app: NSRunningApplication) {
        guard AccessibilityInventory.isTrusted else {
            DebugLog.write("[app] preferences needs Accessibility permission, skipping")
            AccessibilityInventory.requestTrust()
            AccessibilityInventory.openSystemSettings()
            return
        }
        app.activate()
        // Wait until the target really is frontmost, otherwise the keystroke lands on
        // whatever app was in front before.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            sendCommandComma()
        }
    }

    // MARK: - Internals

    /// Posts ⌘, to the HID event stream, matching a real key press.
    private static func sendCommandComma() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let comma: CGKeyCode = 43
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source,
                                      virtualKey: comma,
                                      keyDown: isDown) else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }

    private static func identifier(of app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? app.localizedName ?? "?"
    }
}
