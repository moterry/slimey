import Foundation

/// Installs Slimey's Claude Code hooks: copies the hook script to ~/.slimey/hook.sh and merges
/// entries into ~/.claude/settings.json (backing the original up first).
enum HookInstaller {
    enum Failure: Error {
        case unreadableSettings
        case missingScript
    }

    private static let fm = FileManager.default
    private static var home: URL { fm.homeDirectoryForCurrentUser }
    static var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    static var scriptURL: URL { home.appendingPathComponent(".slimey/hook.sh") }

    static var isInstalled: Bool {
        guard fm.isExecutableFile(atPath: scriptURL.path), let settings = try? readSettings() else { return false }
        return HookConfig.isInstalled(in: settings)
    }

    static func install() throws {
        guard let bundled = Bundle.main.url(forResource: "hook", withExtension: "sh") else { throw Failure.missingScript }
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: scriptURL.path) { try fm.removeItem(at: scriptURL) }
        try fm.copyItem(at: bundled, to: scriptURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try writeSettings(HookConfig.installing(into: try readSettings()))
    }

    static func uninstall() throws {
        try writeSettings(HookConfig.removing(from: try readSettings()))
        try? fm.removeItem(at: home.appendingPathComponent(".slimey/sessions"))
    }

    /// A missing file is an empty config; a file that isn't a JSON object is left alone.
    private static func readSettings() throws -> [String: Any] {
        guard fm.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadableSettings
        }
        return object
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("slimey-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
