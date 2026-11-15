import CoreGraphics
import DinkyCommands
import DinkyConfig
@testable import DinkyLayout

// What the demo takes from Splay itself: the shipped config, its key bindings and the layout engine, set up the way
// the app's Coordinator sets up a workspace. Nothing here is retyped from the docs.

enum Shipped {
    static let config = Config.default

    /// A 14-inch MacBook Pro at its default resolution, with the Dock hidden.
    static let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    static let menuBar: CGFloat = 33
    /// What the app tiles in: the display below the menu bar (tilingArea with an auto-hidden Dock).
    static var bounds: CGRect {
        tilingArea(frame: display, visible: CGRect(x: 0, y: menuBar, width: display.width, height: display.height - menuBar),
                   dockAutohides: true)
    }

    /// The config's gaps for the built-in display, mapped as DisplayGeometry.swift maps them.
    static var gaps: DinkyLayout.Gaps {
        let g = config.gaps(for: Monitor(name: "Built-in Retina Display", isMain: true, count: 1))
        return DinkyLayout.Gaps(horizontal: CGFloat(g.inner.horizontal), vertical: CGFloat(g.inner.vertical),
                                top: CGFloat(g.outer.top), bottom: CGFloat(g.outer.bottom),
                                left: CGFloat(g.outer.left), right: CGFloat(g.outer.right))
    }

    /// The glide, as Animator.setDuration builds it from `[animations] duration-ms`.
    static var animationSeconds: Double { Double(config.animations.durationMs) / 1000 }
    static var spring: Spring { Spring(response: animationSeconds, damping: 0.9) }
    static var timeout: Double { max(1, 4 * animationSeconds) }

    static var borderWidth: CGFloat { CGFloat(config.borders.width) }
    static var activeBorder: CGColor { cg(config.borders.activeColor) }
    static var inactiveBorder: CGColor { cg(config.borders.inactiveColor) }

    static func cg(_ c: DinkyConfig.Color) -> CGColor {
        CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    /// The tiling algorithm for a layout name, as LayoutSettings.swift maps it.
    static func algorithm(_ kind: LayoutKind) -> TilingAlgorithm {
        switch kind {
        case .tiles, .dwindle: .dwindle(.tiles)
        case .accordion: .dwindle(.accordion)
        case .scrolling: .scrolling
        case .master: .master
        case .fixed: fatalError("the demo has no fixed layout")
        }
    }

    /// A new workspace, set up as Coordinator.key(of:) sets one up.
    static func workspace(_ kind: LayoutKind = config.defaultLayout) -> Workspace {
        var w = Workspace(bounds: bounds, gaps: gaps, accordionPadding: CGFloat(config.accordion.padding),
                          autoOrientAccordions: config.accordion.orientation == .auto, algorithm: algorithm(kind))
        w.columnWidth = config.scrolling.columnWidth
        w.masterSize = config.master.size
        w.fullscreenWidth = config.fullscreenWidth
        w.loneWindowWidth = config.loneWindowWidth
        w.walls = []
        // StripSettings.swift's applyStrip.
        w.centerFocusedColumn = switch config.scrolling.centerFocusedColumn {
        case .never: .never
        case .always: .always
        case .onOverflow: .onOverflow
        }
        w.presetColumnWidths = config.scrolling.presetColumnWidths
        w.sliver = CGFloat(config.scrolling.peek)
        return w
    }

    /// The commands a key runs in the shipped main mode. Stops the tool if the key is not bound, so a demo never
    /// shows a key the app does not answer to.
    static func commands(for key: String) -> [Command] {
        guard let combo = try? KeyCombo(key), let binding = config.modes["main"]?.bindings[combo] else {
            fatalError("'\(key)' is not bound in the shipped config")
        }
        return binding.commands.map { try! Command.parse($0) }
    }

    /// The command text a key runs, as the overlay shows it.
    static func commandText(for key: String) -> String {
        guard let combo = try? KeyCombo(key), let binding = config.modes["main"]?.bindings[combo] else {
            fatalError("'\(key)' is not bound in the shipped config")
        }
        return binding.commands.joined(separator: "; ")
    }

    /// Keycap labels for a combo, modifiers in Apple's order.
    static func keycaps(_ key: String) -> [String] {
        let combo = try! KeyCombo(key)
        var caps: [String] = []
        if combo.modifiers.contains(.ctrl) { caps.append("⌃") }
        if combo.modifiers.contains(.alt) { caps.append("⌥") }
        if combo.modifiers.contains(.shift) { caps.append("⇧") }
        if combo.modifiers.contains(.cmd) { caps.append("⌘") }
        let names = ["left": "←", "right": "→", "up": "↑", "down": "↓", "home": "Home", "end": "End",
                     "tab": "Tab", "esc": "Esc", "space": "Space", "enter": "Return"]
        caps.append(names[combo.key] ?? combo.key.uppercased())
        return caps
    }
}

extension Workspace {
    /// Every window's rect along the whole strip and the screen's rect on it, in points, the strip's first column
    /// starting at 0. Windows scrolled out of view are where the strip has them, not where they are parked. Outside
    /// the strip, the screen's own frames.
    func stripView() -> (frames: [WindowID: CGRect], screen: CGRect) {
        let tiled = layout()
        guard isScrolling, !root.children.isEmpty else { return (tiled.frames, bounds) }
        let strip = tiledLayout()
        let area = stripArea, spans = columnSpans(in: area)
        let shift = offset(for: spans, in: area) - area.minX
        // A lone column fills the screen as layout() narrows it; one window is never parked.
        let frames = strip.frames.count == 1 ? tiled.frames : strip.frames
        return (frames.mapValues { $0.offsetBy(dx: shift, dy: 0) }, bounds.offsetBy(dx: shift, dy: 0))
    }
}
