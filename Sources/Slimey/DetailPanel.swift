import AppKit

/// What the detail panel shows. Built from the fetcher's latest state.
struct DetailContent {
    var snapshot: UsageSnapshot?
    var problem: String?
    var tasks = TaskSummary(running: 0, waiting: 0, done: 0)
    var hooksInstalled = true
}

/// Borderless dark panel with pixel-style progress bars, shown next to the slime.
final class DetailPanel: NSPanel {
    private let body = DetailView(frame: NSRect(origin: .zero, size: DetailView.size))
    private var outsideClickMonitor: Any?

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: DetailView.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = body
    }

    var content: DetailContent {
        get { body.content }
        set { body.content = newValue }
    }

    func toggle(near anchor: NSRect) {
        if isVisible { dismiss() } else { show(near: anchor) }
    }

    func show(near anchor: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchor
        let size = DetailView.size
        // Prefer above the slime; fall back to below. Keep it on screen horizontally.
        var y = anchor.maxY + 6
        if y + size.height > visible.maxY { y = anchor.minY - size.height - 6 }
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        setFrameOrigin(NSPoint(x: x, y: max(y, visible.minY + 8)))
        orderFrontRegardless()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        orderOut(nil)
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
    }
}

private final class DetailView: NSView {
    static let size = NSSize(width: 300, height: 272)

    var content = DetailContent() { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    private let background = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.96)
    private let border = SlimePalette.hex(0x639922)
    private let muted = NSColor(white: 0.62, alpha: 1)
    private let track = NSColor(white: 0.25, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(false)
        let px: CGFloat = 3

        // Pixel frame: outer border with notched corners.
        ctx.setFillColor(border.cgColor)
        ctx.fill(CGRect(x: px, y: 0, width: bounds.width - 2 * px, height: bounds.height))
        ctx.fill(CGRect(x: 0, y: px, width: bounds.width, height: bounds.height - 2 * px))
        ctx.setFillColor(background.cgColor)
        ctx.fill(CGRect(x: 2 * px, y: px, width: bounds.width - 4 * px, height: bounds.height - 2 * px))
        ctx.fill(CGRect(x: px, y: 2 * px, width: bounds.width - 2 * px, height: bounds.height - 4 * px))
        ctx.setShouldAntialias(true)

        let left: CGFloat = 18
        var y: CGFloat = 14
        text(L10n.t("Claude usage", "Claude 用量"), at: CGPoint(x: left, y: y), size: 15, weight: .bold, color: .white)
        y += 30

        let snap = content.snapshot
        y = windowRow(ctx, title: L10n.t("Current session", "当前 session"), window: snap?.session, y: y)
        y = windowRow(ctx, title: L10n.t("This week", "本周"), window: snap?.weekly, y: y)

        text(L10n.t("Free reset", "免费 reset"), at: CGPoint(x: left, y: y), size: 13, weight: .semibold, color: .white)
        let (resetText, resetColor) = freeResetText(snap)
        text(resetText, at: CGPoint(x: left + 90, y: y), size: 13, weight: .regular, color: resetColor)
        y += 26

        text(L10n.t("Code tasks", "Code 任务"), at: CGPoint(x: left, y: y), size: 13, weight: .semibold, color: .white)
        let lampColor: NSColor
        switch content.tasks.lamp {
        case .running: lampColor = SlimePalette.lampRunning
        case .waiting: lampColor = SlimePalette.lampWaiting
        case .done: lampColor = SlimePalette.lampDone
        case .none: lampColor = muted
        }
        text(content.hooksInstalled ? content.tasks.text : L10n.t("Right-click → Install hooks", "右键 → 安装 hooks"), at: CGPoint(x: left + 90, y: y), size: 13, weight: .regular, color: lampColor)
        y += 30

        if let problem = content.problem {
            text(problem, at: CGPoint(x: left, y: y), size: 11, weight: .regular,
                 color: SlimePalette.hex(0xF09595), width: bounds.width - 2 * left)
        } else if let fetched = snap?.fetchedAt {
            text(L10n.t("Updated ", "更新于 ") + LabelFormatter.fullDate(fetched), at: CGPoint(x: left, y: y), size: 11,
                 weight: .regular, color: muted)
        }
    }

    private func windowRow(_ ctx: CGContext, title: String, window: UsageWindow?, y start: CGFloat) -> CGFloat {
        let left: CGFloat = 18
        var y = start
        text(title, at: CGPoint(x: left, y: y), size: 13, weight: .semibold, color: .white)
        let pct = window.map { "\($0.percent)%" } ?? "--"
        text(pct, at: CGPoint(x: bounds.width - left - 44, y: y), size: 13, weight: .bold, color: .white,
             width: 44, alignRight: true)
        y += 22

        // Segmented pixel bar: 20 blocks, colored by the same thresholds as the slime.
        let blocks = 20, gap: CGFloat = 2
        let barWidth = bounds.width - 2 * left
        let blockWidth = (barWidth - gap * CGFloat(blocks - 1)) / CGFloat(blocks)
        let filled = window.map { Int((Double($0.percent) / 100 * Double(blocks)).rounded(.up)) } ?? 0
        let fill = SlimePalette.forMood(window.map { Mood(percent: $0.percent) }).body
        ctx.setShouldAntialias(false)
        for i in 0..<blocks {
            ctx.setFillColor((i < filled ? fill : track).cgColor)
            ctx.fill(CGRect(x: left + CGFloat(i) * (blockWidth + gap), y: y, width: blockWidth, height: 10))
        }
        ctx.setShouldAntialias(true)
        y += 16

        let resetLine = window?.resetsAt.map { L10n.t("Resets ", "重置于 ") + LabelFormatter.fullDate($0) }
            ?? L10n.t("Reset time unknown", "重置时间未知")
        text(resetLine, at: CGPoint(x: left, y: y), size: 11, weight: .regular, color: muted)
        return y + 28
    }

    private func freeResetText(_ snap: UsageSnapshot?) -> (String, NSColor) {
        guard let reset = snap?.freeReset else { return (L10n.t("Not available", "暂未读取到"), muted) }
        let left = reset.count ?? (reset.available ? 1 : 0)
        guard left > 0 else { return (L10n.t("None", "没有了"), muted) }
        guard reset.available else { return (L10n.t("\(left) left (not usable now)", "剩 \(left) 次（暂不可用）"), muted) }
        var parts = [reset.count.map { L10n.t("\($0) left", "剩 \($0) 次") } ?? L10n.t("Available", "可用")]
        if let expires = reset.expiresAt {
            parts.append(L10n.t("expires \(LabelFormatter.shortDate(expires))", "\(LabelFormatter.shortDate(expires)) 过期"))
        }
        return (parts.joined(separator: " · "), SlimePalette.hex(0xFAC775))
    }

    private func text(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor,
                      width: CGFloat? = nil, alignRight: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignRight ? .right : .left
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let w = width ?? (bounds.width - point.x - 12)
        (string as NSString).draw(with: NSRect(x: point.x, y: point.y, width: w, height: 40),
                                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }
}
