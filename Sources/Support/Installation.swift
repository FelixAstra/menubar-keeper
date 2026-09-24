import AppKit

/// Where the app is installed from, and how to fix it when that matters.
///
/// **Measurement (macOS 27):** when the system applies the menu bar visibility
/// allow-list, it only protects the status items of apps installed in a standard
/// location. Run MenuBarKeeper straight from `~/Desktop/...` and its own icon is
/// swept away with everything else, leaving the user with no way to control the
/// app. Copying it to `/Applications` keeps the icon.
///
/// So this is not tidiness — running from `/Applications` is a functional
/// requirement, and the checks that enforce it live here.
enum Installation {

    static let applicationsDirectory = "/Applications"

    /// Whether the app is running from the Applications folder.
    static var isInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix(applicationsDirectory + "/")
    }

    static var currentPath: String { Bundle.main.bundlePath }

    static var currentName: String { (currentPath as NSString).lastPathComponent }

    /// Copies the app to `/Applications`. Returns nil on success, otherwise a
    /// human-readable reason.
    ///
    /// The original is left alone — when running from a checkout, that directory is
    /// still the source of truth.
    static func copyToApplications() -> String? {
        guard !isInApplications else { return nil }

        let destination = "\(applicationsDirectory)/\(currentName)"
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }
            try fileManager.copyItem(atPath: currentPath, toPath: destination)
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    /// Launches the copy at `path` and quits the current process.
    ///
    /// Permission records follow the code signature, not the path, so moving does
    /// not invalidate an Accessibility grant.
    static func relaunch(at path: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The delay lets the current process exit before the new one starts, so the
        // menu bar icon is handed over cleanly rather than overlapping.
        task.arguments = ["-c", "sleep 1; open \(shellQuoted(path))"]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Wraps a path in single quotes for `/bin/sh`, escaping embedded quotes.
    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
