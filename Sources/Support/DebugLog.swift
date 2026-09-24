import Foundation

/// Debug logging and debug switches.
///
/// Output is written to a file rather than stderr: when the app is started through
/// LaunchServices (`open`), stderr never reaches the calling terminal, so a file is
/// the only way to read it back.
///
/// A switch is considered on when either of these is true:
/// - the environment variable `MBK_<FLAG>=1` is set (useful when running the binary
///   directly), or
/// - the marker file `/tmp/menubarkeeper-<flag>` exists (needed when the app is
///   launched with `open`, because shell environment variables do not cross that
///   boundary).
enum DebugLog {

    static let filePath = "/tmp/menubarkeeper-debug.log"

    private static let markerDirectory = "/tmp"

    static func isEnabled(_ flag: String) -> Bool {
        if ProcessInfo.processInfo.environment["MBK_" + flag.uppercased()] == "1" { return true }
        return FileManager.default.fileExists(atPath: "\(markerDirectory)/menubarkeeper-\(flag)")
    }

    static func write(_ line: String) {
        let url = URL(fileURLWithPath: filePath)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Writes only while `flag` is on, so normal use never creates a stray file.
    static func write(_ line: String, when flag: String) {
        guard isEnabled(flag) else { return }
        write(line)
    }
}
