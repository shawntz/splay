import CoreGraphics
@testable import DinkyLayout

// Runs a scene's beats against one or more desks at 120 Hz and records every tick. The minimap is the engine's own
// strip (Workspace.stripView), animated on the same spring as the windows so the two move together.

/// The key overlay for one beat.
struct Overlay {
    var start: Double
    var end: Double
    var keys: [String]
    var label: String
    /// A Splay command, shown in monospace; otherwise something an app does, such as opening a window.
    var isCommand: Bool

    func alpha(at t: Double) -> Double {
        let fadeIn = 0.08, fadeOut = 0.2
        if t < start || t > end { return 0 }
        if t < start + fadeIn { return (t - start) / fadeIn }
        if t > end - fadeOut { return max(0, (end - t) / fadeOut) }
        return 1
    }
}

/// One thing that happens in a scene, with the overlay it shows and how long the scene waits after it.
struct Beat {
    var keys: [String]
    var label: String
    var isCommand: Bool
    var hold: Double
    var run: (Stage) -> Void

    /// A key bound in the shipped config, run on every desk.
    static func key(_ key: String, hold: Double = 1.1) -> Beat {
        Beat(keys: Shipped.keycaps(key), label: Shipped.commandText(for: key), isCommand: true, hold: hold) { stage in
            for desk in stage.desks { desk.press(key) }
        }
    }

    /// An app opens window `id` on every desk; the app tiles it a moment later.
    static func open(_ id: WindowID, hold: Double = 1.1) -> Beat {
        Beat(keys: ["⌘", "N"], label: "new window", isCommand: false, hold: hold) { stage in
            for desk in stage.desks { desk.open(id, at: spawnFrame(id)) }
            stage.after(0.1) { stage in for desk in stage.desks { desk.tile(id) } }
        }
    }

    /// An app closes window `id` on every desk.
    static func close(_ id: WindowID, hold: Double = 1.1) -> Beat {
        Beat(keys: ["⌘", "W"], label: "close window", isCommand: false, hold: hold) { stage in
            for desk in stage.desks { desk.close(id) }
        }
    }

    /// Something with no overlay.
    static func quiet(hold: Double, _ run: @escaping (Stage) -> Void) -> Beat {
        Beat(keys: [], label: "", isCommand: false, hold: hold, run: run)
    }

    /// Where an app puts a new window before it is tiled: centred, a little down and right for each new one.
    static func spawnFrame(_ id: WindowID) -> CGRect {
        let b = Shipped.bounds
        let size = CGSize(width: 860, height: 600)
        let step = CGFloat(Int(id) % 4) * 22
        return CGRect(x: (b.midX - size.width / 2 + step).rounded(), y: (b.minY + 120 + step).rounded(),
                      width: size.width, height: size.height)
    }
}

/// A minimap's items: each window's place along its workspace's strip, and the screen's.
struct MiniItem {
    var id: WindowID
    /// The index in `MiniShot.groups` of the workspace it is on.
    var group: Int
    var rect: CGRect
    var opacity: Double
    var focused: Bool
}

struct MiniShot {
    var items: [MiniItem]
    /// The screen's rect on each group's strip.
    var views: [(group: Int, rect: CGRect, current: Bool)]
    /// Each group's offset along the minimap, in points.
    var groups: [(space: Int, offset: CGFloat, current: Bool)]
    /// Where each group's content starts as the engine has it, not as it glides.
    var starts: [CGFloat]
}

/// One desk's minimap, in points along a line holding each shown Space's strip at its own offset.
final class Mini {
    let desk: Desk
    /// The Spaces shown, by index, with their offsets in points.
    let groups: [(space: Int, offset: CGFloat)]
    private var anims: [Int: FrameAnimation] = [:]
    private var rects: [Int: CGRect] = [:]
    private var fades: [Int: Fade] = [:]
    private var leaving: [(key: Int, rect: CGRect, fade: Fade)] = []
    private var groupOf: [Int: Int] = [:]
    private var starts: [CGFloat] = []
    private var now = 0.0

    init(desk: Desk, groups: [(space: Int, offset: CGFloat)]) {
        self.desk = desk
        self.groups = groups
    }

    /// What the engine says now, keyed by window ID, and by -1 - index for each group's screen.
    private func targets() -> [Int: CGRect] {
        var result: [Int: CGRect] = [:]
        for (i, group) in groups.enumerated() {
            let (frames, screen) = desk.spaces[group.space].stripView()
            for (id, frame) in frames {
                result[Int(id)] = frame.offsetBy(dx: group.offset, dy: 0)
                groupOf[Int(id)] = i
            }
            result[-1 - i] = screen.offsetBy(dx: group.offset, dy: 0)
        }
        return result
    }

    /// Follows the engine: new items appear where they belong, gone ones fade, the rest glide.
    func update(snap: Bool = false) {
        let goal = targets()
        starts = groups.indices.map { g in
            goal.filter { $0.key < 0 ? $0.key == -1 - g : groupOf[$0.key] == g }.map(\.value.minX).min() ?? groups[g].offset
        }
        for (key, rect) in rects where goal[key] == nil {
            leaving.append((key, rect, Fade(from: 1, to: 0, start: now, duration: 0.14)))
            rects[key] = nil
            anims[key] = nil
        }
        // A workspace left with no windows shows its screen where an empty strip has it, without a glide.
        let empty = Set(groups.indices.filter { g in !goal.keys.contains { $0 >= 0 && groupOf[$0] == g } }.map { -1 - $0 })
        for (key, target) in goal {
            if snap || rects[key] == nil || empty.contains(key) {
                if rects[key] == nil && !snap && key >= 0 { fades[key] = Fade(from: 0, to: 1, start: now, duration: 0.14) }
                rects[key] = target
                anims[key] = nil
            } else if anims[key] != nil {
                anims[key]!.retarget(target)
            } else if rects[key] != target {
                anims[key] = FrameAnimation(from: rects[key]!, to: target)
            }
        }
    }

    func step(_ dt: Double) {
        now += dt
        for key in anims.keys.sorted() {
            let done = anims[key]!.step(desk.spring, dt: dt, timeout: desk.timeout)
            rects[key] = anims[key]!.frame
            if done { anims[key] = nil }
        }
        leaving.removeAll { $0.fade.done(at: now) }
        for (key, fade) in fades where fade.done(at: now) { fades[key] = nil }
    }

    func shot() -> MiniShot {
        var items: [MiniItem] = []
        for (key, rect) in rects where key >= 0 {
            items.append(MiniItem(id: WindowID(key), group: groupOf[key] ?? 0, rect: rect,
                                  opacity: fades[key]?.value(at: now) ?? 1, focused: WindowID(key) == desk.keyboard))
        }
        for gone in leaving where gone.key >= 0 {
            items.append(MiniItem(id: WindowID(gone.key), group: groupOf[gone.key] ?? 0, rect: gone.rect,
                                  opacity: gone.fade.value(at: now), focused: false))
        }
        items.sort { $0.id < $1.id }
        let views = groups.indices.compactMap { i -> (group: Int, rect: CGRect, current: Bool)? in
            rects[-1 - i].map { (i, $0, groups[i].space == desk.shown) }
        }
        return MiniShot(items: items, views: views,
                        groups: groups.map { ($0.space, $0.offset, $0.space == desk.shown) }, starts: starts)
    }
}

/// One recorded tick.
struct Tick {
    var screens: [ScreenShot]
    var minis: [MiniShot]
}

struct Timeline {
    static let rate = 120.0
    var ticks: [Tick]
    var overlays: [Overlay]
    var duration: Double

    func tick(at t: Double) -> Tick {
        ticks[min(max(Int((t * Self.rate).rounded()), 0), ticks.count - 1)]
    }
}

final class Stage {
    let desks: [Desk]
    let minis: [Mini]
    private(set) var now = 0.0
    private var pending: [(at: Double, run: (Stage) -> Void)] = []

    init(desks: [Desk], minis: [Mini]) {
        self.desks = desks
        self.minis = minis
        for mini in minis { mini.update(snap: true) }
    }

    func after(_ seconds: Double, _ run: @escaping (Stage) -> Void) {
        pending.append((now + seconds, run))
    }

    private func step() {
        let dt = 1 / Timeline.rate
        now += dt
        for desk in desks { desk.step(dt) }
        for mini in minis { mini.step(dt) }
    }

    /// Runs whatever is due, oldest first. True if anything ran.
    private func runDue() -> Bool {
        var ran = false
        while let i = pending.indices.min(by: { pending[$0].at < pending[$1].at }), pending[i].at <= now + 1e-9 {
            let job = pending.remove(at: i)
            job.run(self)
            ran = true
        }
        if ran { for mini in minis { mini.update() } }
        return ran
    }

    private var signature: String { desks.map { $0.signature() }.joined(separator: " | ") }

    private func settle() {
        var guardTicks = 0
        while desks.contains(where: \.isMoving) || !pending.isEmpty {
            _ = runDue()
            step()
            guardTicks += 1
            precondition(guardTicks < 120 * 120, "the scene never settles")
        }
        for mini in minis { mini.update(snap: true) }
    }

    /// Plays `beats` once unrecorded, so the clip starts where it ends, then again recorded. The first beat comes
    /// `lead` seconds in; the clip lasts until the last beat's hold is over, rounded up to a fifth of a second so
    /// every frame rate in use divides it.
    func record(_ beats: [Beat], lead: Double) -> Timeline {
        let schedule = { (start: Double) in
            var t = start
            for beat in beats {
                self.pending.append((t, beat.run))
                t += beat.hold
            }
            return t
        }
        _ = schedule(now + lead)
        settle()
        let start = signature

        let origin = now
        var overlays: [Overlay] = []
        var t = lead
        for beat in beats {
            if !beat.keys.isEmpty {
                overlays.append(Overlay(start: t, end: t + max(beat.hold - 0.08, 0.5), keys: beat.keys, label: beat.label,
                                        isCommand: beat.isCommand))
            }
            t += beat.hold
        }
        let duration = (t * 5).rounded(.up) / 5
        _ = schedule(origin + lead)
        var ticks: [Tick] = []
        let count = Int((duration * Timeline.rate).rounded())
        for _ in 0..<count {
            _ = runDue()
            ticks.append(Tick(screens: desks.map { $0.shot() }, minis: minis.map { $0.shot() }))
            step()
        }
        _ = runDue()
        let still = !desks.contains(where: \.isMoving)
        let end = signature
        if start != end || !still {
            print("warning: the clip does not end where it began\n  start: \(start)\n  end:   \(end)\n  still: \(still)")
        } else {
            print("  loop closes: \(end)")
        }
        return Timeline(ticks: ticks, overlays: overlays, duration: duration)
    }
}
