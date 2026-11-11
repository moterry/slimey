import AppKit

/// Transparent, borderless, always-on-top window holding the slime. Drag to move, click to
/// toggle details, right-click for the menu. Remembers its position.
final class PetWindow: NSWindow {
    let slime: InteractiveSlimeView
    private static let originKey = "petWindowOrigin"

    init() {
        slime = InteractiveSlimeView(frame: NSRect(origin: .zero, size: SlimeView.size))
        super.init(contentRect: NSRect(origin: .zero, size: SlimeView.size),
                   styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isMovable = false // we move it ourselves so a click can be told apart from a drag
        contentView = slime
        setFrameOrigin(Self.savedOrigin() ?? Self.defaultOrigin())
        slime.onDragEnded = { [weak self] in self?.saveOrigin() }
    }

    override var canBecomeKey: Bool { false }

    private static func defaultOrigin() -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - SlimeView.size.width - 24, y: visible.minY + 24)
    }

    private static func savedOrigin() -> NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: originKey) else { return nil }
        let p = NSPointFromString(s)
        // Ignore positions that no longer land on any screen (e.g. an unplugged monitor).
        let frame = NSRect(origin: p, size: SlimeView.size)
        return NSScreen.screens.contains { $0.frame.intersects(frame) } ? p : nil
    }

    private func saveOrigin() {
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: Self.originKey)
    }
}

final class InteractiveSlimeView: SlimeView {
    var onClick: () -> Void = {}
    var onDragEnded: () -> Void = {}
    var menuProvider: () -> NSMenu? = { nil }

    private var mouseDownScreen: NSPoint?
    private var windowOriginAtDown: NSPoint = .zero
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownScreen = NSEvent.mouseLocation
        windowOriginAtDown = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownScreen, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if !dragged && hypot(dx, dy) < 3 { return }
        dragged = true
        window.setFrameOrigin(NSPoint(x: windowOriginAtDown.x + dx, y: windowOriginAtDown.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownScreen = nil }
        if dragged { onDragEnded() } else { onClick() }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
