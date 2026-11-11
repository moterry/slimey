import AppKit
import ServiceManagement

/// Wires the fetcher's state into the slime and the detail panel.
final class AppController: NSObject, NSApplicationDelegate {
    private let pet = PetWindow()
    private let panel = DetailPanel()
    private let fetcher = UsageFetcher()
    private let tasks = TaskWatcher()
    private var needsLogin = false
    private var promptedLogin = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        pet.slime.onClick = { [weak self] in self?.clicked() }
        pet.slime.menuProvider = { [weak self] in self?.makeMenu() }
        pet.orderFrontRegardless()

        tasks.onChange = { [weak self] summary in
            self?.pet.slime.lamp = summary.lamp
            self?.panel.content.tasks = summary
        }
        tasks.start()
        pet.slime.lamp = tasks.summary.lamp
        panel.content.tasks = tasks.summary

        if let demo = DemoMode.fromArguments() {
            apply(.ok(demo))
            return
        }
        fetcher.onUpdate = { [weak self] state in self?.apply(state) }
        fetcher.start()
    }

    private func apply(_ state: FetchState) {
        let slime = pet.slime
        needsLogin = false
        switch state {
        case .loading:
            slime.mood = nil
            slime.label = "-"
            setPanel(nil, L10n.t("Loading claude.ai…", "正在读取 claude.ai…"))
        case .ok(let snapshot):
            show(snapshot, dimmed: false)
            setPanel(snapshot, nil)
        case .needsLogin(let last):
            needsLogin = true
            if !promptedLogin {
                promptedLogin = true
                fetcher.showLogin()
            }
            slime.mood = nil
            slime.label = "?"
            slime.showHourglass = false
            setPanel(last, L10n.t("Not signed in to claude.ai. Click Slimey to sign in.", "还没登录 claude.ai，点史莱姆登录"))
        case .failed(let message, let last):
            if let last { show(last, dimmed: true) } else { slime.mood = nil; slime.label = "?" }
            setPanel(last, message)
        }
    }

    private func setPanel(_ snapshot: UsageSnapshot?, _ problem: String?) {
        panel.content = DetailContent(snapshot: snapshot, problem: problem, tasks: tasks.summary,
                                      hooksInstalled: HookInstaller.isInstalled)
    }

    private func show(_ snapshot: UsageSnapshot, dimmed: Bool) {
        let slime = pet.slime
        // Mood follows whichever limit is closer to blocking you.
        let worst = max(snapshot.session?.percent ?? 0, snapshot.weekly?.percent ?? 0)
        slime.mood = Mood(percent: worst)
        slime.label = LabelFormatter.label(for: snapshot)
        slime.labelDimmed = dimmed
        slime.showHourglass = snapshot.freeReset?.available == true
    }

    private func clicked() {
        // Desktop sessions clear their green lamp only when opened; this covers terminal ones.
        if tasks.summary.done > 0 { tasks.acknowledgeUntrackedDone() }
        if needsLogin {
            fetcher.showLogin()
        } else {
            panel.content.hooksInstalled = HookInstaller.isInstalled
            panel.toggle(near: pet.frame)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.t("Refresh now", "立即刷新"), action: #selector(refreshNow), keyEquivalent: "").target = self
        menu.addItem(withTitle: L10n.t("Sign in again", "重新登录"), action: #selector(relogin), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let hooks = menu.addItem(withTitle: L10n.t("Claude Code task light (installs hooks)", "Claude Code 任务灯（安装 hooks）"),
                                 action: #selector(toggleHooks), keyEquivalent: "")
        hooks.target = self
        hooks.state = HookInstaller.isInstalled ? .on : .off
        let startup = menu.addItem(withTitle: L10n.t("Launch at login", "开机自动启动"), action: #selector(toggleLoginItem), keyEquivalent: "")
        startup.target = self
        switch LoginItem.status {
        case .enabled: startup.state = .on
        case .requiresApproval:
            startup.state = .mixed
            startup.title = L10n.t("Launch at login (allow it in System Settings → Login Items)",
                                   "开机自动启动（需在系统设置→登录项里允许）")
        default: startup.state = .off
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("Quit Slimey", "退出"), action: #selector(quit), keyEquivalent: "").target = self
        return menu
    }

    @objc private func refreshNow() { fetcher.refresh() }
    @objc private func relogin() { fetcher.showLogin() }
    @objc private func toggleHooks() {
        do {
            if HookInstaller.isInstalled { try HookInstaller.uninstall() } else { try HookInstaller.install() }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.t("Couldn't update ~/.claude/settings.json", "没能修改 ~/.claude/settings.json")
            alert.informativeText = L10n.t("Make sure it is valid JSON, then try again. Nothing was changed.",
                                           "请确认它是有效的 JSON 后再试一次。文件没有被改动。")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        panel.content.hooksInstalled = HookInstaller.isInstalled
    }

    @objc private func toggleLoginItem() {
        if LoginItem.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        } else {
            LoginItem.setEnabled(LoginItem.status != .enabled)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// `--demo <percent> [--free]` shows fake data, for checking the look without signing in.
enum DemoMode {
    static func fromArguments() -> UsageSnapshot? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo") else { return nil }
        let percent = args.indices.contains(i + 1) ? Int(args[i + 1]) ?? 53 : 53
        let now = Date()
        return UsageSnapshot(
            session: UsageWindow(percent: percent, resetsAt: now.addingTimeInterval(4 * 3600)),
            weekly: UsageWindow(percent: 10, resetsAt: now.addingTimeInterval(4 * 86400)),
            freeReset: args.contains("--free")
                ? FreeReset(available: true, count: 1, expiresAt: now.addingTimeInterval(26 * 86400))
                : FreeReset(available: false, count: 0, expiresAt: nil),
            fetchedAt: now
        )
    }
}

/// `--snapshot <dir>` renders every mood and the detail panel to PNGs, then exits (for checking the art).
enum SnapshotMode {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        let cases: [(String, Mood?, String, Bool, TaskLamp)] = [
            ("calm", .calm, "23% · 03:40", false, .done), ("busy", .busy, "53% · 03:40", true, .running),
            ("stressed", .stressed, "88% · 03:40", false, .waiting), ("melted", .melted, "100% · 03:40", false, .running),
            ("unknown", nil, "?", false, .none),
        ]
        for (name, mood, label, hourglass, lamp) in cases {
            let view = SlimeView(frame: NSRect(origin: .zero, size: SlimeView.size))
            view.mood = mood
            view.label = label
            view.showHourglass = hourglass
            view.lamp = lamp
            save(view, to: dir.appendingPathComponent("slime-\(name).png"))
        }
        let panel = DetailPanel()
        panel.content = DetailContent(snapshot: DemoMode.fromArguments() ?? UsageSnapshot(
            session: UsageWindow(percent: 53, resetsAt: Date().addingTimeInterval(4 * 3600)),
            weekly: UsageWindow(percent: 10, resetsAt: Date().addingTimeInterval(4 * 86400)),
            freeReset: FreeReset(available: true, count: 1, expiresAt: Date().addingTimeInterval(26 * 86400)),
            fetchedAt: Date()), problem: nil, tasks: TaskSummary(running: 2, waiting: 0, done: 1))
        if let view = panel.contentView { save(view, to: dir.appendingPathComponent("panel.png")) }
        exit(0)
    }

    private static func save(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

SnapshotMode.runIfRequested()

// `Slimey --install-hooks` / `--uninstall-hooks`: the same as the menu toggle, for the terminal.
for (flag, install) in [("--install-hooks", true), ("--uninstall-hooks", false)] where CommandLine.arguments.contains(flag) {
    do {
        try install ? HookInstaller.install() : HookInstaller.uninstall()
        print(install ? "Slimey hooks installed in \(HookInstaller.settingsURL.path)" : "Slimey hooks removed")
        exit(0)
    } catch {
        print("Failed: \(error). \(HookInstaller.settingsURL.path) was not changed.")
        exit(1)
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
