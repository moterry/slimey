import Foundation

/// What a Claude Code session is doing, as last reported by its hooks.
enum TaskState: String, Equatable {
    case running, waiting, done

    /// Parses the one-word state file the hook script writes.
    init?(fileContents: String) {
        self.init(rawValue: fileContents.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct TaskEntry: Equatable {
    var state: TaskState
    var updatedAt: Date
}

/// The lamp on the slime's antenna.
enum TaskLamp: Equatable {
    case none, running, waiting, done
}

struct TaskSummary: Equatable {
    var running: Int
    var waiting: Int
    var done: Int

    /// Waiting needs the user, so it wins; a finished task only shows once nothing is active.
    var lamp: TaskLamp {
        if waiting > 0 { return .waiting }
        if running > 0 { return .running }
        return done > 0 ? .done : .none
    }

    var text: String {
        var parts: [String] = []
        if running > 0 { parts.append(L10n.t("\(running) running", "\(running) 个在跑")) }
        if waiting > 0 { parts.append(L10n.t("\(waiting) waiting on you", "\(waiting) 个等你")) }
        if done > 0 { parts.append(L10n.t("\(done) done", "\(done) 个完成")) }
        return parts.isEmpty ? L10n.t("No tasks", "没有任务") : parts.joined(separator: " · ")
    }
}

enum TaskStatus {
    /// A running/waiting session that hasn't fired a hook for this long probably crashed.
    static let activeTimeout: TimeInterval = 60 * 60
    /// Unacknowledged "done" lamps eventually go out on their own.
    static let doneTimeout: TimeInterval = 12 * 60 * 60

    static func summarize(_ entries: [TaskEntry], now: Date) -> TaskSummary {
        var summary = TaskSummary(running: 0, waiting: 0, done: 0)
        for entry in entries {
            let age = now.timeIntervalSince(entry.updatedAt)
            switch entry.state {
            case .running where age <= activeTimeout: summary.running += 1
            case .waiting where age <= activeTimeout: summary.waiting += 1
            case .done where age <= doneTimeout: summary.done += 1
            default: break
            }
        }
        return summary
    }
}

/// What the Claude desktop app knows about whether the user has looked at a session.
struct SessionFocus: Equatable {
    /// When the user last switched to this session in the desktop app.
    var lastFocusedAt: Date?
    /// The desktop app is frontmost and this is the session it is showing.
    var isOnScreenNow: Bool
}

/// The slice of the desktop app's per-session metadata file that we read.
struct DesktopSessionRecord: Equatable {
    var cliSessionId: String
    var lastFocusedAt: Date?

    static func parse(_ data: Data) -> DesktopSessionRecord? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = root["cliSessionId"] as? String else { return nil }
        let focused = (root["lastFocusedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return DesktopSessionRecord(cliSessionId: id, lastFocusedAt: focused)
    }
}

extension TaskStatus {
    /// A finished session counts as seen only if the user opened it after it finished,
    /// or is looking at it right now. Clicking the slime is deliberately not enough.
    static func isDoneSeen(doneAt: Date, focus: SessionFocus?) -> Bool {
        guard let focus else { return false }
        if focus.isOnScreenNow { return true }
        guard let focused = focus.lastFocusedAt else { return false }
        return focused > doneAt
    }
}
