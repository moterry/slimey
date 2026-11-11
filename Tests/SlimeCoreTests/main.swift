import Foundation

// Minimal test harness: XCTest/swift-testing aren't available with Command Line Tools only.
var failures = 0
var passes = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", line: Int = #line) {
    check(actual == expected, "\(message) expected \(expected), got \(actual)", line: line)
}

L10n.lang = .zh
let utc = TimeZone(identifier: "UTC")!
let shanghai = TimeZone(identifier: "Asia/Shanghai")!

// MARK: parseUsage

do {
    let json = """
    {"five_hour":{"utilization":53.0,"resets_at":"2026-09-27T19:40:00.903Z"},
     "seven_day":{"utilization":9.6,"resets_at":"2026-10-01T21:00:00.123456+00:00"},
     "seven_day_opus":null}
    """.data(using: .utf8)!
    let (session, weekly) = try UsageParser.parseUsage(json)
    checkEqual(session?.percent, 53, "session percent")
    checkEqual(weekly?.percent, 10, "weekly percent rounds")
    checkEqual(session?.resetsAt.map { Int(($0.timeIntervalSince1970 * 1000).rounded()) }, 1_790_538_000_903, "session reset (Z + millis)")
    checkEqual(weekly?.resetsAt.map { Int($0.timeIntervalSince1970) }, 1_790_888_400, "weekly reset (+00:00 + micros)")
} catch {
    check(false, "parseUsage threw \(error)")
}

do {
    let json = #"{"five_hour":null,"seven_day":{"utilization":0,"resets_at":null}}"#.data(using: .utf8)!
    let (session, weekly) = try UsageParser.parseUsage(json)
    check(session == nil, "null five_hour -> nil session")
    checkEqual(weekly?.percent, 0, "weekly zero")
    check(weekly?.resetsAt == nil, "null resets_at -> nil")
} catch {
    check(false, "parseUsage threw on nulls \(error)")
}

do {
    let json = #"{"five_hour":{"utilization":130,"resets_at":null}}"#.data(using: .utf8)!
    let (session, _) = try UsageParser.parseUsage(json)
    checkEqual(session?.percent, 100, "clamped to 100")
} catch {
    check(false, "parseUsage threw on overflow \(error)")
}

do {
    _ = try UsageParser.parseUsage("<html>".data(using: .utf8)!)
    check(false, "garbage should throw")
} catch {
    passes += 1
}

// MARK: parseFreeReset (the "Reset for free" card lives under `cedar_ember`)

func freeResetJSON(_ cedar: String) -> Data {
    #"{"five_hour":{"utilization":66.0,"resets_at":null},"cedar_ember":\#(cedar)}"#.data(using: .utf8)!
}

do {
    let json = freeResetJSON("""
    {"eligible":true,"at_limit":false,"cooldown_until":null,"grants":[
      {"id":"opus55","resets_total":1,"resets_left":1,"ends_at":"2026-10-22T16:00:00+00:00","paused":false,"usable_now":true}]}
    """)
    let reset = UsageParser.parseFreeReset(json)
    checkEqual(reset?.available, true, "grant usable now")
    checkEqual(reset?.count, 1, "resets_left")
    checkEqual(reset.flatMap { $0.expiresAt }.map { LabelFormatter.shortDate($0, timeZone: shanghai) }, "10月23日", "expiry in Shanghai")
}

do {
    let json = freeResetJSON("""
    {"eligible":true,"grants":[
      {"resets_left":2,"ends_at":"2026-11-30T00:00:00+00:00","paused":false,"usable_now":true},
      {"resets_left":1,"ends_at":"2026-10-10T00:00:00+00:00","paused":false,"usable_now":false},
      {"resets_left":0,"ends_at":"2026-10-01T00:00:00+00:00","paused":false,"usable_now":false},
      {"resets_left":5,"ends_at":"2026-10-05T00:00:00+00:00","paused":true,"usable_now":false}]}
    """)
    let reset = UsageParser.parseFreeReset(json)
    checkEqual(reset?.count, 3, "sums resets_left of unpaused grants")
    checkEqual(reset?.available, true, "any unpaused grant usable now")
    checkEqual(reset.flatMap { $0.expiresAt }.map { Int($0.timeIntervalSince1970) },
               Int(UsageParser.parseDate("2026-10-10T00:00:00+00:00")!.timeIntervalSince1970),
               "earliest expiry among grants with resets left")
}

do {
    let reset = UsageParser.parseFreeReset(freeResetJSON(#"{"eligible":true,"grants":[{"resets_left":0,"usable_now":false,"paused":false}]}"#))
    checkEqual(reset, FreeReset(available: false, count: 0, expiresAt: nil), "all used up")
}

checkEqual(UsageParser.parseFreeReset(freeResetJSON(#"{"eligible":false,"grants":[]}"#)),
           FreeReset(available: false, count: 0, expiresAt: nil), "ineligible")
check(UsageParser.parseFreeReset(freeResetJSON("null")) == nil, "no cedar_ember -> unknown")
check(UsageParser.parseFreeReset("oops".data(using: .utf8)!) == nil, "garbage -> unknown")

// MARK: Mood

checkEqual(Mood(percent: 0), .calm)
checkEqual(Mood(percent: 49), .calm)
checkEqual(Mood(percent: 50), .busy)
checkEqual(Mood(percent: 79), .busy)
checkEqual(Mood(percent: 80), .stressed)
checkEqual(Mood(percent: 99), .stressed)
checkEqual(Mood(percent: 100), .melted)

// MARK: LabelFormatter

let reset = ISO8601DateFormatter().date(from: "2026-09-27T19:40:00Z")!
let snap = UsageSnapshot(
    session: UsageWindow(percent: 53, resetsAt: reset),
    weekly: UsageWindow(percent: 10, resetsAt: nil),
    freeReset: nil,
    fetchedAt: reset
)
checkEqual(LabelFormatter.label(for: snap, timeZone: shanghai), "53% · 03:40", "label in Shanghai")
checkEqual(LabelFormatter.label(for: snap, timeZone: utc), "53% · 19:40", "label in UTC")
checkEqual(LabelFormatter.label(for: nil, timeZone: utc), "?", "no data")
let noReset = UsageSnapshot(session: UsageWindow(percent: 0, resetsAt: nil), weekly: nil, freeReset: nil, fetchedAt: reset)
checkEqual(LabelFormatter.label(for: noReset, timeZone: utc), "0%", "no reset time")
checkEqual(LabelFormatter.fullDate(reset, timeZone: shanghai), "9月28日 周一 03:40", "full date")
checkEqual(LabelFormatter.shortDate(reset, timeZone: shanghai), "9月28日", "short date")
checkEqual(LabelFormatter.fullDate(reset, timeZone: shanghai, lang: .en), "Mon, Sep 28 03:40", "full date (en)")
checkEqual(LabelFormatter.shortDate(reset, timeZone: shanghai, lang: .en), "Sep 28", "short date (en)")

// MARK: TaskStatus (Claude Code session lamp)

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func entry(_ state: TaskState, minutesAgo: Double) -> TaskEntry {
    TaskEntry(state: state, updatedAt: t0.addingTimeInterval(-minutesAgo * 60))
}

checkEqual(TaskStatus.summarize([], now: t0), TaskSummary(running: 0, waiting: 0, done: 0), "no sessions")
checkEqual(TaskStatus.summarize([], now: t0).lamp, .none, "no sessions -> no lamp")
checkEqual(TaskStatus.summarize([entry(.done, minutesAgo: 1)], now: t0).lamp, .done, "finished -> green")
checkEqual(TaskStatus.summarize([entry(.done, minutesAgo: 1), entry(.running, minutesAgo: 0)], now: t0).lamp, .running,
           "running beats done")
checkEqual(TaskStatus.summarize([entry(.running, minutesAgo: 0), entry(.waiting, minutesAgo: 2)], now: t0).lamp, .waiting,
           "waiting for the user beats running")
checkEqual(TaskStatus.summarize([entry(.running, minutesAgo: 1), entry(.running, minutesAgo: 5), entry(.done, minutesAgo: 9)], now: t0),
           TaskSummary(running: 2, waiting: 0, done: 1), "counts")
checkEqual(TaskStatus.summarize([entry(.running, minutesAgo: 61), entry(.waiting, minutesAgo: 90)], now: t0).lamp, .none,
           "sessions silent for over an hour are treated as dead")
checkEqual(TaskStatus.summarize([entry(.done, minutesAgo: 11 * 60)], now: t0).lamp, .done, "done lingers until acknowledged")
checkEqual(TaskStatus.summarize([entry(.done, minutesAgo: 13 * 60)], now: t0).lamp, .none, "but not forever")
checkEqual(TaskState(fileContents: "running\n"), .running, "parses hook file")
check(TaskState(fileContents: "garbage") == nil, "unknown state ignored")
checkEqual(TaskSummary(running: 2, waiting: 1, done: 1).text, "2 个在跑 · 1 个等你 · 1 个完成", "summary text")
checkEqual(TaskSummary(running: 0, waiting: 0, done: 0).text, "没有任务", "empty summary text")
L10n.lang = .en
checkEqual(TaskSummary(running: 2, waiting: 1, done: 1).text, "2 running · 1 waiting on you · 1 done", "summary text (en)")
checkEqual(TaskSummary(running: 0, waiting: 0, done: 0).text, "No tasks", "empty summary text (en)")
L10n.lang = .zh

// MARK: "done" is only cleared by actually opening that session

let doneAt = t0
check(!TaskStatus.isDoneSeen(doneAt: doneAt, focus: SessionFocus(lastFocusedAt: t0.addingTimeInterval(-300), isOnScreenNow: false)),
      "focused before it finished, now elsewhere -> still unread")
check(TaskStatus.isDoneSeen(doneAt: doneAt, focus: SessionFocus(lastFocusedAt: t0.addingTimeInterval(5), isOnScreenNow: false)),
      "opened after it finished -> read")
check(TaskStatus.isDoneSeen(doneAt: doneAt, focus: SessionFocus(lastFocusedAt: t0.addingTimeInterval(-300), isOnScreenNow: true)),
      "finished while the user is looking at it -> read")
check(!TaskStatus.isDoneSeen(doneAt: doneAt, focus: SessionFocus(lastFocusedAt: nil, isOnScreenNow: false)),
      "never focused -> unread")
check(!TaskStatus.isDoneSeen(doneAt: doneAt, focus: nil), "no desktop record (terminal session) -> unread")

do {
    let json = #"{"sessionId":"local_x","cliSessionId":"abc-123","lastFocusedAt":1800000005000,"isArchived":false}"#.data(using: .utf8)!
    let record = DesktopSessionRecord.parse(json)
    checkEqual(record?.cliSessionId, "abc-123", "desktop record id")
    checkEqual(record?.lastFocusedAt, t0.addingTimeInterval(5), "desktop record focus time (ms epoch)")
    check(DesktopSessionRecord.parse(#"{"cliSessionId":"abc"}"#.data(using: .utf8)!)?.lastFocusedAt == nil, "missing focus time")
    check(DesktopSessionRecord.parse("nope".data(using: .utf8)!) == nil, "garbage record")
}

// MARK: HookConfig (merging into ~/.claude/settings.json)

do {
    let theirs: [String: Any] = [
        "theme": "dark",
        "hooks": ["PostToolUse": [["matcher": "Write|Edit", "hooks": [["type": "command", "command": "prettier --write"]]]]],
    ]
    check(!HookConfig.isInstalled(in: theirs), "not installed initially")
    let installed = HookConfig.installing(into: theirs)
    check(HookConfig.isInstalled(in: installed), "installed after merge")
    checkEqual(installed["theme"] as? String, "dark", "unrelated settings kept")
    let post = (installed["hooks"] as? [String: Any])?["PostToolUse"] as? [[String: Any]] ?? []
    checkEqual(post.count, 2, "user's own PostToolUse hook kept alongside ours")
    checkEqual(post.first?["matcher"] as? String, "Write|Edit", "user's hook stays first")

    let twice = HookConfig.installing(into: installed)
    checkEqual(((twice["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count, 1, "re-install does not duplicate")

    let removed = HookConfig.removing(from: twice)
    check(!HookConfig.isInstalled(in: removed), "uninstalled")
    let left = removed["hooks"] as? [String: Any] ?? [:]
    checkEqual(Array(left.keys), ["PostToolUse"], "only the user's own event remains")
    checkEqual(((left["PostToolUse"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String,
               "prettier --write", "user's hook untouched")
    check(HookConfig.removing(from: HookConfig.installing(into: [:]))["hooks"] == nil, "empty hooks key dropped")
}

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
