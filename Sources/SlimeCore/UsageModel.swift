import Foundation

struct UsageWindow: Equatable {
    var percent: Int
    var resetsAt: Date?
}

struct FreeReset: Equatable {
    var available: Bool
    var count: Int?
    var expiresAt: Date?
}

struct UsageSnapshot: Equatable {
    var session: UsageWindow?
    var weekly: UsageWindow?
    var freeReset: FreeReset?
    var fetchedAt: Date
}

enum Mood: Equatable {
    case calm, busy, stressed, melted

    init(percent: Int) {
        switch percent {
        case ..<50: self = .calm
        case ..<80: self = .busy
        case ..<100: self = .stressed
        default: self = .melted
        }
    }
}

enum UsageParseError: Error {
    case notJSON
}

enum UsageParser {
    /// Parses claude.ai's `/api/organizations/{id}/usage` response.
    static func parseUsage(_ data: Data) throws -> (session: UsageWindow?, weekly: UsageWindow?) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageParseError.notJSON
        }
        return (window(root["five_hour"]), window(root["seven_day"]))
    }

    /// The "Reset for free" card, read from the usage response's `cedar_ember` object
    /// (requested with `?cedar_ember=1`). Returns nil when the response carries no reset info.
    static func parseFreeReset(_ data: Data) -> FreeReset? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cedar = root["cedar_ember"] as? [String: Any] else { return nil }
        guard cedar["eligible"] as? Bool == true else {
            return FreeReset(available: false, count: 0, expiresAt: nil)
        }
        let grants = (cedar["grants"] as? [[String: Any]] ?? [])
            .filter { $0["paused"] as? Bool != true }
            .filter { (($0["resets_left"] as? NSNumber)?.intValue ?? 0) > 0 }
        let count = grants.reduce(0) { $0 + (($1["resets_left"] as? NSNumber)?.intValue ?? 0) }
        let usable = grants.contains { $0["usable_now"] as? Bool == true }
        let expiresAt = grants.compactMap { parseDate($0["ends_at"] as? String) }.min()
        return FreeReset(available: usable, count: count, expiresAt: expiresAt)
    }

    private static func window(_ value: Any?) -> UsageWindow? {
        guard let dict = value as? [String: Any],
              let utilization = (dict["utilization"] as? NSNumber)?.doubleValue else { return nil }
        let percent = min(100, max(0, Int(utilization.rounded())))
        return UsageWindow(percent: percent, resetsAt: parseDate(dict["resets_at"] as? String))
    }

    /// Accepts ISO 8601 with or without fractional seconds, including microsecond precision.
    static func parseDate(_ string: String?) -> Date? {
        guard var s = string else { return nil }
        // ISO8601DateFormatter only handles up to millisecond fractions; trim longer ones.
        if let dot = s.firstIndex(of: ".") {
            let fracStart = s.index(after: dot)
            let fracEnd = s[fracStart...].firstIndex(where: { !$0.isNumber }) ?? s.endIndex
            if s.distance(from: fracStart, to: fracEnd) > 3 {
                s.removeSubrange(s.index(fracStart, offsetBy: 3)..<fracEnd)
            }
        }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

enum LabelFormatter {
    /// Text shown above the slime, e.g. "53% · 03:40".
    static func label(for snapshot: UsageSnapshot?, timeZone: TimeZone = .current) -> String {
        guard let session = snapshot?.session else { return "?" }
        guard let reset = session.resetsAt else { return "\(session.percent)%" }
        return "\(session.percent)% · \(format(reset, "HH:mm", timeZone))"
    }

    /// Full reset time for the detail panel, e.g. "Mon, Sep 28 03:40" / "9月28日 周一 03:40".
    static func fullDate(_ date: Date, timeZone: TimeZone = .current, lang: Lang = L10n.lang) -> String {
        format(date, lang == .zh ? "M月d日 EEE HH:mm" : "EEE, MMM d HH:mm", timeZone, lang)
    }

    /// Day only, e.g. "Oct 23" / "10月23日" for the free-reset expiry.
    static func shortDate(_ date: Date, timeZone: TimeZone = .current, lang: Lang = L10n.lang) -> String {
        format(date, lang == .zh ? "M月d日" : "MMM d", timeZone, lang)
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone, _ lang: Lang = .en) -> String {
        let f = DateFormatter()
        f.locale = lang.locale
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }
}
