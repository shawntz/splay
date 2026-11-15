import CoreGraphics
import DinkyCommands
import DinkyConfig
@testable import DinkyLayout

// One display and its workspaces, driven the way the app drives them: each command runs on the focused window's
// tree as Coordinator.command(on:) runs it, and windows glide to their tiles on the app's own spring
// (FrameAnimation), stepped at 120 Hz as on a 14-inch MacBook Pro. A Space that is not on screen is laid out when it
// shows, without a glide, as Coordinator.spacesShown does.

/// An opacity changing over time.
struct Fade {
    var from: Double, to: Double, start: Double, duration: Double

    func value(at t: Double) -> Double {
        guard duration > 0 else { return to }
        let p = min(max((t - start) / duration, 0), 1)
        let eased = p * p * (3 - 2 * p)
        return from + (to - from) * eased
    }

    func done(at t: Double) -> Bool { t >= start + duration }
}

/// A window drawn without a tile: one opening before it is tiled, or one leaving (closed, or sent to another Space).
struct Loose {
    var id: WindowID
    var frame: CGRect
    var space: Int
    var fade: Fade
    var border: Bool
}

/// A window as drawn on one frame.
struct WindowShot {
    var id: WindowID
    var frame: CGRect
    var opacity: Double
    /// Nil while the border is hidden: during a glide that changes the window's size, as BorderWindow hides it.
    var border: CGColor?
    var focused: Bool
}

/// What one display shows on one frame.
struct ScreenShot {
    /// Back to front, by Space: during a Space switch both are shown, offset.
    var layers: [(space: Int, dx: Double, windows: [WindowShot])]
    var workspaceNumber: Int
}

final class Desk {
    var spaces: [Workspace]
    private(set) var shown = 0
    private(set) var now = 0.0

    private(set) var frames: [WindowID: CGRect] = [:]
    private var anims: [WindowID: FrameAnimation] = [:]
    /// The size each window's border was last drawn at.
    private var borderSize: [WindowID: CGSize] = [:]
    /// Each Space's windows front to back, as the app raises them into the tree's order.
    private var stacking: [Int: [WindowID]] = [:]
    private(set) var loose: [Loose] = []
    private var fadesIn: [WindowID: Fade] = [:]
    /// The window with the keyboard, whose border is the active colour.
    private(set) var keyboard: WindowID?
    /// Spaces whose tree changed while they were not on screen.
    private var dirty: Set<Int> = []
    /// A Space switch in progress.
    private var slide: (from: Int, to: Int, start: Double)?
    /// How long a Space switch slides. See Desk.switchSpace.
    static let slideSeconds = 0.12
    let spring = Shipped.spring
    let timeout = Shipped.timeout

    /// Each Space as it was before any window, for starting over.
    let blank: [Workspace]

    init(spaces: [Workspace]) {
        self.spaces = spaces
        blank = spaces
    }

    // MARK: Setting up, before the clip starts

    /// Puts windows straight into Space `space`'s tree, on their tiles, as if they had been there all along.
    func preset(_ ids: [WindowID], in space: Int = 0) {
        for id in ids { spaces[space].insert(id) }
        settle(space)
    }

    /// Runs an engine change with no glide.
    func presetChange(in space: Int = 0, _ change: (inout Workspace) -> Void) {
        change(&spaces[space])
        settle(space)
    }

    private func settle(_ space: Int) {
        let layout = spaces[space].layout()
        for (id, frame) in layout.frames {
            frames[id] = frame
            borderSize[id] = frame.size
            anims[id] = nil
        }
        stacking[space] = layout.order
        if space == shown { keyboard = spaces[space].focused }
    }

    // MARK: Commands

    /// What a key bound in the shipped config does, as the app's dispatcher runs it.
    func press(_ key: String) {
        for command in Shipped.commands(for: key) { perform(command) }
    }

    private func perform(_ command: Command) {
        switch command {
        case .focus(let direction, _, _):
            treeCommand { $0.focus(direction) }
        case .focusColumn(let end):
            // StripCommands.swift: focus-column only acts in the strip.
            treeCommand { $0.isScrolling && $0.focusEdge(end == .first ? .left : .right) }
        case .columnWidth(.next):
            treeCommand { $0.cycleColumnWidth() }
        case .columnWidth(.prev):
            treeCommand { $0.cycleColumnWidth(backward: true) }
        case .columnWidth(.share(let share)):
            treeCommand { $0.setColumnWidth(share) }
        case .maximizeColumn:
            treeCommand { $0.toggleMaximizeColumn() }
        case .centerColumn:
            treeCommand { $0.centerColumn() }
        case .workspace(let target):
            switchSpace(to: resolve(target))
        case .moveWindowToWorkspace(let target, let follow):
            precondition(!follow, "the demo moves windows without following them")
            moveFocusedWindow(to: resolve(target))
        default:
            fatalError("the demo does not drive \(command)")
        }
    }

    private func resolve(_ target: WorkspaceTarget) -> Int {
        switch target {
        case .number(let n): return n - 1
        case .next: return shown + 1
        case .prev: return shown - 1
        }
    }

    /// Coordinator.command(on:): focus the focused window in its tree, run the change, apply what changed, and give
    /// the keyboard to the window the tree focuses.
    private func treeCommand(_ change: (inout Workspace) -> Bool) {
        if let focused = spaces[shown].focused { spaces[shown].focus(focused) }
        _ = change(&spaces[shown])
        apply(shown)
        keyboard = spaces[shown].focused
    }

    // MARK: Windows coming and going

    /// A window an app opens at `frame`. The app tiles it `classify` seconds later, into a new column beside the
    /// focused window of the Space on screen.
    func open(_ id: WindowID, at frame: CGRect) {
        frames[id] = frame
        borderSize[id] = frame.size
        fadesIn[id] = Fade(from: 0, to: 1, start: now, duration: 0.12)
        loose.append(Loose(id: id, frame: frame, space: shown, fade: Fade(from: 1, to: 1, start: now, duration: 0), border: true))
        keyboard = id
    }

    /// The window opened with `open` is tiled: Coordinator.place inserts it into the tree.
    func tile(_ id: WindowID) {
        loose.removeAll { $0.id == id }
        spaces[shown].insert(id)
        apply(shown)
        keyboard = spaces[shown].focused
    }

    /// A window closes: its tree drops it, and the app's refocus gives the keyboard to the tree's next window.
    func close(_ id: WindowID, fade seconds: Double = 0.14) {
        guard let space = spaces.firstIndex(where: { $0.contains(id) }) else { return }
        let frame = frames[id]!
        spaces[space].remove(id)
        anims[id] = nil
        loose.append(Loose(id: id, frame: frame, space: space, fade: Fade(from: 1, to: 0, start: now, duration: seconds),
                           border: borderSize[id] == frame.size))
        frames[id] = nil
        borderSize[id] = nil
        apply(space)
        if space == shown { keyboard = spaces[space].focused }
    }

    /// move-window-to-workspace without --follow: the window leaves this Space's tree for the other's, and the
    /// keyboard goes to the window that took its place here (Dispatcher.relocate, Coordinator.windowMoved).
    private func moveFocusedWindow(to target: Int) {
        if let focused = spaces[shown].focused { spaces[shown].focus(focused) }
        guard let id = keyboard, spaces[shown].contains(id), target != shown, spaces.indices.contains(target) else { return }
        let frame = frames[id]!
        spaces[shown].remove(id)
        anims[id] = nil
        loose.append(Loose(id: id, frame: frame, space: shown, fade: Fade(from: 1, to: 0, start: now, duration: 0.12),
                           border: borderSize[id] == frame.size))
        apply(shown)
        spaces[target].insert(id)
        apply(target)
        keyboard = spaces[shown].focused
    }

    /// `workspace N`: the display switches to the Space, which shows its tree as it was left, or laid out at once if
    /// it changed meanwhile, and its focused window takes the keyboard.
    ///
    /// Splay switches Spaces with a synthetic Dock swipe. On macOS 27 it is sent fast enough that macOS skips the
    /// slide; before 27 the slide takes 60 to 120 ms. The demo shows a 120 ms slide so the direction reads.
    private func switchSpace(to target: Int) {
        guard target != shown, spaces.indices.contains(target) else { return }
        if Self.slideSeconds > 0 { slide = (shown, target, now) }
        shown = target
        if dirty.remove(target) != nil { settle(target) }
        keyboard = spaces[target].focused
    }

    // MARK: Applying a tree

    /// Coordinator.apply and Animator.animate: windows glide from where they are to their tiles, a glide in flight
    /// is retargeted, and a Space that is not on screen waits until it shows.
    private func apply(_ space: Int) {
        let layout = spaces[space].layout()
        stacking[space] = layout.order
        guard space == shown else {
            dirty.insert(space)
            return
        }
        for (id, target) in layout.frames {
            if anims[id] != nil {
                anims[id]!.retarget(target)
            } else if let start = frames[id], !start.isClose(to: target, within: 1) {
                anims[id] = FrameAnimation(from: start, to: target)
            } else {
                frames[id] = target
                borderSize[id] = target.size
            }
        }
    }

    // MARK: Time

    /// Advances everything by `dt` seconds.
    func step(_ dt: Double) {
        now += dt
        for id in anims.keys.sorted() {
            let done = anims[id]!.step(spring, dt: dt, timeout: timeout)
            frames[id] = anims[id]!.frame
            if done {
                anims[id] = nil
                // Animator.onArrive: the border catches up with the size it skipped.
                borderSize[id] = frames[id]!.size
            }
        }
        loose.removeAll { $0.fade.to == 0 && $0.fade.done(at: now) }
        for (id, fade) in fadesIn where fade.done(at: now) { fadesIn[id] = nil }
        if let slide, now >= slide.start + Self.slideSeconds { self.slide = nil }
    }

    /// Whether any window is still gliding or fading.
    var isMoving: Bool { !anims.isEmpty || !fadesIn.isEmpty || loose.contains { $0.fade.to == 0 } || slide != nil }

    // MARK: Drawing

    func shot() -> ScreenShot {
        var layers: [(space: Int, dx: Double, windows: [WindowShot])] = []
        if let slide {
            let p = min(max((now - slide.start) / Self.slideSeconds, 0), 1)
            let eased = 1 - pow(1 - p, 3)
            let width = Double(Shipped.display.width)
            let sign: Double = slide.to > slide.from ? 1 : -1
            layers.append((slide.from, -sign * eased * width, windows(of: slide.from)))
            layers.append((slide.to, sign * (1 - eased) * width, windows(of: slide.to)))
        } else {
            layers.append((shown, 0, windows(of: shown)))
        }
        return ScreenShot(layers: layers, workspaceNumber: shown + 1)
    }

    /// Back to front: the tree's stacking reversed, then windows without a tile on top.
    private func windows(of space: Int) -> [WindowShot] {
        var result: [WindowShot] = []
        for id in (stacking[space] ?? []).reversed() where spaces[space].contains(id) {
            guard let frame = frames[id] else { continue }
            let showsBorder = borderSize[id] == frame.size
            result.append(WindowShot(id: id, frame: frame, opacity: fadesIn[id]?.value(at: now) ?? 1,
                                     border: showsBorder ? color(id) : nil, focused: id == keyboard))
        }
        for window in loose where window.space == space {
            let frame = window.fade.to == 0 ? window.frame : (frames[window.id] ?? window.frame)
            let opacity = window.fade.to == 0 ? window.fade.value(at: now) : (fadesIn[window.id]?.value(at: now) ?? 1)
            result.append(WindowShot(id: window.id, frame: frame, opacity: opacity,
                                     border: window.border ? color(window.id) : nil, focused: window.id == keyboard))
        }
        return result
    }

    private func color(_ id: WindowID) -> CGColor {
        id == keyboard ? Shipped.activeBorder : Shipped.inactiveBorder
    }

    /// The engine's targets, for checking that a clip ends where it began.
    func signature() -> String {
        spaces.enumerated().map { i, w in
            let layout = w.layout()
            let frames = layout.frames.keys.sorted().map { "\($0)=\(layout.frames[$0]!)" }.joined(separator: ",")
            return "space\(i + 1)[focus=\(w.focused.map(String.init) ?? "-") \(frames)]"
        }.joined(separator: " ") + " shown=\(shown + 1) keyboard=\(keyboard.map(String.init) ?? "-")"
    }
}
