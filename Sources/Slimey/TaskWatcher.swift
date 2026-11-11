import AppKit

/// Watches the state files written by `hooks/hook.sh` (one per Claude Code session),
/// and clears a finished session once the user has actually opened it in the Claude desktop app.
final class TaskWatcher {
    var onChange: (TaskSummary) -> Void = { _ in }
    private(set) var summary = TaskSummary(running: 0, waiting: 0, done: 0)

    private let directory: URL
    private let desktopSessions: URL
    private var timer: Timer?
    /// Parsed desktop records keyed by file path, reused while the file's mtime is unchanged.
    private var recordCache: [String: (modified: Date, record: DesktopSessionRecord?)] = [:]

    static let desktopBundleID = "com.anthropic.claudefordesktop"

    private struct StateFile {
        var url: URL
        var sessionID: String
        var entry: TaskEntry
    }

    init() {
        let fm = FileManager.default
        let base = ProcessInfo.processInfo.environment["SLIMEY_DIR"].map { URL(fileURLWithPath: $0) }
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".slimey")
        directory = base.appendingPathComponent("sessions")
        desktopSessions = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    func start() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.scan() }
    }

    /// Clicking the slime only clears finished sessions the desktop app doesn't know about
    /// (terminal `claude` sessions), since there is no way to tell whether those were read.
    func acknowledgeUntrackedDone() {
        let known = Set(desktopRecords().map(\.cliSessionId))
        for file in readStateFiles() where file.entry.state == .done && !known.contains(file.sessionID) {
            try? FileManager.default.removeItem(at: file.url)
        }
        scan()
    }

    private func scan() {
        var files = readStateFiles()
        if files.contains(where: { $0.entry.state == .done }) {
            files = removingSeen(files)
        }
        let latest = TaskStatus.summarize(files.map(\.entry), now: Date())
        guard latest != summary else { return }
        summary = latest
        onChange(latest)
    }

    /// Deletes "done" files for sessions the user has opened since they finished.
    private func removingSeen(_ files: [StateFile]) -> [StateFile] {
        let records = desktopRecords()
        let byID = Dictionary(records.map { ($0.cliSessionId, $0) }, uniquingKeysWith: { a, _ in a })
        // The desktop app shows whichever session was focused most recently.
        let showing = records.max { ($0.lastFocusedAt ?? .distantPast) < ($1.lastFocusedAt ?? .distantPast) }?.cliSessionId
        let desktopIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.desktopBundleID

        return files.filter { file in
            guard file.entry.state == .done else { return true }
            let focus = byID[file.sessionID].map {
                SessionFocus(lastFocusedAt: $0.lastFocusedAt,
                             isOnScreenNow: desktopIsFrontmost && file.sessionID == showing)
            }
            guard TaskStatus.isDoneSeen(doneAt: file.entry.updatedAt, focus: focus) else { return true }
            try? FileManager.default.removeItem(at: file.url)
            return false
        }
    }

    private func readStateFiles() -> [StateFile] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []
        return files.compactMap { url in
            guard let contents = try? String(contentsOf: url, encoding: .utf8),
                  let state = TaskState(fileContents: contents),
                  let modified = modificationDate(url) else { return nil }
            return StateFile(url: url, sessionID: url.lastPathComponent, entry: TaskEntry(state: state, updatedAt: modified))
        }
    }

    /// Reads `claude-code-sessions/<account>/<org>/local_*.json`, the desktop app's per-session metadata.
    private func desktopRecords() -> [DesktopSessionRecord] {
        let fm = FileManager.default
        var paths: [URL] = []
        for account in (try? fm.contentsOfDirectory(at: desktopSessions, includingPropertiesForKeys: nil)) ?? [] {
            for org in (try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [] {
                let files = (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                paths += files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("local_") }
            }
        }
        var fresh: [String: (modified: Date, record: DesktopSessionRecord?)] = [:]
        for url in paths {
            guard let modified = modificationDate(url) else { continue }
            if let cached = recordCache[url.path], cached.modified == modified {
                fresh[url.path] = cached
            } else {
                fresh[url.path] = (modified, (try? Data(contentsOf: url)).flatMap(DesktopSessionRecord.parse))
            }
        }
        recordCache = fresh
        return fresh.values.compactMap(\.record)
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
