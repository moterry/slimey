import Foundation

/// Adds/removes Slimey's entries in Claude Code's `~/.claude/settings.json` without touching anything else.
enum HookConfig {
    /// Every Slimey hook command contains this, which is how we recognise our own entries.
    static let marker = "/.slimey/hook.sh"

    static let hooks: [(event: String, matcher: String?, state: String)] = [
        ("UserPromptSubmit", nil, "running"),
        ("PostToolUse", nil, "running"),
        ("PostToolUseFailure", nil, "running"),
        ("PreToolUse", "AskUserQuestion", "waiting"),
        ("Notification", "permission_prompt|elicitation_dialog", "waiting"),
        ("Stop", nil, "done"),
        ("SessionEnd", nil, "end"),
    ]

    static func command(for state: String) -> String {
        "\"$HOME\(marker)\" \(state) 2>/dev/null || true"
    }

    static func isInstalled(in settings: [String: Any]) -> Bool {
        let events = settings["hooks"] as? [String: Any] ?? [:]
        return hooks.allSatisfy { hook in
            groups(events[hook.event]).contains { group in
                commands(in: group).contains(command(for: hook.state))
            }
        }
    }

    /// Returns `settings` with Slimey's hooks present exactly once (re-installing is a no-op).
    static func installing(into settings: [String: Any]) -> [String: Any] {
        var result = removing(from: settings)
        var events = result["hooks"] as? [String: Any] ?? [:]
        for hook in hooks {
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command(for: hook.state), "timeout": 5]],
            ]
            if let matcher = hook.matcher { group["matcher"] = matcher }
            events[hook.event] = groups(events[hook.event]) + [group]
        }
        result["hooks"] = events
        return result
    }

    /// Returns `settings` with every Slimey hook removed; other hooks are kept as they were.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var events = settings["hooks"] as? [String: Any] else { return result }
        for (event, value) in events {
            guard let list = value as? [Any] else { continue }
            let kept: [Any] = list.compactMap { item in
                guard var group = item as? [String: Any], let entries = group["hooks"] as? [Any] else { return item }
                let others = entries.filter { entry in
                    !((entry as? [String: Any])?["command"] as? String ?? "").contains(marker)
                }
                if others.isEmpty { return nil }
                group["hooks"] = others
                return group
            }
            if kept.isEmpty { events.removeValue(forKey: event) } else { events[event] = kept }
        }
        if events.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = events }
        return result
    }

    private static func groups(_ value: Any?) -> [[String: Any]] {
        (value as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    }

    private static func commands(in group: [String: Any]) -> [String] {
        (group["hooks"] as? [Any] ?? []).compactMap { ($0 as? [String: Any])?["command"] as? String }
    }
}
