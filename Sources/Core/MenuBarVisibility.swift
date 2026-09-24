import AppKit
import ObjectiveC

/// Runtime bridge to the macOS 27 private framework `MenuBarClientCore`.
///
/// The framework was written for assessment/exam lockdown and exposes an
/// **allow-list** style restriction on menu bar visibility: hand it the system item
/// IDs and apps that may stay visible, and it hides everything else and re-lays out
/// the menu bar itself. The system restores the menu bar when the process exits or
/// when the assertion is invalidated, so a one-shot assertion is enough and no
/// background agent is required.
///
/// This is the only way to actually hide *other* apps' menu bar icons on macOS 27.
/// The older trick of stretching a separator until it pushes icons off screen is
/// dead: an over-wide separator is dropped from the layout and the menu bar simply
/// grows rightward instead, bringing the icons back.
///
/// Every symbol is resolved at run time through dlopen/dlsym, so a missing framework
/// or a changed interface degrades to "unavailable" rather than failing to launch.
final class MenuBarVisibility {

    static let frameworkPath =
        "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"

    /// System item IDs that may stay visible.
    ///
    /// **Only the numbers 0...8 are valid** (battery, Bluetooth, clock, display,
    /// keyboard, sound, Wi-Fi, screen mirroring, Control Center). Passing a wider
    /// range — 0..<64, say — does not "keep a few more"; the system treats the
    /// configuration as containing invalid IDs and **silently ignores the whole
    /// request**: the call reports success and an assertion is created, but the menu
    /// bar does not change at all. An empty array, on the other hand, takes the
    /// clock and battery down with everything else.
    static let systemItemIDs: [Int] = Array(0...8)

    /// Human-readable name for each system item ID.
    static let systemItemNames = [
        "Battery", "Bluetooth", "Clock", "Display", "Keyboard",
        "Sound", "Wi-Fi", "Screen Mirroring", "Control Center",
    ]

    private static let configurationClass = "MBAssessmentModeConfiguration"
    private static let assertionClass = "MBAssessmentModeAssertion"

    private let initSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private let invalidateSelector = NSSelectorFromString("invalidate")
    private let allocSelector = NSSelectorFromString("alloc")
    private let initPlainSelector = NSSelectorFromString("init")

    private var msgSend: UnsafeMutableRawPointer?

    /// Whether the system offers the capability at all. Independent of permissions —
    /// this is pure capability detection.
    private(set) var isAvailable = false
    private(set) var unavailableReason: String?

    /// Upper bound on how long to wait for the activation callback. If it never
    /// arrives we report failure instead of waiting forever.
    private let activationTimeout: TimeInterval = 5

    init() {
        prepare()
    }

    // MARK: - Capability detection

    private func prepare() {
        guard dlopen(Self.frameworkPath, RTLD_NOW | RTLD_LOCAL) != nil else {
            unavailableReason = L("reason.noFramework")
            return
        }
        guard let libobjc = dlopen("/usr/lib/libobjc.A.dylib", RTLD_NOW),
              let send = dlsym(libobjc, "objc_msgSend") else {
            unavailableReason = L("reason.noObjectiveC")
            return
        }
        msgSend = send

        guard let configuration = NSClassFromString(Self.configurationClass),
              let assertion = NSClassFromString(Self.assertionClass) else {
            unavailableReason = L("reason.missingClasses")
            return
        }
        guard configuration.instancesRespond(to: initSelector),
              assertion.instancesRespond(to: activateSelector),
              assertion.instancesRespond(to: invalidateSelector) else {
            unavailableReason = L("reason.interfaceChanged")
            return
        }
        isAvailable = true
    }

    // MARK: - Activation

    /// Restricts the menu bar to the given allow-list.
    ///
    /// The return value is the assertion object holding the restriction; the caller
    /// must keep it and hand it back to `invalidate` when restoring. Returning nil
    /// means the request was never sent (capability missing or the configuration
    /// could not be built); the completion handler is then called synchronously with
    /// a failure.
    @discardableResult
    func activate(allowedSystemItems: [Int],
                  allowedBundleIdentifiers: [String],
                  completionHandler: @escaping (Result<AnyObject, MenuBarVisibilityError>) -> Void) -> AnyObject? {
        guard isAvailable, let msgSend else {
            completionHandler(.failure(.unavailable(unavailableReason ?? L("reason.noFramework"))))
            return nil
        }
        guard let configurationClass = NSClassFromString(Self.configurationClass),
              let assertionClass = NSClassFromString(Self.assertionClass) else {
            completionHandler(.failure(.unavailable(L("reason.missingClasses"))))
            return nil
        }

        typealias AllocFn = @convention(c) (AnyObject, Selector) -> AnyObject
        typealias InitPlainFn = @convention(c) (AnyObject, Selector) -> AnyObject
        typealias InitFn = @convention(c) (AnyObject, Selector, NSArray, NSArray) -> AnyObject?
        // The block parameter has to be declared as AnyObject. Written as
        // @convention(block) Swift treats it as a non-escaping argument, while the
        // framework keeps it asynchronously — which traps with "closure argument
        // passed as @noescape ... has escaped".
        typealias ActivateFn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> Void
        typealias CompletionBlock = @convention(block) (NSError?) -> Void

        let allocFn = unsafeBitCast(msgSend, to: AllocFn.self)
        let initPlainFn = unsafeBitCast(msgSend, to: InitPlainFn.self)
        let initFn = unsafeBitCast(msgSend, to: InitFn.self)
        let activateFn = unsafeBitCast(msgSend, to: ActivateFn.self)

        // Both arguments must be NSArray: the framework reads them by index.
        let systemItems = allowedSystemItems.map { NSNumber(value: $0) } as NSArray
        let bundles = allowedBundleIdentifiers as NSArray

        let uninitializedConfiguration = allocFn(configurationClass, allocSelector)
        guard let configuration = initFn(uninitializedConfiguration, initSelector, systemItems, bundles) else {
            completionHandler(.failure(.unavailable(L("reason.cannotCreateConfiguration"))))
            return nil
        }

        let assertion = allocFn(assertionClass, allocSelector)
        _ = initPlainFn(assertion, initPlainSelector)

        // Timeout guard: settle exactly once, whichever arrives first.
        var settled = false
        let settle: (Result<AnyObject, MenuBarVisibilityError>) -> Void = { result in
            guard !settled else { return }
            settled = true
            completionHandler(result)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + activationTimeout) {
            settle(.failure(.activationTimedOut))
        }

        let completion: CompletionBlock = { error in
            DispatchQueue.main.async {
                if let error {
                    settle(.failure(.activationFailed(error.localizedDescription)))
                } else {
                    settle(.success(assertion))
                }
            }
        }
        activateFn(assertion, activateSelector, configuration, unsafeBitCast(completion, to: AnyObject.self))
        return assertion
    }

    /// Drops the restriction so every icon is visible again.
    func invalidate(_ assertion: AnyObject) {
        guard let msgSend else { return }
        typealias InvalidateFn = @convention(c) (AnyObject, Selector) -> Void
        unsafeBitCast(msgSend, to: InvalidateFn.self)(assertion, invalidateSelector)
    }
}

enum MenuBarVisibilityError: LocalizedError {
    case unavailable(String)
    case activationFailed(String)
    case activationTimedOut

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return L("error.mechanism.unavailable", reason)
        case .activationFailed(let reason):
            return L("error.mechanism.rejected", reason)
        case .activationTimedOut:
            return L("error.mechanism.timeout")
        }
    }
}
