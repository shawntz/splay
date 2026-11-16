import AppKit
import DinkyLayout
import DinkyPrivate

// Splay: the reads behind RestoreKeeps, which decides what a restore makes of a window its own passes left without a
// verdict, and which journaled windows the menu offers to restore. This file reads the window server, the on-screen
// window list and whether each window's app is hidden, and records the verdicts. It makes no Accessibility call, moves
// no window and writes no frame. Main thread only.
extension Recovery {
    /// How many of `entries` a restore could reach now (`RestoreKeeps.reachable`). The menu's "Restore N windows from
    /// the previous session" and `recover` count only these, so a window its app closed and kept, journaled until it is
    /// open again, does not bring the item back at every launch.
    static func reachable(_ entries: [Entry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        let screen = Screen()
        return entries.filter { RestoreKeeps.reachable(screen.facts(of: $0)) }.count
    }

    /// Runs after the restore's own passes and before it maps what is left to problems, on the windows still without a
    /// verdict by the same test that mapping uses. One the window server has in place gets a result that counts as
    /// matched; one out of reach that Accessibility read nothing back for gets `RestoreProblem.notShowing`, which keeps
    /// it journaled. The rest are left as they are. Logs a line per window it decides on, and nothing when it decides none.
    func keepOutOfReach(_ live: [Entry], results: inout [UInt32: FrameResult], problems: inout [UInt32: RestoreProblem]) {
        let open = live.filter { results[$0.id]?.matched != true && problems[$0.id] == nil }
        guard !open.isEmpty else { return }
        let screen = Screen()
        for entry in open {
            let window = screen.facts(of: entry, answer: results[entry.id], problem: problems[entry.id])
            let verdict = RestoreKeeps.verdict(window)
            switch verdict {
            case .upstream: continue
            case .restored(let result): results[entry.id] = result
            case .kept: problems[entry.id] = RestoreKeeps.problem(for: window)
            }
            if let line = RestoreKeeps.line(window, verdict) { fputs("recovery: \(line)\n", stderr) }
        }
    }
}

/// What every window's facts share, read once: the on-screen window list and the Spaces the displays show.
private struct Screen {
    let onScreen = Set(onScreenOrder())
    let showing = Set(AppState.shared.displays.displays.map(\.currentSpaceID))

    func facts(of entry: Recovery.Entry, answer: FrameResult? = nil, problem: RestoreProblem? = nil) -> RestoreKeeps.Facts {
        let info = dinky_window_info(entry.id)
        let space = dinky_window_space_id(entry.id)
        // CoreGraphics' window list as a second read, so one failed SkyLight query does not count a window gone.
        let exists = (info.exists && info.pid == entry.pid) || windowPID(entry.id) == entry.pid
        return RestoreKeeps.Facts(id: entry.id, pid: entry.pid,
                                  journaled: WindowPosition(frame: entry.frame, spaceID: entry.spaceID),
                                  now: WindowPosition(frame: info.frame, spaceID: space), answer: answer, problem: problem,
                                  exists: exists, minimized: info.isMinimized,
                                  appHidden: NSRunningApplication(processIdentifier: entry.pid)?.isHidden ?? false,
                                  spaceShowing: showing.contains(space), onScreen: onScreen.contains(entry.id))
    }
}
