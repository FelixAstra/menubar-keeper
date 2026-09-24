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
    }

    // MARK: - Public state

    /// Apps moved into the hidden area (persisted).
    private(set) var hiddenBundles: Set<String> = []

    /// Whether the hidden area is currently collapsed.
    private(set) var isCollapsed = false

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

    private init() {
        hiddenBundles = Set(UserDefaults.standard.stringArray(forKey: Keys.hidden) ?? [])
        // MenuBarKeeper never hides itself, or it would take away its own controls.
        hiddenBundles.remove(Self.ownBundleID)
        observeWorkspace()
    }

    // MARK: - Selection

    func isHidden(_ bundle: String) -> Bool { hiddenBundles.contains(bundle) }

    /// Moves an app into or out of the hidden area. Applies immediately.
    func setHidden(_ hidden: Bool, for bundle: String) {
        guard !bundle.isEmpty, bundle != Self.ownBundleID else { return }
        if hidden {
            hiddenBundles.insert(bundle)
        } else {
            hiddenBundles.remove(bundle)
        }
        persist()
        // With nothing selected there is no reason to keep holding a restriction.
        hiddenBundles.isEmpty ? restore() : collapse()
        onStateChange?()
    }

    private func persist() {
        UserDefaults.standard.set(Array(hiddenBundles).sorted(), forKey: Keys.hidden)
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

    /// Applies the saved selection at launch, if the user asked for that.
    func prepareOnLaunch() {
        guard collapsesOnLaunch, !hiddenBundles.isEmpty else { return }
        collapse()
    }

    /// Always restores before quitting — the menu bar is never left restricted.
    func shutdown() {
        rehideWorkItem?.cancel()
        resyncWorkItem?.cancel()
        restore()
    }

    // MARK: - Configuration

    /// Computes the allow-list to submit. Nil means "no restriction, show everything".
    private func desiredConfiguration() -> Configuration? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let hidden = hiddenBundles.intersection(running)
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
