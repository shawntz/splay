import DinkyCommands
import DinkyLayout

// The scrolling strip's commands, on the focused window's workspace. In another layout they have nothing to do
// and say so, as swap-with-master does outside a master layout.
extension Dispatcher {
    /// `window` stands in for the focused window, as a rule supplies it: the column changed is that window's.
    static func strip(_ command: Command, window: WindowID? = nil,
                      coordinator: Coordinator? = AppState.shared.coordinator) -> Reply {
        guard let coordinator else { return .error("tiling is not running") }
        let outcome = coordinator.strip(command, window: window)
        // As `focus` does: the tree moved first, then the window found gets the keyboard.
        if case .focus(let id) = outcome { return focus(window: id) }
        return reply(to: command, outcome, window: window) ?? .ok("")
    }

    /// The reply for what a strip command came to. Nil for `focus-column` finding a window, which `focus` answers.
    static func reply(to command: Command, _ outcome: StripOutcome, window: WindowID?) -> Reply? {
        switch outcome {
        case .notStrip: .error("\(command) is not a strip command")
        case .notTiled(let name): .error("\(name): \(window.map { "window \($0)" } ?? "the focused window") is not tiled")
        case .nothing(let name): .ok("\(name): nothing to do")
        case .changed(let name): .ok(name)
        case .focus: nil
        }
    }

    /// The name replies give a strip command, and what it does to the workspace: false when there was nothing
    /// to do. Nil for any other command.
    static func stripChange(_ command: Command) -> (name: String, change: (inout Workspace) -> Bool)? {
        switch command {
        case .centerColumn:
            ("center-column", { $0.centerColumn() })
        case .columnWidth(.next):
            ("column-width next", { $0.cycleColumnWidth() })
        case .columnWidth(.prev):
            ("column-width prev", { $0.cycleColumnWidth(backward: true) })
        case .columnWidth(.share(let share)):
            ("column-width \(share)", { $0.setColumnWidth(share) })
        case .maximizeColumn:
            ("maximize-column", { $0.toggleMaximizeColumn() })
        case .focusColumn(let end):
            // focusEdge also finds the edge window of a tree, which has no columns.
            ("focus-column \(end.rawValue)", { $0.isScrolling && $0.focusEdge(end == .first ? .left : .right) })
        default:
            nil
        }
    }
}

/// What a strip command came to, before the reply is worded.
enum StripOutcome: Equatable {
    case notStrip
    case notTiled(String)
    case nothing(String)
    case changed(String)
    /// `focus-column` found this window for the keyboard to go to.
    case focus(WindowID)
}

extension Coordinator {
    /// Runs a strip command on the tree of `window`, or with none on the command window's.
    func strip(_ command: Command, window: WindowID? = nil) -> StripOutcome {
        guard let (name, change) = Dispatcher.stripChange(command) else { return .notStrip }
        if case .focusColumn = command {
            cancelRefocus()
            switch self.command(on: window, { change(&$0) ? $0.focused : nil }) {
            case nil: return .notTiled(name)
            case .some(nil): return .nothing(name)
            case .some(let id?): return .focus(id)
            }
        }
        // A width for a rule's window is no reason to look at that window. `command(on:)` focuses it in its tree,
        // which scrolls the strip to it, so the tree's focus then goes back to the window that had it, the one the
        // keyboard is on. Centring a column is asking to see it, and stays there.
        let resumes = window.flatMap { placements[$0]?.space }.flatMap { workspaces[$0]?.focused }
        var staysThere = false
        if case .centerColumn = command { staysThere = true }
        let changed = self.command(on: window) { workspace -> Bool in
            let changed = change(&workspace)
            if !staysThere, let resumes, resumes != window { workspace.focus(resumes) }
            return changed
        }
        switch changed {
        case nil: return .notTiled(name)
        case false?: return .nothing(name)
        case true?: return .changed(name)
        }
    }
}
