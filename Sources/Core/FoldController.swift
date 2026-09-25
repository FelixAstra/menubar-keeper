import AppKit

/// Owns "which apps are hidden" and translates that into the system's menu bar
/// visibility allow-list.
///
/// Key constraint: the system interface is an **allow-list** — we submit the apps
/// that may stay visible and everything else is hidden. The allow-list is therefore
/// recomputed on every submission from the apps that are running right now, and it
/// must include MenuBarKeeper itself, or the app's own icon disappears and the user
/// is left with no controls.
///
/// The allow-list is a static snapshot, so an app launched later has to be re-submitted
/// to be visible. This controller observes app launch/terminate and re-submits after a
/// short debounce.
final class FoldController {

    static let shared = FoldController()

    /// Folding is only meaningful on systems that provide the mechanism.
    static var isSupportedBySystem: Bool { MenuBarAgentInventory.isApplicable }

    static let ownBundleID = Bundle.main.bundleIdentifier ?? "io.github.felixastra.MenuBarKeeper"

    /// A visibility configuration submitted to the system.
    struct Configuration: Equatable {
        let systemItems: [Int]
        let bundles: [String]
    }

    /// `UserDefaults` keys. Not private because `Diagnostics` reports on them.
    enum Keys {
        static let hidden = "MenuBarKeeper.hiddenBundles"
        static let collapseOnLaunch = "MenuBarKeeper.collapseOnLaunch"
        static let released = "MenuBarKeeper.releasedBundles"
    }

    /// The whole selection, so a caller can capture it and put it back exactly as it
    /// was. Auto-detection computes a complete selection rather than a single edit,
    /// and the self-test has to leave no trace behind.
    struct Selection: Equatable {
        let hidden: Set<String>
        let released: Set<String>
    }

    // MARK: - Public state

    /// Apps moved into the hidden area (persisted).
    private(set) var hiddenBundles: Set<String> = []

    /// Apps the user took back out by hand. Auto-detection subtracts these, so
    /// releasing an app once is enough to keep it out on every later launch instead
    /// of having the next scan fold it straight back in.
    private(set) var releasedBundles: Set<String> = []

    /// Whether the hidden area is currently collapsed.
    private(set) var isCollapsed = false

    /// Apps put back on the menu bar for a moment, without changing the selection.
    ///
    /// Used to make a folded icon clickable: the icon has to exist on the menu bar before
    /// its own menu can be opened, and then it goes away again. Deliberately *not*
    /// persisted — a transient reveal is not a release, and the app must still be folded
    /// on the next launch.
    private var transientBundles: Set<String> = []

    /// Whether the selection is applied automatically at launch.
    var collapsesOnLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.collapseOnLaunch) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.collapseOnLaunch)
            onStateChange?()
        }
    }

    /// Why the mechanism is unavailable; nil means it is available.
    var availabilityMessage: String? {
        guard Self.isSupportedBySystem else {
            return L("reason.unsupportedOS", ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        }
        return visibility.unavailableReason
    }

    var isMechanismAvailable: Bool { availabilityMessage == nil }

    /// Reason the last submission failed, surfaced in the UI — failures are never silent.
    private(set) var lastError: String?

    /// Called on the main thread whenever visible state changes.
    var onStateChange: (() -> Void)?

    // MARK: - Internals

    private let visibility = MenuBarVisibility()
    private var assertion: AnyObject?
    private var pendingAssertion: AnyObject?
    private var currentConfiguration: Configuration?
    private var generation = 0
    private var rehideWorkItem: DispatchWorkItem?
    private var resyncWorkItem: DispatchWorkItem?
    private var revealFailsafe: DispatchWorkItem?

    /// One line describing what the mechanism currently believes, for the log.
    ///
    /// `apply` is asynchronous and skips a request whose configuration matches the last one it
    /// *completed*, so the state at any instant is not derivable from the calls made — an
    /// assertion in flight, a stale `currentConfiguration` and a skipped re-hide all look
    /// identical from outside. Printing all four together is what tells them apart.
    var stateSummary: String {
        "collapsed=\(isCollapsed) restricted=\(currentConfiguration != nil) "
            + "generation=\(generation) transient=\(transientBundles.sorted())"
    }

    private init() {
        // Auto-fold is the whole point of the app, so it is on unless the user turns it
        // off. Registering the default is what makes that true: `bool(forKey:)` answers
        // false for an absent key, which would silently mean "off" for everyone.
        UserDefaults.standard.register(defaults: [Keys.collapseOnLaunch: true])

        hiddenBundles = Set(UserDefaults.standard.stringArray(forKey: Keys.hidden) ?? [])
        releasedBundles = Set(UserDefaults.standard.stringArray(forKey: Keys.released) ?? [])
        // A bundle cannot be selected and released at the same time; a stale pair from
        // an older build would make the launch scan's result depend on key order.
        hiddenBundles.subtract(releasedBundles)
        // MenuBarKeeper never hides itself, or it would take away its own controls.
        hiddenBundles.remove(Self.ownBundleID)
        observeWorkspace()
    }

    // MARK: - Selection

    func isHidden(_ bundle: String) -> Bool { hiddenBundles.contains(bundle) }

    var selection: Selection { Selection(hidden: hiddenBundles, released: releasedBundles) }

    /// Moves an app into or out of the hidden area. Applies immediately.
    func setHidden(_ hidden: Bool, for bundle: String) {
        guard !bundle.isEmpty, bundle != Self.ownBundleID else { return }
        if hidden {
            hiddenBundles.insert(bundle)
            // Re-selecting clears an earlier release: the user asked for it back in.
            releasedBundles.remove(bundle)
        } else {
            hiddenBundles.remove(bundle)
            // Remember the release. Without this the next launch's scan would find the
            // app still sitting on the menu bar and quietly fold it in again.
            releasedBundles.insert(bundle)
        }
        persist()
        // With nothing selected there is no reason to keep holding a restriction.
        hiddenBundles.isEmpty ? restore() : collapse()
        onStateChange?()
    }

    /// Replaces the whole selection at once, then applies it.
    ///
    /// Used by auto-detection, which derives a complete selection from a scan, and by
    /// the self-test, which must restore exactly what it found.
    func setSelection(_ selection: Selection) {
        hiddenBundles = selection.hidden.subtracting([Self.ownBundleID])
        releasedBundles = selection.released.subtracting([Self.ownBundleID])
        hiddenBundles.subtract(releasedBundles)
        persist()
        hiddenBundles.isEmpty ? restore() : collapse()
        onStateChange?()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(Array(hiddenBundles).sorted(), forKey: Keys.hidden)
        defaults.set(Array(releasedBundles).sorted(), forKey: Keys.released)
    }

    // MARK: - Collapse / restore

    /// Collapses: removes the hidden apps from the menu bar.
    func collapse() {
        rehideWorkItem?.cancel()
        rehideWorkItem = nil
        apply(desiredConfiguration())
    }

    /// Restores: shows everything by dropping the restriction.
    func restore() {
        rehideWorkItem?.cancel()
        rehideWorkItem = nil
        apply(nil)
    }

    func toggleCollapsed() {
        isCollapsed ? restore() : collapse()
    }

    // MARK: - Transient reveal

    /// Puts one hidden app back on the menu bar without changing the selection.
    ///
    /// The only way to reach an app's own status menu: the system removes a hidden item
    /// from the accessibility tree entirely (measured — see `Diagnostics.runTreeDump`),
    /// so there is no element left to press. The icon has to come back first.
    ///
    /// Nothing is persisted and `hiddenBundles` is untouched, so `endTransientReveal()`
    /// restores the exact previous state and the app is folded again on the next launch.
    func beginTransientReveal(_ bundle: String) {
        guard hiddenBundles.contains(bundle), !transientBundles.contains(bundle) else { return }
        transientBundles.insert(bundle)
        apply(desiredConfiguration())
        scheduleRevealFailsafe()
    }

    /// Takes the transiently revealed app back off the menu bar.
    func endTransientReveal() {
        revealFailsafe?.cancel()
        revealFailsafe = nil
        guard !transientBundles.isEmpty else { return }
        transientBundles.removeAll()
        apply(desiredConfiguration())
    }

    /// Whether `bundle` is on the menu bar only for the moment.
    func isTransientlyRevealed(_ bundle: String) -> Bool { transientBundles.contains(bundle) }

    /// Puts the icon back after `failsafeRevealTimeout`, whether or not anything asked it to.
    ///
    /// A transient reveal is the one state this app can get into where the user's own menu bar
    /// is left wrong: it is entered for about a second, from a click handler, and left by a
    /// timer. Anything that drops that timer — a race in `apply`, a request that compares equal
    /// to one still in flight, a callback the generation guard discards — leaves the icon on
    /// the menu bar permanently, and a global menu bar edit is exactly the kind of state that
    /// should not depend on a chain of asynchronous hops all landing. Seen once in five runs
    /// before this existed: WeChat's icon was still on the bar minutes after the click.
    ///
    /// Three seconds is far longer than the 0.9 s the normal path takes and short enough that
    /// a stuck icon is not something the user has to notice and work around.
    private func scheduleRevealFailsafe() {
        revealFailsafe?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.transientBundles.isEmpty else { return }
            DebugLog.write("[fold] failsafe: a transient reveal outlived its timer, "
                           + "\(self.stateSummary)")
            self.endTransientReveal()
        }
        revealFailsafe = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.failsafeRevealTimeout, execute: work)
    }

    private static let failsafeRevealTimeout: TimeInterval = 3

    /// Shows everything, then collapses again after `seconds` — for "keep it clean, but
    /// let me take a quick look".
    func expandTemporarily(for seconds: TimeInterval = 10) {
        restore()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hiddenBundles.isEmpty else { return }
            self.collapse()
        }
        rehideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Automatic detection at launch

    /// Applies the launch state.
    ///
    /// With auto-fold on — the default — this is where the app earns its name: scan the
    /// menu bar, treat every app that can be hidden as selected, and collapse. Apps the
    /// user released by hand are subtracted, so a single release is enough to keep an app
    /// out of every later scan.
    func prepareOnLaunch() {
        guard collapsesOnLaunch else { return }

        // Refusing to auto-fold from outside /Applications is a safety rule, not
        // tidiness. Hiding icons is only safe when the system protects this app's own
        // status item, and it only does that for apps in a standard location — so
        // folding automatically from a checkout would take away the user's only control
        // before they had a chance to react.
        guard Installation.isInApplications else {
            DebugLog.write("[launch] auto-fold skipped: not running from "
                           + Installation.applicationsDirectory, when: "launch")
            return
        }

        // The scan walks the accessibility tree of every running app and takes the best
        // part of a second, so it never runs on the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let detected = MenuBarScanner.scan()
                .filter { $0.canFold && $0.isObservable }
                .map(\.bundleIdentifier)
            DispatchQueue.main.async {
                self?.adoptDetected(Set(detected))
            }
        }
    }

    /// Merges what the scan found into the selection and collapses.
    private func adoptDetected(_ detected: Set<String>) {
        // Union rather than replace: an app selected earlier but not running right now
        // has to stay selected, so it is folded the moment it comes back. The submitted
        // configuration is intersected with what is running, so the extra entries cost
        // nothing until then. The subtraction is what makes a release stick.
        let next = detected.union(hiddenBundles).subtracting(releasedBundles)
        guard !next.isEmpty else {
            DebugLog.write("[launch] auto-fold found nothing to hide", when: "launch")
            return
        }
        DebugLog.write("[launch] detected \(detected.sorted()) → selection \(next.sorted())",
                       when: "launch")
        // Goes through the same applier as everything else, so the selection is
        // persisted, submitted and announced by exactly one code path.
        setSelection(Selection(hidden: next, released: releasedBundles))
    }

    /// Always restores before quitting — the menu bar is never left restricted.
    func shutdown() {
        rehideWorkItem?.cancel()
        resyncWorkItem?.cancel()
        transientBundles.removeAll()
        restore()
    }

    // MARK: - Configuration

    /// Computes the allow-list to submit. Nil means "no restriction, show everything".
    private func desiredConfiguration() -> Configuration? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        // Transient reveals are subtracted here rather than removed from `hiddenBundles`,
        // so the selection the user sees in the window never flickers with them.
        let hidden = hiddenBundles.intersection(running).subtracting(transientBundles)
        // Nothing to hide means there is no reason to activate the mechanism; activation
        // has side effects, for instance Focus-related system extras can disappear too.
        guard !hidden.isEmpty else { return nil }

        // The allow-list must contain MenuBarKeeper itself.
        //
        // Whether its own icon survives also depends on the app being installed in
        // /Applications. Measured behaviour: when run from anywhere else, the system
        // hides this app's status item even with itself first in the allow-list, and the
        // user loses their only way in. See `Installation`.
        let others = running.subtracting(hidden).subtracting([Self.ownBundleID]).sorted()
        return Configuration(systemItems: MenuBarVisibility.systemItemIDs,
                             bundles: [Self.ownBundleID] + others)
    }

    /// Apps currently hidden *and* still running — what the floating bar displays.
    var foldedApplications: [NSRunningApplication] {
        hiddenBundles
            .compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
            .filter { !$0.isTerminated && $0.bundleIdentifier != Self.ownBundleID }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func apply(_ desired: Configuration?) {
        guard desired != currentConfiguration else { return }

        guard let desired else {
            releaseAssertions()
            currentConfiguration = nil
            isCollapsed = false
            onStateChange?()
            return
        }

        generation += 1
        let request = generation

        // The previous assertion is kept until the new one takes effect, otherwise every
        // toggle flashes (everything visible, then hidden again).
        pendingAssertion = visibility.activate(
            allowedSystemItems: desired.systemItems,
            allowedBundleIdentifiers: desired.bundles
        ) { [weak self] result in
            guard let self, self.generation == request else { return }
            switch result {
            case .success(let newAssertion):
                if let previous = self.assertion { self.visibility.invalidate(previous) }
                self.assertion = newAssertion
                self.pendingAssertion = nil
                self.currentConfiguration = desired
                self.isCollapsed = true
                self.lastError = nil
            case .failure(let error):
                // On failure fall all the way back to "everything visible" — never stop
                // halfway, with some icons hidden and no way to reason about it.
                self.pendingAssertion = nil
                self.currentConfiguration = nil
                self.isCollapsed = false
                self.lastError = error.localizedDescription
            }
            self.onStateChange?()
        }
    }

    private func releaseAssertions() {
        if let assertion { visibility.invalidate(assertion) }
        if let pendingAssertion { visibility.invalidate(pendingAssertion) }
        assertion = nil
        pendingAssertion = nil
        generation += 1
    }

    // MARK: - Reacting to the environment

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(self, selector: #selector(environmentChanged),
                               name: name, object: nil)
        }
    }

    /// Re-submits after an app launches or quits: a newly launched app is not in the
    /// allow-list and would otherwise be hidden along with everything else.
    @objc private func environmentChanged() {
        guard isCollapsed else { return }
        resyncWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isCollapsed else { return }
            // Bypass the "configuration unchanged, skip" shortcut: the allow-list itself
            // moves as apps start and stop.
            let desired = self.desiredConfiguration()
            if desired != self.currentConfiguration {
                self.currentConfiguration = nil
                self.apply(desired)
            }
        }
        resyncWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
