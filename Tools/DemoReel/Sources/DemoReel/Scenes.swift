import CoreGraphics
import DinkyConfig
@testable import DinkyLayout

// The four clips. Each sets up desks with the shipped config, plays its beats through the engine and says where on
// the 1920 x 1200 frame each display and minimap goes.

/// Where things go on the frame, in pixels of the 1920 x 1200 design.
struct Placement {
    /// One rect per desk; the display is scaled to fit it.
    var screens: [CGRect]
    /// A label above each screen, if any.
    var titles: [String]
    /// One rect per minimap.
    var panels: [CGRect]
    /// A line of text under everything, if any, with its baseline.
    var footnote: (text: String, baseline: CGFloat)?
    /// The centre of the key overlay.
    var overlay: CGPoint
    /// Label each minimap group with its workspace number.
    var numberGroups: Bool
    /// A note at the bottom left, beside the caption, if any.
    var note: String? = nil
}

struct Scene {
    var name: String
    var timeline: Timeline
    var placement: Placement
}

enum Scenes {
    static let all = ["strip", "widths", "versus", "workspaces"]

    static func make(_ name: String) -> Scene {
        switch name {
        case "strip": strip()
        case "widths": widths()
        case "versus": versus()
        case "workspaces": workspaces()
        default: fatalError("no scene \(name)")
        }
    }

    /// The display at its own size, 1 point to 1 pixel, with the minimap under it.
    static let single = Placement(
        screens: [CGRect(x: 204, y: 44, width: 1512, height: 982)],
        titles: [],
        panels: [CGRect(x: 204, y: 1052, width: 1512, height: 104)],
        footnote: nil,
        overlay: CGPoint(x: 960, y: 44 + 982 - 84),
        numberGroups: false)

    /// One workspace, five windows: new columns open beside the focused one, focus walks the strip and jumps to its
    /// ends, and the strip scrolls only as far as it must.
    static func strip() -> Scene {
        let desk = Desk(spaces: [Shipped.workspace()])
        desk.preset([1, 2, 3])
        let stage = Stage(desks: [desk], minis: [Mini(desk: desk, groups: [(0, 0)])])
        let timeline = stage.record([
            .open(4, hold: 1.2),
            .open(5, hold: 1.2),
            .key("alt-cmd-left"),
            .key("alt-cmd-left"),
            .key("alt-cmd-home", hold: 1.2),
            .key("alt-cmd-right"),
            .key("alt-cmd-end", hold: 1.2),
            .close(5),
            .close(4, hold: 1.2),
        ], lead: 0.7)
        return Scene(name: "strip", timeline: timeline, placement: single)
    }

    /// The focused column through the preset widths and back, maximised and given its width back, then centred.
    static func widths() -> Scene {
        let desk = Desk(spaces: [Shipped.workspace()])
        desk.preset([1, 2, 3])
        // Start on the middle column at a third of the screen, as two steps of column-width next leave it.
        desk.presetChange {
            $0.focus(.left)
            $0.cycleColumnWidth()
            $0.cycleColumnWidth()
        }
        let stage = Stage(desks: [desk], minis: [Mini(desk: desk, groups: [(0, 0)])])
        let timeline = stage.record([
            .key("alt-r"),
            .key("alt-r"),
            .key("alt-shift-r"),
            .key("alt-m", hold: 1.2),
            .key("alt-m"),
            .key("alt-c", hold: 1.2),
            .key("alt-shift-r"),
            .key("alt-l"),
            .key("alt-h", hold: 1.2),
        ], lead: 0.7)
        return Scene(name: "widths", timeline: timeline, placement: single)
    }

    /// The same five windows opened under Dinky's default layout and Splay's.
    static func versus() -> Scene {
        // Upstream's Config defaults to `tiles`; this fork's to the strip.
        let tilesKind = LayoutKind.tiles
        let stripKind = Shipped.config.defaultLayout
        precondition(stripKind == .scrolling, "Splay's default layout is no longer the strip")
        let left = Desk(spaces: [Shipped.workspace(tilesKind)])
        let right = Desk(spaces: [Shipped.workspace(stripKind)])
        let stage = Stage(desks: [left, right], minis: [Mini(desk: left, groups: [(0, 0)]), Mini(desk: right, groups: [(0, 0)])])
        var beats: [Beat] = (1...5).map { .open(WindowID($0), hold: $0 == 5 ? 2.0 : 1.15) }
        // Back to an empty desk, so the clip loops: every window fades out at once.
        beats.append(.quiet(hold: 0.8) { stage in
            for desk in stage.desks { desk.clearAll(fade: 0.35) }
        })
        let timeline = stage.record(beats, lead: 0.5)

        let scale: CGFloat = 0.59
        let size = CGSize(width: (1512 * scale).rounded(), height: (982 * scale).rounded())
        let gap: CGFloat = 40
        let x0 = ((1920 - 2 * size.width - gap) / 2).rounded()
        let top: CGFloat = 178
        let screens = [CGRect(origin: CGPoint(x: x0, y: top), size: size),
                       CGRect(origin: CGPoint(x: x0 + size.width + gap, y: top), size: size)]
        let panelTop = top + size.height + 34
        let placement = Placement(
            screens: screens,
            titles: ["Dinky's default (tiles)", "Splay's default (strip)"],
            panels: screens.map { CGRect(x: $0.minX, y: panelTop, width: $0.width, height: 92) },
            footnote: ("Both layouts ship in both apps. Only the default differs.", panelTop + 92 + 66),
            overlay: CGPoint(x: 960, y: 1090),
            numberGroups: false)
        return Scene(name: "versus", timeline: timeline, placement: placement)
    }

    /// Workspaces are native Spaces, each with its own strip: switch between them, send a window to another and back.
    static func workspaces() -> Scene {
        let desk = Desk(spaces: [Shipped.workspace(), Shipped.workspace()])
        desk.preset([1, 2, 3], in: 0)
        desk.preset([4, 5], in: 1)
        let mini = Mini(desk: desk, groups: [(0, 0), (1, 3000)])
        let stage = Stage(desks: [desk], minis: [mini])
        let timeline = stage.record([
            .key("ctrl-right", hold: 1.2),
            .key("ctrl-left", hold: 1.2),
            .key("alt-shift-2", hold: 1.3),
            .key("ctrl-right", hold: 1.3),
            .key("alt-shift-1", hold: 1.3),
            .key("ctrl-left", hold: 1.3),
        ], lead: 0.7)
        var placement = single
        placement.numberGroups = true
        placement.note = "Workspaces and their keys come from Dinky unchanged."
        return Scene(name: "workspaces", timeline: timeline, placement: placement)
    }
}

extension Desk {
    /// Every window fades out where it is, and each Space starts over as it was before any window.
    func clearAll(fade seconds: Double) {
        for i in spaces.indices {
            for id in spaces[i].windows { close(id, fade: seconds) }
            spaces[i] = blank[i]
        }
    }
}
