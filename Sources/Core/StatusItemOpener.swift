import AppKit
import CoreGraphics

/// Opens a folded app's own status item menu, so a click on the floating bar does what a
/// click on the menu bar icon would have done.
///
/// Why this is not simply `AXUIElementPerformAction(element, kAXPressAction)`, in two parts,
/// both measured on macOS 27 rather than assumed:
///
/// * **A hidden item leaves the accessibility tree completely.** `Diagnostics.runTreeDump`
///   walks `com.apple.MenuBarAgent`'s tree with nine apps folded; every one of them reports
///   zero items. There is no element left to press, so the icon has to come back first.
/// * **Once it is back, `AXPress` is accepted and then ignored.** The call returns
///   `kAXErrorSuccess` and nothing opens. MenuBarKeeper's own status item is the control:
///   the same call on it does toggle the floating bar, so the mechanism is sound and a
///   third-party item is simply not listening — it is hosted inside the menu bar agent's
///   window, so the action reaches a proxy that no-ops. A **synthetic click** at the item's
///   rectangle does open the app's real menu.
///
/// So the sequence is: reveal the icon, click it, hide it again. Each step was measured:
///
/// * the reveal lands in 0.07–0.11 s, so the click feels immediate and the icon is visible
///   for about as long as a menu takes to appear;
/// * an open menu is a window of the *target* app and survives the icon disappearing, so
///   there is no need to wait for the menu to close before hiding again. That is what keeps
///   this two steps rather than a state machine tracking a foreign menu.
enum StatusItemOpener {

    /// How long to keep looking for the item after the reveal. The reveal itself takes about
    /// a tenth of a second; the rest is slack for a busy menu bar.
    private static let locateTimeout: TimeInterval = 1.5

    /// Gap between looks. Short enough not to be the latency, long enough that a busy menu
    /// bar is not walked dozens of times a second.
    private static let pollInterval: TimeInterval = 0.06

    /// How long the item has to hold still before it is clicked.
    ///
    /// Not a formality. The reveal re-lays out the whole menu bar, and the new item reports
    /// its final position *before* the layout around it has finished animating: clicking the
    /// first stable-looking frame it reports opened nothing for one of the three apps this
    /// was tested against, while the identical click a second later opened the menu. The
    /// frame does not move — the menu bar beneath it is still settling.
    private static let settleInterval: TimeInterval = 0.35

    /// How long the icon stays on the menu bar after the click. It only has to outlast the
    /// target app handling the mouse-up, and waiting longer would leave a stray icon behind
    /// for no reason.
    private static let rehideDelay: TimeInterval = 0.45

    /// Opens `bundle`'s own status item menu.
    ///
    /// The completion reports whether anything was clicked. `false` means the call never got
    /// as far as a click — no Accessibility permission, or the icon did not come back — and
    /// the caller should fall back to something that at least responds.
    ///
    /// Always calls back on the main thread.
    static func open(bundleIdentifier bundle: String, completion: @escaping (Bool) -> Void) {
        guard !bundle.isEmpty else {
            completion(false)
            return
        }
        guard AccessibilityInventory.isTrusted else {
            DebugLog.write("[open] \(bundle): no Accessibility permission, cannot locate the item")
            completion(false)
            return
        }

        let started = ProcessInfo.processInfo.systemUptime
        let fold = FoldController.shared
        // A no-op unless the app is hidden *and* the menu bar is collapsed, which is also
        // what makes this path work unchanged when the icon is simply on the menu bar.
        fold.beginTransientReveal(bundle)
        DebugLog.write("[open] \(bundle): revealed, \(fold.stateSummary)")

        locate(bundle, until: Date().addingTimeInterval(locateTimeout), candidate: nil) { item in
            guard let item, let frame = item.frame, let point = clickPoint(for: frame) else {
                fold.endTransientReveal()
                DebugLog.write("[open] \(bundle): no clickable item appeared within "
                               + "\(locateTimeout)s; reverting, \(fold.stateSummary)")
                completion(false)
                return
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            DebugLog.write(String(format: "[open] %@: clicking %.0f,%.0f (item %.0f,%.0f %.0f×%.0f) after %.2fs",
                                  bundle, point.x, point.y,
                                  frame.minX, frame.minY, frame.width, frame.height, elapsed))
            click(at: point)
            DispatchQueue.main.asyncAfter(deadline: .now() + rehideDelay) {
                fold.endTransientReveal()
                DebugLog.write("[open] \(bundle): re-hid after \(rehideDelay)s, \(fold.stateSummary)")
                completion(true)
            }
        }
    }

    // MARK: - Finding the item

    /// Looks for the app's status item until the deadline, and only hands one over once it
    /// has held still for `settleInterval`.
    ///
    /// See `settleInterval` for why stillness, rather than mere existence, is the condition.
    private static func locate(_ bundle: String,
                               until deadline: Date,
                               candidate: (frame: CGRect, since: Date)?,
                               completion: @escaping (MenuBarAgentInventory.Node?) -> Void) {
        guard Date() < deadline else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            // An app can own several items; the floating bar shows one icon per app, so the
            // leftmost is the one that icon stands for.
            let item = MenuBarAgentInventory.items(ofBundle: bundle).first { $0.frame != nil }
            DispatchQueue.main.async {
                guard let item, let frame = item.frame,
                      clickPoint(for: frame) != nil else {
                    after(pollInterval) {
                        locate(bundle, until: deadline, candidate: nil, completion: completion)
                    }
                    return
                }
                if let candidate, candidate.frame == frame,
                   Date().timeIntervalSince(candidate.since) >= settleInterval {
                    completion(item)
                    return
                }
                let next = candidate?.frame == frame ? candidate! : (frame, Date())
                after(pollInterval) {
                    locate(bundle, until: deadline, candidate: next, completion: completion)
                }
            }
        }
    }

    // MARK: - Aiming

    /// Where to click for an item, or nil if the result would not be on a screen.
    ///
    /// The centre is not used raw. Menu bar items report rectangles that are not always the
    /// drawn icon: CyberGhost's is `24×512` starting at `y = -241`, so the arithmetic centre
    /// happens to land correctly while anything less symmetrical would not. Clamping the
    /// point into the menu bar strip — the part of the screen above `visibleFrame` — turns a
    /// lucky hit into a correct one, and rejects an item that is genuinely off-screen
    /// instead of clicking whatever happens to be at the clamped spot.
    ///
    /// Not private: `Diagnostics` drives this and `click(at:)` so the probe aims and clicks
    /// exactly the way the app does. A probe with its own copy of the aiming would pass while
    /// the app failed, which is the one thing a probe must not do.
    static func clickPoint(for axFrame: CGRect) -> CGPoint? {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        for screen in NSScreen.screens {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            guard menuBarHeight > 0 else { continue }
            // The screen's menu bar occupies the top `menuBarHeight` points.
            let minY = top - screen.frame.maxY
            let maxY = minY + menuBarHeight
            let x = min(max(axFrame.midX, screen.frame.minX + 1), screen.frame.maxX - 1)
            let y = min(max(axFrame.midY, minY + 1), maxY - 1)
            guard axFrame.midX >= screen.frame.minX, axFrame.midX <= screen.frame.maxX else { continue }
            return CGPoint(x: x, y: y)
        }
        return nil
    }

    // MARK: - Clicking

    /// The shape of a synthetic click.
    ///
    /// A type rather than four constants because the shape is the thing in question: the same
    /// click opens WeChat's menu on one attempt and nothing on the next, and the candidates
    /// that could explain that — the event source, the gaps between the three events, which
    /// tap they are posted to — are only separable by trying them. `standard` is what the app
    /// ships; a probe varies one field at a time from there, so the two never drift into
    /// different implementations.
    struct Gesture {
        var stateID: CGEventSourceStateID
        /// Pause between the move that positions the pointer and the press.
        var moveToDown: TimeInterval
        /// How long the button is held down.
        var downToUp: TimeInterval
        var location: CGEventTapLocation

        static let standard = Gesture(stateID: .hidSystemState,
                                      moveToDown: 0.02,
                                      downToUp: 0.02,
                                      location: .cghidEventTap)

        /// Short form for probe logs: `hid 0.02/0.02 cghid`.
        var label: String {
            let source: String
            switch stateID {
            case .hidSystemState: source = "hid"
            case .combinedSessionState: source = "combined"
            case .privateState: source = "private"
            default: source = "state\(stateID.rawValue)"
            }
            let tap: String
            switch location {
            case .cghidEventTap: tap = "cghid"
            case .cgSessionEventTap: tap = "session"
            case .cgAnnotatedSessionEventTap: tap = "annotated"
            default: tap = "tap\(location.rawValue)"
            }
            return String(format: "%@ %.2f/%.2f %@", source, moveToDown, downToUp, tap)
        }
    }

    /// Clicks at a point in accessibility / CGEvent coordinates — origin top-left, which is
    /// *not* what `NSWindow.convertPoint(toScreen:)` returns. An `AXPosition` is already in
    /// exactly the space `CGEvent` wants; flipping it again would aim at the mirrored row.
    ///
    /// The pointer does move, and is deliberately not moved back. A real click on a menu bar
    /// icon leaves the pointer there too, and the menu opens directly underneath it — which
    /// is where the user is about to want it.
    static func click(at point: CGPoint, gesture: Gesture = .standard) {
        guard let source = CGEventSource(stateID: gesture.stateID) else { return }
        // Let the events through even though they were posted a moment ago. The source's own
        // suppression window is 0.25 s by default, and a posted pair arriving inside it is
        // dropped — which looks exactly like the target app refusing the click.
        source.localEventsSuppressionInterval = 0
        post(.mouseMoved, source: source, at: point, gesture: gesture)
        Thread.sleep(forTimeInterval: gesture.moveToDown)
        post(.leftMouseDown, source: source, at: point, gesture: gesture)
        Thread.sleep(forTimeInterval: gesture.downToUp)
        post(.leftMouseUp, source: source, at: point, gesture: gesture)
    }

    private static func post(_ type: CGEventType,
                             source: CGEventSource,
                             at point: CGPoint,
                             gesture: Gesture) {
        CGEvent(mouseEventSource: source, mouseType: type,
                mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: gesture.location)
    }

    private static func after(_ delay: TimeInterval, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body)
    }
}
