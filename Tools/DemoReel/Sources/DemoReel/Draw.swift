import AppKit
import CoreGraphics
import CoreText
@testable import DinkyLayout

// Draws one frame: a mock desktop per display with the windows where the engine put them, the minimap, the key
// overlay and a caption. Everything is placeholder art: no real app, no real text beyond a few generic words.

enum Palette {
    static let navy = hex(0x0A1A44)
    static let navyDeep = hex(0x07112E)
    static let royal = hex(0x1456E0)
    static let azure = hex(0x2F8CFF)
    static let cyan = hex(0x58C6FF)
    static let indigo = hex(0x4A4DE0)
    static let ice = hex(0xDCE8FF)
    static let ink = hex(0x0B1020)
    static let paper = hex(0xF6F8FC)
    static let windowBody = hex(0x131C38)
    static let windowBar = hex(0x19244A)
    static let terminalBody = hex(0x0B1124)

    static func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }
}

extension CGColor {
    func alpha(_ a: CGFloat) -> CGColor { copy(alpha: a * alpha) ?? self }
}

/// What a window looks like: placeholder content of one kind, an accent, a number and a generic label.
struct Look {
    enum Kind { case editor, browser, terminal, chat, notes }
    var kind: Kind
    var accent: CGColor
    var label: String

    static func of(_ id: WindowID) -> Look {
        switch (Int(id) - 1) % 5 {
        case 0: Look(kind: .editor, accent: Palette.hex(0x2F8CFF), label: "Editor")
        case 1: Look(kind: .browser, accent: Palette.hex(0x58C6FF), label: "Browser")
        case 2: Look(kind: .terminal, accent: Palette.hex(0x8A8DFF), label: "Terminal")
        case 3: Look(kind: .chat, accent: Palette.hex(0x4FD8E8), label: "Chat")
        default: Look(kind: .notes, accent: Palette.hex(0xB9CCFF), label: "Notes")
        }
    }
}

enum Fonts {
    static func system(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CTFont {
        NSFont.systemFont(ofSize: size, weight: weight) as CTFont
    }
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CTFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight) as CTFont
    }
    static func digits(_ size: CGFloat, _ weight: NSFont.Weight = .bold) -> CTFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) as CTFont
    }
}

enum Align { case left, center, right }

extension CGContext {
    /// Draws a line of text with its baseline at `y`. Returns its width.
    @discardableResult
    func text(_ string: String, _ font: CTFont, _ color: CGColor, x: CGFloat, y: CGFloat, align: Align = .left) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let start = switch align {
        case .left: x
        case .center: x - width / 2
        case .right: x - width
        }
        saveGState()
        textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        textPosition = CGPoint(x: start, y: y)
        CTLineDraw(line, self)
        restoreGState()
        return width
    }

    func fill(_ rect: CGRect, radius: CGFloat, _ color: CGColor) {
        guard rect.width > 0, rect.height > 0 else { return }
        let r = min(radius, rect.width / 2, rect.height / 2)
        addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        setFillColor(color)
        fillPath()
    }

    func stroke(_ rect: CGRect, radius: CGFloat, _ color: CGColor, width: CGFloat) {
        let r = min(radius, rect.width / 2, rect.height / 2)
        addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        setStrokeColor(color)
        setLineWidth(width)
        strokePath()
    }

    func clip(_ rect: CGRect, radius: CGFloat) {
        let r = min(radius, rect.width / 2, rect.height / 2)
        addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        clip()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// A stable pseudo-random number in 0..<1 for a window and a line.
func noise(_ a: Int, _ b: Int, _ c: Int = 0) -> CGFloat {
    var h = UInt64(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663 ^ c &* 83_492_791)
    h ^= h >> 33; h &*= 0xff51afd7ed558ccd; h ^= h >> 33; h &*= 0xc4ceb9fe1a85ec53; h ^= h >> 33
    return CGFloat(h % 10_000) / 10_000
}

struct Renderer {
    let scene: Scene
    /// Each minimap's mapping from points along its line to pixels.
    private let miniMaps: [(sx: CGFloat, sy: CGFloat, dx: CGFloat, dy: CGFloat)]
    /// For each minimap, where each group's content starts at its leftmost over the clip, in points.
    private let groupStarts: [[CGFloat]]

    static let size = CGSize(width: 1920, height: 1200)
    static let frameRadius: CGFloat = 36
    static let windowRadius: CGFloat = 14
    static let caption = "Rendered from Splay's layout engine. Window contents are placeholders."

    init(scene: Scene) {
        self.scene = scene
        // One scale for every minimap of the scene, fitted to all their content over the whole clip, so the strip and
        // the screen keep their proportions and the minimaps of a side-by-side compare at the same size.
        var extents: [CGRect] = Array(repeating: .null, count: scene.placement.panels.count)
        var starts: [[CGFloat]] = Array(repeating: [], count: scene.placement.panels.count)
        for tick in scene.timeline.ticks {
            for (i, mini) in tick.minis.enumerated() {
                if starts[i].isEmpty { starts[i] = Array(repeating: .infinity, count: mini.groups.count) }
                for item in mini.items { extents[i] = extents[i].union(item.rect) }
                for view in mini.views { extents[i] = extents[i].union(view.rect) }
                for (g, start) in mini.starts.enumerated() { starts[i][g] = min(starts[i][g], start) }
            }
        }
        groupStarts = starts
        // Columns run the full height, so the minimap is squashed: across it keeps the strip's proportions, capped so
        // it stays a minimap; down it fits the panel.
        let across = zip(extents, scene.placement.panels).map { extent, panel in
            min((panel.width - 40) / extent.width, 0.26)
        }.min() ?? 1
        let down = zip(extents, scene.placement.panels).map { extent, panel in
            (panel.height - 16) / extent.height
        }.min() ?? 1
        miniMaps = zip(extents, scene.placement.panels).map { extent, panel in
            (across, down, panel.midX - extent.midX * across, panel.midY - extent.midY * down)
        }
    }

    /// Draws the frame at time `t` into `ctx`, whose user space is the 1920 x 1200 design, top-left origin.
    /// `opaque` fills outside the rounded frame with navy, for video, instead of leaving it transparent.
    func draw(_ ctx: CGContext, at t: Double, opaque: Bool) {
        let tick = scene.timeline.tick(at: t)
        let frame = CGRect(origin: .zero, size: Self.size)
        if opaque {
            ctx.setFillColor(Palette.navyDeep)
            ctx.fill(frame)
        } else {
            ctx.clear(frame)
        }
        ctx.saveGState()
        ctx.clip(frame, radius: Self.frameRadius)
        drawBackdrop(ctx, frame)
        for (i, rect) in scene.placement.screens.enumerated() where i < tick.screens.count {
            drawScreen(ctx, tick.screens[i], in: rect)
            if i < scene.placement.titles.count {
                ctx.text(scene.placement.titles[i], Fonts.system(32, .semibold), Palette.ice, x: rect.midX, y: rect.minY - 30,
                         align: .center)
            }
        }
        for (i, panel) in scene.placement.panels.enumerated() where i < tick.minis.count {
            drawMini(ctx, tick.minis[i], map: miniMaps[i], panel: panel, panelIndex: i)
        }
        if let footnote = scene.placement.footnote {
            ctx.text(footnote.text, Fonts.system(28, .regular), Palette.ice.alpha(0.82), x: 960, y: footnote.baseline,
                     align: .center)
        }
        drawOverlay(ctx, at: t)
        ctx.text(Self.caption, Fonts.system(17, .regular), Palette.ice.alpha(0.5), x: 1920 - 52, y: 1200 - 20, align: .right)
        if let note = scene.placement.note {
            ctx.text(note, Fonts.system(17, .regular), Palette.ice.alpha(0.5), x: 52, y: 1200 - 20)
        }
        ctx.restoreGState()
    }

    // MARK: Backdrop

    private func drawBackdrop(_ ctx: CGContext, _ frame: CGRect) {
        ctx.setFillColor(Palette.navyDeep)
        ctx.fill(frame)
    }

    // MARK: Screen

    private func drawScreen(_ ctx: CGContext, _ shot: ScreenShot, in rect: CGRect) {
        let display = Shipped.display
        let s = rect.width / display.width
        ctx.saveGState()
        ctx.clip(rect, radius: 16)
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: s, y: s)
        for layer in shot.layers {
            ctx.saveGState()
            ctx.translateBy(x: layer.dx, y: 0)
            drawWallpaper(ctx, display)
            for window in layer.windows { drawWindow(ctx, window) }
            ctx.restoreGState()
        }
        drawMenuBar(ctx, display, workspace: shot.workspaceNumber)
        ctx.restoreGState()
        ctx.stroke(rect.insetBy(dx: -0.75, dy: -0.75), radius: 16.75, Palette.ice.alpha(0.18), width: 1.5)
    }

    /// The navy desktop with a soft light rising from below. The light is drawn as rings of whole-number colours a
    /// couple of levels apart, which the GIF keeps exactly (see `wallpaperSteps`), so it does not band.
    private func drawWallpaper(_ ctx: CGContext, _ display: CGRect) {
        ctx.setFillColor(Palette.navy)
        ctx.fill(display)
        let steps = Self.wallpaperSteps, radius: CGFloat = 980
        let centre = CGPoint(x: display.midX, y: display.maxY + 180)
        ctx.saveGState()
        ctx.clip(to: display)
        for (i, colour) in steps.enumerated() {
            // The rings narrow towards the middle, so the light falls off softly.
            let r = radius * pow(1 - CGFloat(i) / CGFloat(steps.count), 0.7)
            ctx.setFillColor(CGColor(srgbRed: CGFloat(colour >> 16 & 0xFF) / 255, green: CGFloat(colour >> 8 & 0xFF) / 255,
                                     blue: CGFloat(colour & 0xFF) / 255, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
        }
        ctx.restoreGState()
    }

    /// The wallpaper light's colours, outermost first: equal steps from the navy to a lighter blue.
    static let wallpaperSteps: [UInt32] = {
        let base: [Double] = [10, 26, 68], peak: [Double] = [17, 44, 110], count = 21
        return (1...count).map { i in
            let t = Double(i) / Double(count)
            let c = zip(base, peak).map { UInt32(($0 + ($1 - $0) * t).rounded()) }
            return c[0] << 16 | c[1] << 8 | c[2]
        }
    }()

    private func drawMenuBar(_ ctx: CGContext, _ display: CGRect, workspace: Int) {
        let bar = CGRect(x: 0, y: 0, width: display.width, height: Shipped.menuBar)
        ctx.setFillColor(Palette.ink.alpha(0.42))
        ctx.fill(bar)
        ctx.setFillColor(Palette.ice.alpha(0.08))
        ctx.fill(CGRect(x: 0, y: bar.maxY - 1, width: bar.width, height: 1))
        let mid = bar.midY
        ctx.fill(CGRect(x: 18, y: mid - 7, width: 14, height: 14), radius: 4, Palette.ice.alpha(0.55))
        var x: CGFloat = 50
        for (i, w) in [46.0, 32, 36, 40, 30].enumerated() {
            ctx.fill(CGRect(x: x, y: mid - 4, width: w, height: 8), radius: 4, Palette.ice.alpha(i == 0 ? 0.5 : 0.28))
            x += w + 18
        }
        // The status item: Splay shows the focused display's workspace number.
        ctx.text("\(workspace)", Fonts.digits(16, .bold), Palette.ice.alpha(0.95), x: display.width - 26, y: mid + 6, align: .center)
        var right = display.width - 54
        for w in [52.0, 18, 18] {
            ctx.fill(CGRect(x: right - w, y: mid - 4, width: w, height: 8), radius: 4, Palette.ice.alpha(0.28))
            right -= w + 16
        }
    }

    // MARK: Windows

    private func drawWindow(_ ctx: CGContext, _ w: WindowShot) {
        guard w.opacity > 0.001 else { return }
        ctx.saveGState()
        if w.opacity < 1 {
            ctx.setAlpha(w.opacity)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        let r = Self.windowRadius, frame = w.frame
        // The border ring covers the frame plus its width on every side, below the window (BorderWindow, order below).
        if let border = w.border {
            let width = Shipped.borderWidth
            let outer = frame.insetBy(dx: -width, dy: -width)
            let path = CGMutablePath()
            path.addRoundedRect(in: outer, cornerWidth: r + width, cornerHeight: r + width)
            path.addRoundedRect(in: frame, cornerWidth: r, cornerHeight: r)
            ctx.addPath(path)
            ctx.setFillColor(border)
            ctx.fillPath(using: .evenOdd)
        }
        let look = Look.of(w.id)
        ctx.saveGState()
        ctx.clip(frame, radius: r)
        ctx.setFillColor(look.kind == .terminal ? Palette.terminalBody : Palette.windowBody)
        ctx.fill(frame)
        drawContent(ctx, look, id: Int(w.id), in: CGRect(x: frame.minX, y: frame.minY + 44, width: frame.width,
                                                          height: frame.height - 44))
        drawTitleBar(ctx, look, id: w.id, CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 44))
        ctx.restoreGState()
        ctx.stroke(frame.insetBy(dx: 0.5, dy: 0.5), radius: r - 0.5, Palette.ice.alpha(0.1), width: 1)
        if w.opacity < 1 { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    private func drawTitleBar(_ ctx: CGContext, _ look: Look, id: WindowID, _ bar: CGRect) {
        ctx.setFillColor(look.kind == .terminal ? Palette.hex(0x10172E) : Palette.windowBar)
        ctx.fill(bar)
        ctx.setFillColor(Palette.ice.alpha(0.07))
        ctx.fill(CGRect(x: bar.minX, y: bar.maxY - 1, width: bar.width, height: 1))
        for i in 0..<3 {
            let c = CGPoint(x: bar.minX + 20 + CGFloat(i) * 20, y: bar.midY)
            ctx.setFillColor(Palette.ice.alpha(0.24))
            ctx.fillEllipse(in: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
        }
        let badge = CGRect(x: bar.minX + 86, y: bar.midY - 14, width: 30, height: 28)
        ctx.fill(badge, radius: 8, look.accent)
        ctx.text("\(id)", Fonts.digits(20, .heavy), Palette.ink, x: badge.midX, y: badge.midY + 7.5, align: .center)
        ctx.text(look.label, Fonts.system(15, .semibold), Palette.ice.alpha(0.72), x: badge.maxX + 12, y: bar.midY + 5.5)
    }

    private func drawContent(_ ctx: CGContext, _ look: Look, id: Int, in r: CGRect) {
        switch look.kind {
        case .editor: drawEditor(ctx, look, id, r)
        case .browser: drawBrowser(ctx, look, id, r)
        case .terminal: drawTerminal(ctx, look, id, r)
        case .chat: drawChat(ctx, look, id, r)
        case .notes: drawNotes(ctx, look, id, r)
        }
    }

    private func bar(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: CGColor) {
        ctx.fill(CGRect(x: x, y: y, width: max(w, 0), height: h), radius: h / 2, color)
    }

    private func drawEditor(_ ctx: CGContext, _ look: Look, _ id: Int, _ r: CGRect) {
        // A file list on wide windows, then lines of code as bars, indented.
        var left = r.minX
        if r.width > 640 {
            let side = CGRect(x: r.minX, y: r.minY, width: 190, height: r.height)
            ctx.setFillColor(Palette.ink.alpha(0.35))
            ctx.fill(side)
            for i in 0..<12 {
                let y = side.minY + 24 + CGFloat(i) * 30
                let indent: CGFloat = i % 4 == 0 ? 0 : 16
                bar(ctx, side.minX + 20 + indent, y, 70 + noise(id, i, 1) * 70 - indent, 9,
                    i == 3 ? look.accent.alpha(0.8) : Palette.ice.alpha(0.22))
            }
            left = side.maxX
        }
        let colors = [look.accent.alpha(0.85), Palette.ice.alpha(0.42), Palette.hex(0x8A8DFF, 0.8), Palette.ice.alpha(0.25),
                      Palette.hex(0x58C6FF, 0.75)]
        var indent = 0
        for line in 0..<40 {
            let y = r.minY + 26 + CGFloat(line) * 28
            if y > r.maxY { break }
            bar(ctx, left + 18, y, 18, 8, Palette.ice.alpha(0.14))
            if noise(id, line) < 0.12 { indent = 0; continue }
            if noise(id, line, 7) < 0.25 { indent = min(indent + 1, 3) } else if noise(id, line, 8) < 0.25 { indent = max(indent - 1, 0) }
            var x = left + 56 + CGFloat(indent) * 26
            let pieces = 1 + Int(noise(id, line, 2) * 3)
            for p in 0..<pieces {
                let w = 30 + noise(id, line, 10 + p) * 120
                bar(ctx, x, y, w, 9, colors[(line + p * 2 + id) % colors.count])
                x += w + 10
            }
        }
    }

    private func drawBrowser(_ ctx: CGContext, _ look: Look, _ id: Int, _ r: CGRect) {
        let address = CGRect(x: r.minX + 18, y: r.minY + 14, width: r.width - 36, height: 26)
        ctx.fill(address, radius: 13, Palette.ice.alpha(0.1))
        bar(ctx, address.minX + 16, address.midY - 4, min(220, address.width * 0.4), 8, Palette.ice.alpha(0.35))
        let page = CGRect(x: r.minX + 28, y: address.maxY + 24, width: r.width - 56, height: r.maxY - address.maxY - 24)
        let hero = CGRect(x: page.minX, y: page.minY, width: page.width, height: min(220, page.height * 0.32))
        ctx.fill(hero, radius: 12, look.accent.alpha(0.22))
        bar(ctx, hero.minX + 28, hero.minY + 40, min(380, hero.width * 0.6), 18, Palette.ice.alpha(0.85))
        bar(ctx, hero.minX + 28, hero.minY + 76, min(300, hero.width * 0.5), 10, Palette.ice.alpha(0.45))
        bar(ctx, hero.minX + 28, hero.minY + 98, min(260, hero.width * 0.42), 10, Palette.ice.alpha(0.45))
        ctx.fill(CGRect(x: hero.minX + 28, y: hero.minY + 136, width: 120, height: 34), radius: 10, look.accent)
        let columns = max(1, min(3, Int(page.width / 260)))
        let cardW = (page.width - CGFloat(columns - 1) * 18) / CGFloat(columns)
        let cardTop = hero.maxY + 24
        for c in 0..<columns {
            let card = CGRect(x: page.minX + CGFloat(c) * (cardW + 18), y: cardTop, width: cardW, height: 190)
            ctx.fill(card, radius: 12, Palette.ice.alpha(0.06))
            ctx.fill(CGRect(x: card.minX, y: card.minY, width: card.width, height: 90), radius: 12,
                     [look.accent.alpha(0.3), Palette.hex(0x8A8DFF, 0.3), Palette.hex(0x4FD8E8, 0.28)][c % 3])
            bar(ctx, card.minX + 16, card.minY + 110, card.width * 0.6, 10, Palette.ice.alpha(0.6))
            bar(ctx, card.minX + 16, card.minY + 132, card.width * 0.8, 8, Palette.ice.alpha(0.25))
            bar(ctx, card.minX + 16, card.minY + 150, card.width * 0.5, 8, Palette.ice.alpha(0.25))
        }
        for line in 0..<12 {
            let y = cardTop + 220 + CGFloat(line) * 24
            if y > r.maxY { break }
            bar(ctx, page.minX, y, page.width * (0.5 + noise(id, line) * 0.45), 8, Palette.ice.alpha(0.2))
        }
    }

    private func drawTerminal(_ ctx: CGContext, _ look: Look, _ id: Int, _ r: CGRect) {
        var y = r.minY + 26
        var line = 0
        while y < r.maxY - 20 {
            let prompt = line % 4 == 0
            if prompt {
                bar(ctx, r.minX + 20, y, 14, 9, look.accent)
                bar(ctx, r.minX + 42, y, 60 + noise(id, line) * 160, 9, Palette.ice.alpha(0.8))
            } else {
                bar(ctx, r.minX + 20, y, (r.width - 60) * (0.3 + noise(id, line) * 0.6), 9,
                    noise(id, line, 3) < 0.3 ? Palette.hex(0x4FD8E8, 0.6) : Palette.ice.alpha(0.32))
            }
            y += 26
            line += 1
            if line == 21 {
                bar(ctx, r.minX + 20, y, 14, 9, look.accent)
                ctx.fill(CGRect(x: r.minX + 42, y: y - 3, width: 10, height: 16), radius: 2, Palette.ice.alpha(0.85))
                break
            }
        }
    }

    private func drawChat(_ ctx: CGContext, _ look: Look, _ id: Int, _ r: CGRect) {
        var left = r.minX
        if r.width > 620 {
            let side = CGRect(x: r.minX, y: r.minY, width: 220, height: r.height)
            ctx.setFillColor(Palette.ink.alpha(0.3))
            ctx.fill(side)
            for i in 0..<9 {
                let y = side.minY + 22 + CGFloat(i) * 56
                let row = CGRect(x: side.minX + 10, y: y - 8, width: side.width - 20, height: 48)
                if i == 1 { ctx.fill(row, radius: 10, look.accent.alpha(0.22)) }
                ctx.setFillColor([look.accent, Palette.hex(0x8A8DFF), Palette.hex(0x58C6FF), Palette.ice][i % 4].alpha(0.75))
                ctx.fillEllipse(in: CGRect(x: row.minX + 10, y: row.minY + 8, width: 32, height: 32))
                bar(ctx, row.minX + 52, row.minY + 13, 70 + noise(id, i) * 60, 9, Palette.ice.alpha(0.6))
                bar(ctx, row.minX + 52, row.minY + 29, 50 + noise(id, i, 4) * 80, 7, Palette.ice.alpha(0.25))
            }
            left = side.maxX
        }
        let area = CGRect(x: left, y: r.minY, width: r.maxX - left, height: r.height)
        var y = area.minY + 24
        var i = 0
        while y < area.maxY - 90 {
            let mine = noise(id, i, 5) < 0.4
            let lines = 1 + Int(noise(id, i, 6) * 2.5)
            let w = min(area.width * 0.62, 160 + noise(id, i) * 260)
            let h = CGFloat(lines) * 18 + 22
            let x = mine ? area.maxX - 24 - w : area.minX + 24
            ctx.fill(CGRect(x: x, y: y, width: w, height: h), radius: 14, mine ? look.accent.alpha(0.85) : Palette.ice.alpha(0.1))
            for l in 0..<lines {
                bar(ctx, x + 16, y + 14 + CGFloat(l) * 18, (w - 32) * (l == lines - 1 ? 0.6 : 0.95), 8,
                    mine ? Palette.ink.alpha(0.55) : Palette.ice.alpha(0.5))
            }
            y += h + 16
            i += 1
        }
        let input = CGRect(x: area.minX + 20, y: area.maxY - 58, width: area.width - 40, height: 38)
        ctx.fill(input, radius: 19, Palette.ice.alpha(0.08))
        bar(ctx, input.minX + 18, input.midY - 4, min(180, input.width * 0.4), 8, Palette.ice.alpha(0.25))
    }

    private func drawNotes(_ ctx: CGContext, _ look: Look, _ id: Int, _ r: CGRect) {
        var left = r.minX
        if r.width > 600 {
            let side = CGRect(x: r.minX, y: r.minY, width: 230, height: r.height)
            ctx.setFillColor(Palette.ink.alpha(0.28))
            ctx.fill(side)
            for i in 0..<10 {
                let row = CGRect(x: side.minX + 10, y: side.minY + 12 + CGFloat(i) * 62, width: side.width - 20, height: 54)
                if i == 0 { ctx.fill(row, radius: 10, look.accent.alpha(0.25)) }
                bar(ctx, row.minX + 14, row.minY + 14, 90 + noise(id, i) * 70, 9, Palette.ice.alpha(0.6))
                bar(ctx, row.minX + 14, row.minY + 32, 120 + noise(id, i, 2) * 50, 7, Palette.ice.alpha(0.22))
            }
            left = side.maxX
        }
        let page = CGRect(x: left + 40, y: r.minY + 36, width: r.maxX - left - 80, height: r.height - 36)
        bar(ctx, page.minX, page.minY, min(340, page.width * 0.7), 20, Palette.ice.alpha(0.85))
        bar(ctx, page.minX, page.minY + 36, min(160, page.width * 0.4), 8, look.accent.alpha(0.8))
        var y = page.minY + 76
        var line = 0
        while y < page.maxY - 20 {
            if line % 6 == 5 {
                y += 18
            } else {
                let w = line % 6 == 4 ? page.width * (0.3 + noise(id, line) * 0.3) : page.width * (0.82 + noise(id, line) * 0.18)
                bar(ctx, page.minX, y, w, 9, Palette.ice.alpha(0.3))
                if line == 8 {
                    ctx.fill(CGRect(x: page.minX, y: y + 26, width: min(page.width, 420), height: 110), radius: 12,
                             look.accent.alpha(0.16))
                    y += 136
                }
            }
            y += 24
            line += 1
        }
    }

    // MARK: Minimap

    private func drawMini(_ ctx: CGContext, _ shot: MiniShot, map: (sx: CGFloat, sy: CGFloat, dx: CGFloat, dy: CGFloat), panel: CGRect,
                          panelIndex: Int) {
        func px(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * map.sx + map.dx, y: r.minY * map.sy + map.dy, width: r.width * map.sx,
                   height: r.height * map.sy)
        }
        // Each group's strip as a faint track under its columns.
        for (g, group) in shot.groups.enumerated() {
            let mine = shot.items.filter { $0.opacity >= 0.5 && $0.group == g }
            guard !mine.isEmpty else { continue }
            let extent = mine.dropFirst().reduce(mine[0].rect) { $0.union($1.rect) }
            let track = px(extent).insetBy(dx: -6, dy: -6)
            ctx.fill(track, radius: 8, Palette.ice.alpha(group.current ? 0.07 : 0.04))
        }
        for item in shot.items where item.opacity > 0.001 {
            let rect = px(item.rect)
            let look = Look.of(item.id)
            ctx.saveGState()
            ctx.setAlpha(item.opacity)
            if item.focused {
                ctx.setShadow(offset: .zero, blur: 14, color: look.accent.alpha(0.75))
                ctx.fill(rect, radius: 5, look.accent)
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
                ctx.stroke(rect.insetBy(dx: -1.5, dy: -1.5), radius: 6.5, Palette.ice, width: 2)
            } else {
                ctx.fill(rect, radius: 5, look.accent.alpha(0.42))
            }
            if rect.width >= 22, rect.height >= 24 {
                ctx.text("\(item.id)", Fonts.digits(21, .heavy), item.focused ? Palette.ink : Palette.ice.alpha(0.9),
                         x: rect.midX, y: rect.midY + 7.5, align: .center)
            }
            ctx.restoreGState()
        }
        for view in shot.views {
            let rect = px(view.rect).insetBy(dx: -5, dy: -5)
            ctx.stroke(rect, radius: 8, Palette.ice.alpha(view.current ? 0.95 : 0.3), width: view.current ? 2.5 : 1.5)
        }
        if scene.placement.numberGroups, let starts = groupStarts[safe: panelIndex] {
            for (i, group) in shot.groups.enumerated() where i < starts.count {
                let x = starts[i] * map.sx + map.dx - 22
                ctx.text("\(group.space + 1)", Fonts.digits(30, .bold), Palette.ice.alpha(group.current ? 0.95 : 0.4),
                         x: x, y: panel.midY + 11, align: .right)
            }
        }
    }

    // MARK: Overlay

    private func drawOverlay(_ ctx: CGContext, at t: Double) {
        guard let overlay = scene.timeline.overlays.last(where: { $0.alpha(at: t) > 0 }) else { return }
        let alpha = overlay.alpha(at: t)
        let capFont = Fonts.system(30, .semibold)
        let labelFont = overlay.isCommand ? Fonts.mono(28, .medium) : Fonts.system(28, .regular)
        let capH: CGFloat = 58, pad: CGFloat = 16, spacing: CGFloat = 10
        let capWidths = overlay.keys.map { max(capH, width(of: $0, capFont) + 30) }
        let labelWidth = width(of: overlay.label, labelFont)
        let total = capWidths.reduce(0, +) + spacing * CGFloat(max(overlay.keys.count - 1, 0)) + 24 + labelWidth
        let pill = CGRect(x: overlay.isCommand ? 0 : 0, y: 0, width: total + pad * 2 + 8, height: capH + pad * 2)
            .offsetBy(dx: (scene.placement.overlay.x - (total + pad * 2 + 8) / 2).rounded(),
                      dy: (scene.placement.overlay.y - (capH + pad * 2) / 2).rounded())
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.fill(pill, radius: pill.height / 2, Palette.ink.alpha(0.86))
        ctx.stroke(pill.insetBy(dx: 0.75, dy: 0.75), radius: pill.height / 2, Palette.ice.alpha(0.2), width: 1.5)
        var x = pill.minX + pad + 4
        for (key, w) in zip(overlay.keys, capWidths) {
            let cap = CGRect(x: x, y: pill.minY + pad, width: w, height: capH)
            ctx.fill(cap.offsetBy(dx: 0, dy: 3), radius: 12, Palette.hex(0x8FA6D6))
            ctx.fill(cap, radius: 12, Palette.ice)
            ctx.text(key, capFont, Palette.ink, x: cap.midX, y: cap.midY + 10.5, align: .center)
            x += w + spacing
        }
        x += 24 - spacing
        ctx.text(overlay.label, labelFont, overlay.isCommand ? Palette.hex(0x9ED8FF) : Palette.ice.alpha(0.85),
                 x: x, y: pill.midY + 9.5)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func width(of string: String, _ font: CTFont) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil))
    }
}
