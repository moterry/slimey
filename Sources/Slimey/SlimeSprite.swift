import AppKit

/// Pixel-art sprites. Each string row is one pixel row; '.' is transparent.
enum SlimeArt {
    // X outline, O body, D body shade, W highlight, K eye, P mouth, S sweat, A sand, Z zee
    static let idle = [
        ".....XXXX.....",
        "...XXOOOOXX...",
        "..XOOWWOOOOX..",
        ".XOOWOOOOOOOX.",
        ".XOOOOOOOOOOX.",
        "XOOOKWOOOKWOOX",
        "XOOOKKOOOKKOOX",
        "XOOOOOOPOOOOOX",
        "XDOOOOOOOOOODX",
        "XDDOOOOOOOODDX",
        ".XXXXXXXXXXXX.",
    ]
    static let blink = [
        ".....XXXX.....",
        "...XXOOOOXX...",
        "..XOOWWOOOOX..",
        ".XOOWOOOOOOOX.",
        ".XOOOOOOOOOOX.",
        "XOOOOOOOOOOOOX",
        "XOOOKKOOOKKOOX",
        "XOOOOOOPOOOOOX",
        "XDOOOOOOOOOODX",
        "XDDOOOOOOOODDX",
        ".XXXXXXXXXXXX.",
    ]
    /// Squashed just before a hop: one row shorter, a bit wider.
    static let squash = [
        "..............",
        "....XXXXXX....",
        "..XXOWWOOOXX..",
        ".XOOWOOOOOOOX.",
        "XOOOKWOOOKWOOX",
        "XOOOKKOOOKKOOX",
        "XOOOOOOPOOOOOX",
        "XDOOOOOOOOOODX",
        "XDDOOOOOOOODDX",
        "XDDDOOOOOODDDX",
        ".XXXXXXXXXXXX.",
    ]
    /// 100% used: a sleepy puddle.
    static let melted = [
        "..............",
        "..............",
        "..............",
        "..............",
        "..............",
        "....XXXXXX....",
        "..XXOWWOOOXX..",
        ".XOOKKOOOKKOX.",
        "XOOOOOOPOOOOOX",
        "XDDOOOOOOOODDX",
        ".XXXXXXXXXXXX.",
    ]
    /// Sweat drop drawn beside the head when stressed.
    static let sweat = [
        ".S.",
        "SSS",
        "SSS",
        ".S.",
    ]
    static let hourglass = [
        "XXXXX",
        "X.A.X",
        ".XAX.",
        "..X..",
        ".X.X.",
        "XAAAX",
        "XXXXX",
    ]
    static let zee = [
        "ZZZ",
        "..Z",
        ".Z.",
        "Z..",
        "ZZZ",
    ]
}

/// 3×5 bitmap glyphs for the label above the slime.
enum PixelFont {
    static let glyphs: [Character: [String]] = [
        "0": ["111", "101", "101", "101", "111"],
        "1": ["010", "110", "010", "010", "111"],
        "2": ["111", "001", "111", "100", "111"],
        "3": ["111", "001", "111", "001", "111"],
        "4": ["101", "101", "111", "001", "001"],
        "5": ["111", "100", "111", "001", "111"],
        "6": ["111", "100", "111", "101", "111"],
        "7": ["111", "001", "001", "001", "001"],
        "8": ["111", "101", "111", "101", "111"],
        "9": ["111", "101", "111", "001", "111"],
        "%": ["11001", "11010", "00100", "01011", "10011"],
        ":": ["0", "1", "0", "1", "0"],
        "·": ["0", "0", "1", "0", "0"],
        "?": ["111", "001", "011", "000", "010"],
        "-": ["000", "000", "111", "000", "000"],
        " ": ["0", "0", "0", "0", "0"],
    ]

    static func width(of text: String) -> Int {
        let widths = text.map { (glyphs[$0]?.first?.count ?? 3) }
        return widths.reduce(0, +) + max(0, widths.count - 1)
    }
}

struct SlimePalette {
    var body: NSColor
    var shade: NSColor

    static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func forMood(_ mood: Mood?) -> SlimePalette {
        switch mood {
        case .calm: return SlimePalette(body: hex(0x97C459), shade: hex(0x639922))
        case .busy: return SlimePalette(body: hex(0xFAC775), shade: hex(0xEF9F27))
        case .stressed, .melted: return SlimePalette(body: hex(0xF09595), shade: hex(0xE24B4A))
        case nil: return SlimePalette(body: hex(0xD3D1C7), shade: hex(0x888780))
        }
    }

    static let outline = hex(0x2C2C2A)
    static let eye = hex(0x1A1A1A)
    static let mouth = hex(0xD4537E)
    static let sweat = hex(0x85B7EB)
    static let sand = hex(0xEF9F27)
    static let lampRunning = hex(0x4FA3FF)
    static let lampDone = hex(0x3DDC84)
    static let lampWaiting = hex(0xFFD23F)
    static let labelBackground = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 0.82)
}

/// Draws and animates the slime plus its label. Coordinates are flipped (origin top-left).
class SlimeView: NSView {
    static let scale: CGFloat = 5       // sprite pixel size in points
    static let fontScale: CGFloat = 2   // label pixel size in points
    static let size = NSSize(width: 124, height: 114)

    /// nil means "no data yet" (grey slime).
    var mood: Mood? { didSet { needsDisplay = true } }
    var showHourglass = false { didSet { needsDisplay = true } }
    var label = "?" { didSet { needsDisplay = true } }
    var labelDimmed = false { didSet { needsDisplay = true } }
    /// Antenna lamp for Claude Code task status.
    var lamp: TaskLamp = .none { didSet { needsDisplay = true } }

    /// Animation frame counter (8 per second). Settable so the video renderer can pick frames.
    var tick = 0
    private var blinkUntil = 0
    private var nextBlink = 20
    private var timer: Timer?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// The video renderer hides the label on its title cards.
    var showsLabel = true

    /// The live window needs a clear backing each frame; the video renderer draws over its own scene.
    var clearsBackground = true

    /// When false, the view does not animate itself (used by the video renderer).
    init(frame: NSRect, animated: Bool = true) {
        super.init(frame: frame)
        guard animated else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in
            self?.advance()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func advance() {
        tick += 1
        if tick >= nextBlink {
            blinkUntil = tick + 2
            nextBlink = tick + Int.random(in: 24...48)
        }
        needsDisplay = true
    }

    /// Hop height in sprite pixels and whether to draw the squash frame, per animation tick.
    private func hopState() -> (lift: Int, squash: Bool) {
        if mood == .melted { return (0, false) }
        let period = mood == .stressed ? 8 : 14
        let heights = mood == .stressed
            ? [0, 1, 2, 3, 2, 1, 0, 0]
            : [0, 0, 0, 0, 0, 1, 2, 3, 3, 2, 1, 0, 0, 0]
        let phase = tick % period
        return (heights[phase], phase == period - 1 || phase == 0)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if clearsBackground { ctx.clear(bounds) }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)

        if showsLabel { drawLabel(ctx) }

        let s = Self.scale
        let spriteWidth = CGFloat(SlimeArt.idle[0].count) * s
        let spriteHeight = CGFloat(SlimeArt.idle.count) * s
        let originX = (bounds.width - spriteWidth) / 2
        let groundY = bounds.height - spriteHeight - 2

        let (lift, squash) = hopState()
        let rows: [String]
        if mood == .melted {
            rows = SlimeArt.melted
        } else if squash {
            rows = SlimeArt.squash
        } else if tick < blinkUntil {
            rows = SlimeArt.blink
        } else {
            rows = SlimeArt.idle
        }
        let spriteY = groundY - CGFloat(lift) * s
        drawSprite(ctx, rows, at: CGPoint(x: originX, y: spriteY), pixel: s, palette: .forMood(mood))

        if mood == .stressed {
            let wobble = CGFloat((tick / 2) % 2)
            drawSprite(ctx, SlimeArt.sweat, at: CGPoint(x: originX + spriteWidth - 2 * s, y: spriteY + (1 + wobble) * s),
                       pixel: s * 0.6, palette: .forMood(mood))
        }
        if mood == .melted {
            let drift = CGFloat((tick / 4) % 4)
            drawSprite(ctx, SlimeArt.zee, at: CGPoint(x: originX + spriteWidth - 2 * s, y: groundY + 2 * s - drift * 3),
                       pixel: 3, palette: .forMood(mood))
        }
        if lamp != .none {
            let topRow = rows.firstIndex { $0.contains { $0 != "." } } ?? 0
            drawLamp(ctx, baseX: originX + 9 * s, baseY: spriteY + CGFloat(topRow) * s)
        }
        if showHourglass {
            let bob = CGFloat((tick / 4) % 2) * 2
            drawSprite(ctx, SlimeArt.hourglass, at: CGPoint(x: originX - 14, y: spriteY + 2 * s + bob),
                       pixel: 3, palette: .forMood(mood))
        }
    }

    private func drawSprite(_ ctx: CGContext, _ rows: [String], at origin: CGPoint, pixel: CGFloat, palette: SlimePalette) {
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                let color: NSColor
                switch ch {
                case "X": color = SlimePalette.outline
                case "O": color = palette.body
                case "D": color = palette.shade
                case "W": color = .white
                case "K": color = SlimePalette.eye
                case "P": color = SlimePalette.mouth
                case "S": color = SlimePalette.sweat
                case "A": color = SlimePalette.sand
                case "Z": color = SlimePalette.sweat
                default: continue
                }
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(x: origin.x + CGFloat(x) * pixel, y: origin.y + CGFloat(y) * pixel,
                                width: pixel, height: pixel))
            }
        }
    }

    /// Antenna with a pixel bulb. Running/done "breathe" through four brightness steps;
    /// waiting blinks hard because it needs the user.
    private func drawLamp(_ ctx: CGContext, baseX: CGFloat, baseY: CGFloat) {
        let p: CGFloat = 3
        let color: NSColor
        let level: CGFloat
        switch lamp {
        case .waiting:
            color = SlimePalette.lampWaiting
            level = (tick / 2) % 2 == 0 ? 1 : 0.15
        case .running, .done, .none:
            color = lamp == .done ? SlimePalette.lampDone : SlimePalette.lampRunning
            let steps: [CGFloat] = [0.3, 0.5, 0.75, 1, 1, 0.75, 0.5, 0.3]
            level = steps[(tick / 2) % steps.count]
        }
        // Stem: two pixels tall, leaning one pixel right.
        ctx.setFillColor(SlimePalette.outline.cgColor)
        ctx.fill(CGRect(x: baseX, y: baseY - p, width: p, height: p))
        ctx.fill(CGRect(x: baseX + p, y: baseY - 2 * p, width: p, height: p))
        // Bulb: 3×3 pixels centred above the stem, with a plus-shaped halo one pixel out.
        let bulb = CGRect(x: baseX, y: baseY - 5 * p, width: 3 * p, height: 3 * p)
        ctx.setFillColor(color.withAlphaComponent(level * 0.35).cgColor)
        ctx.fill(bulb.insetBy(dx: -p, dy: 0))
        ctx.fill(bulb.insetBy(dx: 0, dy: -p))
        ctx.setFillColor(SlimePalette.outline.cgColor)
        ctx.fill(bulb)
        ctx.setFillColor(color.withAlphaComponent(0.5 + 0.5 * level).cgColor)
        ctx.fill(bulb)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.7 * level).cgColor)
        ctx.fill(CGRect(x: bulb.minX, y: bulb.minY, width: p, height: p))
    }

    private func drawLabel(_ ctx: CGContext) {
        // With no lamp to make room for, sit the label closer to the slime.
        let top: CGFloat = lamp == .none ? 14 : 0
        let p = Self.fontScale
        let textWidth = CGFloat(PixelFont.width(of: label)) * p
        let padX: CGFloat = 3 * p, padY: CGFloat = 2 * p
        let boxWidth = textWidth + padX * 2
        let boxHeight = 5 * p + padY * 2
        let boxX = ((bounds.width - boxWidth) / 2).rounded()

        // Pixel "pill": a rectangle with its four corner pixels knocked out.
        ctx.setFillColor(SlimePalette.labelBackground.cgColor)
        ctx.fill(CGRect(x: boxX + p, y: top, width: boxWidth - 2 * p, height: boxHeight))
        ctx.fill(CGRect(x: boxX, y: top + p, width: boxWidth, height: boxHeight - 2 * p))

        let textColor = labelDimmed ? NSColor(white: 0.6, alpha: 1) : NSColor.white
        ctx.setFillColor(textColor.cgColor)
        var x = boxX + padX
        for ch in label {
            let glyph = PixelFont.glyphs[ch] ?? PixelFont.glyphs["?"]!
            for (gy, row) in glyph.enumerated() {
                for (gx, bit) in row.enumerated() where bit == "1" {
                    ctx.fill(CGRect(x: x + CGFloat(gx) * p, y: top + padY + CGFloat(gy) * p, width: p, height: p))
                }
            }
            x += CGFloat(glyph[0].count + 1) * p
        }
    }
}
