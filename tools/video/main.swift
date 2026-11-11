import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// Renders the 15-second Slimey demo video frame by frame, reusing the app's own sprite and panel
// drawing code. Usage: make-video <out-dir> [en|zh]

let size = 1080
let fps = 30
let duration = 15.0
let frameCount = Int(duration * Double(fps))

// MARK: - Copy

struct Copy {
    var tagline, scene2, scene3a, scene3b, scene4, scene4b, endLine, prompt, working, done: String

    static let en = Copy(
        tagline: "a tiny pixel pet for Claude users",
        scene2: "Your Claude usage, always in view",
        scene3a: "Glows blue while Claude Code works…",
        scene3b: "…and green when it's done",
        scene4: "Gets nervous as your limit runs out",
        scene4b: "…and naps when it hits 100%",
        endLine: "Free & open source · macOS",
        prompt: "> fix the flaky login test",
        working: "✻ Working",
        done: "✓ Done. All tests pass")

    static let zh = Copy(
        tagline: "给 Claude 用户的像素桌面宠物",
        scene2: "Claude 用量，随时看得见",
        scene3a: "Claude Code 在干活，它亮蓝灯…",
        scene3b: "…干完了，就变绿灯",
        scene4: "额度快用完时，它会紧张",
        scene4b: "…用到 100%，就化成一滩睡着了",
        endLine: "免费开源 · macOS",
        prompt: "> 修一下不稳定的登录测试",
        working: "✻ 干活中",
        done: "✓ 完成，测试全部通过")
}

// MARK: - Helpers

func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(max(x, lo), hi) }
func progress(_ t: Double, _ start: Double, _ end: Double) -> Double { clamp((t - start) / (end - start)) }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
/// Drop-and-settle bounce (0 → 1).
func bounce(_ x: Double) -> Double {
    let n = 7.5625, d = 2.75
    var x = x
    if x < 1 / d { return n * x * x }
    if x < 2 / d { x -= 1.5 / d; return n * x * x + 0.75 }
    if x < 2.5 / d { x -= 2.25 / d; return n * x * x + 0.9375 }
    x -= 2.625 / d; return n * x * x + 0.984375
}

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// Draws text centred in `rect` (flipped context, NSGraphicsContext must be current).
func drawText(_ text: String, in rect: CGRect, font: NSFont, color: CGColor, alpha: Double = 1,
              align: NSTextAlignment = .center) {
    guard alpha > 0 else { return }
    let style = NSMutableParagraphStyle()
    style.alignment = align
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor(cgColor: color)!.withAlphaComponent(CGFloat(alpha)),
        .paragraphStyle: style,
    ]
    (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attrs)
}

func withView(_ ctx: CGContext, _ view: NSView, at origin: CGPoint, scale: CGFloat, alpha: CGFloat = 1) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: scale, y: scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    view.draw(view.bounds)
    ctx.restoreGState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
}

// MARK: - Scene pieces

let cream = hex(0xFFF4E0)
let ink = hex(0x2C2C2A)

func fill(_ ctx: CGContext, _ color: CGColor, _ rect: CGRect) {
    ctx.setFillColor(color)
    ctx.fill(rect)
}

/// Pixel-art wallpaper: stepped sky, clouds and two rows of hills.
func drawWallpaper(_ ctx: CGContext, t: Double) {
    let sky: [UInt32] = [0xAFCBFF, 0xBCD3FF, 0xCBDBFF, 0xDAE2FF, 0xE9E6FA, 0xF6E8F2]
    let band = CGFloat(size) / CGFloat(sky.count) * 0.75
    for (i, c) in sky.enumerated() { fill(ctx, hex(c), CGRect(x: 0, y: CGFloat(i) * band, width: 1080, height: band + 1)) }
    fill(ctx, hex(sky.last!), CGRect(x: 0, y: band * CGFloat(sky.count), width: 1080, height: 1080))
    let p: CGFloat = 20
    // Clouds drift slowly.
    for (cx, cy, w) in [(120.0, 300.0, 7), (620.0, 250.0, 9), (900.0, 360.0, 6)] {
        let x = CGFloat(cx + t * 12).truncatingRemainder(dividingBy: 1240) - 80
        fill(ctx, hex(0xFFFFFF, 0.9), CGRect(x: x, y: CGFloat(cy), width: CGFloat(w) * p, height: p))
        fill(ctx, hex(0xFFFFFF, 0.9), CGRect(x: x + p, y: CGFloat(cy) - p, width: CGFloat(w - 3) * p, height: p))
    }
    for (base, amp, freq, phase, color) in [(700.0, 60.0, 0.006, 0.0, 0xB8E0A8), (800.0, 50.0, 0.009, 2.0, 0x8FCB86)] as [(Double, Double, Double, Double, UInt32)] {
        var x: CGFloat = 0
        while x < 1080 {
            let top = base - amp * (0.5 + 0.5 * sin(Double(x) * freq + phase))
            let snapped = (top / Double(p)).rounded() * Double(p)
            fill(ctx, hex(color), CGRect(x: x, y: CGFloat(snapped), width: p, height: 1080 - CGFloat(snapped)))
            x += p
        }
    }
    // Menu bar.
    fill(ctx, hex(0xFFFFFF, 0.72), CGRect(x: 0, y: 0, width: 1080, height: 40))
    for (x, w) in [(24.0, 26.0), (74.0, 70.0), (164.0, 46.0), (230.0, 46.0)] {
        fill(ctx, hex(0x2C2C2A, 0.55), CGRect(x: x, y: 15, width: w, height: 10))
    }
    drawText("18:02", in: CGRect(x: 900, y: 7, width: 160, height: 30), font: roundedFont(22, .semibold),
             color: hex(0x2C2C2A, 0.8), align: .right)
}

/// Caption card at the top of desktop scenes.
func drawCaption(_ ctx: CGContext, _ text: String, alpha: Double, y: CGFloat = 78) {
    guard alpha > 0 else { return }
    let font = roundedFont(50, .heavy)
    let width = min(1000, (text as NSString).size(withAttributes: [.font: font]).width + 80)
    let rect = CGRect(x: (1080 - width) / 2, y: y + CGFloat(1 - alpha) * 16, width: width, height: 96)
    ctx.saveGState()
    ctx.setAlpha(CGFloat(alpha))
    ctx.setFillColor(hex(0xFFFFFF, 0.94))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 28, cornerHeight: 28, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    drawText(text, in: rect.insetBy(dx: 20, dy: 18), font: font, color: ink, alpha: alpha)
}

/// Pixel arrow cursor; `pressed` shrinks it slightly.
func drawCursor(_ ctx: CGContext, at p: CGPoint, pressed: Bool) {
    let rows = [
        "X...........", "XX..........", "XWX.........", "XWWX........", "XWWWX.......", "XWWWWX......",
        "XWWWWWX.....", "XWWWWWWX....", "XWWWWWWWX...", "XWWWWWWWWX..", "XWWWWWXXXXX.", "XWWXWWX.....",
        "XWX.XWWX....", "XX..XWWX....", "X....XWWX...", ".....XWWX...", "......XX....",
    ]
    let s: CGFloat = pressed ? 3.4 : 4
    for (y, row) in rows.enumerated() {
        for (x, ch) in row.enumerated() where ch != "." {
            fill(ctx, ch == "X" ? hex(0x111111) : hex(0xFFFFFF),
                 CGRect(x: p.x + CGFloat(x) * s, y: p.y + CGFloat(y) * s, width: s, height: s))
        }
    }
}

func drawTerminal(_ ctx: CGContext, lines: [(String, CGColor)], alpha: Double, slide: Double) {
    guard alpha > 0 else { return }
    let rect = CGRect(x: 50, y: 250 + CGFloat(1 - slide) * 40, width: 600, height: 300)
    ctx.saveGState()
    ctx.setAlpha(CGFloat(alpha))
    ctx.setFillColor(hex(0x1E1E24))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.fillPath()
    for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        ctx.setFillColor(hex(UInt32(c)))
        ctx.fillEllipse(in: CGRect(x: rect.minX + 26 + CGFloat(i) * 30, y: rect.minY + 22, width: 18, height: 18))
    }
    ctx.restoreGState()
    let mono = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)
    for (i, line) in lines.enumerated() {
        drawText(line.0, in: CGRect(x: rect.minX + 32, y: rect.minY + 72 + CGFloat(i) * 52, width: rect.width - 50, height: 44),
                 font: mono, color: line.1, alpha: alpha, align: .left)
    }
}

// MARK: - Scenes

let slime = SlimeView(frame: NSRect(origin: .zero, size: SlimeView.size), animated: false)
slime.clearsBackground = false
let panel = DetailPanel()

func resetSlime(t: Double) {
    slime.tick = Int(t * 8)
    slime.showsLabel = true
    slime.labelDimmed = false
    slime.showHourglass = false
    slime.lamp = .none
}

func titleCard(_ ctx: CGContext, t: Double, copy: Copy, ending: Bool) {
    fill(ctx, cream, CGRect(x: 0, y: 0, width: 1080, height: 1080))
    resetSlime(t: t)
    slime.showsLabel = false
    slime.mood = .calm
    slime.lamp = ending ? .done : .none
    let scale: CGFloat = 4.6
    let w = SlimeView.size.width * scale
    let restY: CGFloat = ending ? 120 : 150
    let local = ending ? t - 13.2 : t
    let drop = ending ? 1.0 : bounce(progress(local, 0.05, 1.05))
    let y = -600 + (restY + 600) * CGFloat(drop)
    withView(ctx, slime, at: CGPoint(x: (1080 - w) / 2, y: y), scale: scale)

    let titleAlpha = easeOut(progress(local, ending ? 0.1 : 0.9, ending ? 0.5 : 1.3))
    drawText("Slimey", in: CGRect(x: 0, y: 650, width: 1080, height: 170), font: roundedFont(150, .black),
             color: ink, alpha: titleAlpha)
    let subAlpha = easeOut(progress(local, ending ? 0.3 : 1.2, ending ? 0.7 : 1.6))
    drawText(ending ? copy.endLine : copy.tagline, in: CGRect(x: 60, y: 840, width: 960, height: 70),
             font: roundedFont(46, .semibold), color: hex(0x5F5E5A), alpha: subAlpha)
    if ending {
        let urlAlpha = easeOut(progress(local, 0.5, 0.9))
        let rect = CGRect(x: 190, y: 935, width: 700, height: 76)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(urlAlpha))
        ctx.setFillColor(ink)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 38, cornerHeight: 38, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        drawText("github.com/moterry/slimey", in: rect.insetBy(dx: 10, dy: 16),
                 font: NSFont.monospacedSystemFont(ofSize: 36, weight: .semibold), color: hex(0xFFFFFF), alpha: urlAlpha)
    }
}

let slimeScale: CGFloat = 3.2
let slimeOrigin = CGPoint(x: 1080 - SlimeView.size.width * slimeScale - 40,
                          y: 1080 - SlimeView.size.height * slimeScale - 24)

let demoReset = Date(timeIntervalSince1970: 1_795_000_000)
func snapshot(session: Int, weekly: Int) -> UsageSnapshot {
    UsageSnapshot(session: UsageWindow(percent: session, resetsAt: demoReset),
                  weekly: UsageWindow(percent: weekly, resetsAt: demoReset.addingTimeInterval(4 * 86400)),
                  freeReset: FreeReset(available: false, count: 0, expiresAt: nil),
                  fetchedAt: demoReset.addingTimeInterval(-3 * 3600))
}
let labelTime = LabelFormatter.label(for: snapshot(session: 23, weekly: 41)).components(separatedBy: " · ").last ?? "18:40"

func usageScene(_ ctx: CGContext, t: Double, copy: Copy) {
    drawWallpaper(ctx, t: t)
    resetSlime(t: t)
    slime.mood = .calm
    slime.label = "23% · \(labelTime)"
    let clickAt = 3.8
    // Squash on click by nudging the tick into the squash frame.
    if t >= clickAt && t < clickAt + 0.12 { slime.tick = 13 }
    withView(ctx, slime, at: slimeOrigin, scale: slimeScale)
    drawCaption(ctx, copy.scene2, alpha: easeOut(progress(t, 2.5, 2.9)))

    let panelT = easeOut(progress(t, clickAt + 0.05, clickAt + 0.35))
    if panelT > 0 {
        panel.content = DetailContent(snapshot: snapshot(session: 23, weekly: 41), problem: nil,
                                      tasks: TaskSummary(running: 0, waiting: 0, done: 0), hooksInstalled: true)
        let scale: CGFloat = 1.72 * CGFloat(0.88 + 0.12 * panelT)
        let size = panel.contentView!.bounds.size
        let origin = CGPoint(x: 70 + (1 - 0.88) * 0, y: 330 + CGFloat(1 - panelT) * 30)
        withView(ctx, panel.contentView!, at: origin, scale: scale, alpha: CGFloat(panelT))
        _ = size
    }
    // Cursor glides to the slime, clicks.
    let move = easeInOut(progress(t, 2.9, 3.7))
    let from = CGPoint(x: 480, y: 620), to = CGPoint(x: slimeOrigin.x + 190, y: slimeOrigin.y + 250)
    let cursor = CGPoint(x: from.x + (to.x - from.x) * move, y: from.y + (to.y - from.y) * move)
    drawCursor(ctx, at: cursor, pressed: t >= clickAt && t < clickAt + 0.15)
}

func taskScene(_ ctx: CGContext, t: Double, copy: Copy) {
    drawWallpaper(ctx, t: t)
    resetSlime(t: t)
    slime.mood = .calm
    slime.label = "31% · \(labelTime)"
    let doneAt = 8.6
    let typed = progress(t, 6.5, 7.2)
    let prompt = String(copy.prompt.prefix(Int(Double(copy.prompt.count) * typed)))
    var lines: [(String, CGColor)] = [("$ claude", hex(0xE8E6E3)), (prompt, hex(0xE8E6E3))]
    if t >= 7.3 && t < doneAt {
        slime.lamp = .running
        let dots = String(repeating: ".", count: Int(t * 3) % 4)
        lines.append((copy.working + dots, hex(0x4FA3FF)))
    } else if t >= doneAt {
        slime.lamp = .done
        lines.append((copy.working + "...", hex(0x6B6B70)))
        lines.append((copy.done, hex(0x3DDC84)))
    }
    drawTerminal(ctx, lines: lines, alpha: easeOut(progress(t, 6.1, 6.5)), slide: easeOut(progress(t, 6.1, 6.5)))
    // Bigger than in the usage scene so the antenna light reads clearly.
    let scale: CGFloat = 4.4
    withView(ctx, slime, at: CGPoint(x: 1080 - SlimeView.size.width * scale + 10, y: 1080 - SlimeView.size.height * scale - 10),
             scale: scale)
    if t < doneAt {
        drawCaption(ctx, copy.scene3a, alpha: easeOut(progress(t, 6.2, 6.6)) * (1 - progress(t, doneAt - 0.15, doneAt)))
    } else {
        drawCaption(ctx, copy.scene3b, alpha: easeOut(progress(t, doneAt, doneAt + 0.3)))
    }
}

func limitScene(_ ctx: CGContext, t: Double, copy: Copy) {
    drawWallpaper(ctx, t: t)
    resetSlime(t: t)
    // Climb with pauses so each mood (yellow, sweating red, asleep) gets a beat.
    let keys: [(Double, Double)] = [(10.4, 23), (10.9, 62), (11.5, 68), (11.8, 88), (12.45, 93), (12.7, 100)]
    var value = 23.0
    for (a, b) in zip(keys, keys.dropFirst()) where t >= a.0 {
        value = a.1 + (b.1 - a.1) * easeInOut(progress(t, a.0, b.0))
    }
    let p = Int(value.rounded())
    slime.mood = Mood(percent: p)
    slime.label = "\(p)% · \(labelTime)"
    // A bigger slime here: this is the cute moment.
    let scale: CGFloat = 4.4
    let origin = CGPoint(x: (1080 - SlimeView.size.width * scale) / 2, y: 1080 - SlimeView.size.height * scale - 60)
    withView(ctx, slime, at: origin, scale: scale)
    if t < 12.7 {
        drawCaption(ctx, copy.scene4, alpha: easeOut(progress(t, 10.3, 10.7)) * (1 - progress(t, 12.55, 12.7)))
    } else {
        drawCaption(ctx, copy.scene4b, alpha: easeOut(progress(t, 12.7, 12.95)))
    }
}

func renderScene(_ ctx: CGContext, t: Double, copy: Copy) {
    switch t {
    case ..<2.4: titleCard(ctx, t: t, copy: copy, ending: false)
    case ..<6.0: usageScene(ctx, t: t, copy: copy)
    case ..<10.2: taskScene(ctx, t: t, copy: copy)
    case ..<13.2: limitScene(ctx, t: t, copy: copy)
    default: titleCard(ctx, t: t, copy: copy, ending: true)
    }
}

// MARK: - Frame + encode

let cuts = [2.4, 6.0, 10.2, 13.2]
let fade = 0.25

func makeContext(_ data: UnsafeMutableRawPointer? = nil, bytesPerRow: Int = 0) -> CGContext {
    let ctx = CGContext(data: data, width: size, height: size, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    return ctx
}

func renderFrame(t: Double, copy: Copy, into ctx: CGContext) {
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    renderScene(ctx, t: t, copy: copy)
    // Crossfade: overlay the previous scene's last moment, fading out.
    for cut in cuts where t >= cut && t < cut + fade {
        let layer = makeContext()
        renderScene(layer, t: cut - 0.001, copy: copy)
        if let image = layer.makeImage() {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(1 - (t - cut) / fade))
            ctx.translateBy(x: 0, y: CGFloat(size))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            ctx.restoreGState()
        }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    }
}

func writeVideo(copy: Copy, to url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000,
                                          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<frameCount {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        guard let pixels = buffer else { fatalError("no pixel buffer") }
        CVPixelBufferLockBaseAddress(pixels, [])
        let ctx = makeContext(CVPixelBufferGetBaseAddress(pixels), bytesPerRow: CVPixelBufferGetBytesPerRow(pixels))
        renderFrame(t: Double(frame) / Double(fps), copy: copy, into: ctx)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    if writer.status != .completed { throw writer.error ?? NSError(domain: "MakeVideo", code: 1) }
}

/// Smaller GIF for the README: 540px, 15 fps.
func writeGIF(copy: Copy, to url: URL) {
    let gifFPS = 15, gifSize = 540
    let count = Int(duration * Double(gifFPS))
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else { return }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(gifFPS)]] as CFDictionary
    for frame in 0..<count {
        let ctx = makeContext()
        renderFrame(t: Double(frame) / Double(gifFPS), copy: copy, into: ctx)
        guard let full = ctx.makeImage(),
              let small = CGContext(data: nil, width: gifSize, height: gifSize, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        small.interpolationQuality = .high
        small.draw(full, in: CGRect(x: 0, y: 0, width: gifSize, height: gifSize))
        if let image = small.makeImage() { CGImageDestinationAddImage(dest, image, frameProps) }
    }
    CGImageDestinationFinalize(dest)
}

func writePNG(t: Double, copy: Copy, to url: URL) {
    let ctx = makeContext()
    renderFrame(t: t, copy: copy, into: ctx)
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Main

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "media")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let mode = args.count > 2 ? args[2] : "all"

if mode == "frames" {
    L10n.lang = .en
    // Key frames only, for checking the look quickly.
    for t in [7.8, 9.4, 11.3, 12.2, 13.0] {
        writePNG(t: t, copy: .en, to: outDir.appendingPathComponent(String(format: "frame-%04.1f.png", t)))
    }
    exit(0)
}

for (name, copy, lang) in [("en", Copy.en, Lang.en), ("zh", Copy.zh, Lang.zh)] {
    L10n.lang = lang
    try writeVideo(copy: copy, to: outDir.appendingPathComponent("slimey-demo-\(name).mp4"))
    writePNG(t: 9.4, copy: copy, to: outDir.appendingPathComponent("slimey-poster-\(name).png"))
    print("wrote slimey-demo-\(name).mp4")
}
L10n.lang = .en
writeGIF(copy: .en, to: outDir.appendingPathComponent("slimey-demo.gif"))
print("wrote slimey-demo.gif")
