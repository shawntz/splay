import CoreGraphics

// Splay: what a restore makes of a journaled window its own passes left without a verdict. A window its app closed and
// kept (Slack, ChatGPT and Spotify keep one after Cmd-W) has no Accessibility element, so the restore writes it, reads
// nothing back and would drop it as unreadable, forgetting its original frame. Such a window, and any other that still
// exists but is out of reach, is kept instead, to be put back once it can be reached. A window the window server already
// has at its original frame and Space counts as restored, whatever Accessibility said. Every other window is the
// restore's to decide, as before. This only classifies: nothing here, or in Sources/dinky/RecoveryKeeps.swift, which
// reads the facts, moves a window or writes a frame.

public enum RestoreKeeps {
    /// One journaled window, as the window server and the restore's passes left it.
    public struct Facts: Equatable, Sendable {
        public let id: WindowID
        public let pid: Int32
        /// Where it was before Splay tiled it. Space 0 when that was not known.
        public let journaled: WindowPosition
        /// Where the window server has it now. Space 0 when it is on none.
        public let now: WindowPosition
        /// The restore's readback, nil when its app did not answer.
        public let answer: FrameResult?
        /// What the restore already found wrong with it, nil when nothing.
        public let problem: RestoreProblem?
        /// The window server still has it, owned by the same app, by either of two reads.
        public let exists: Bool
        /// Tagged minimized by the window server, as a window its app closed and kept is.
        public let minimized: Bool
        public let appHidden: Bool
        /// Its Space is one a display shows.
        public let spaceShowing: Bool
        /// In the on-screen window list.
        public let onScreen: Bool

        public init(id: WindowID, pid: Int32, journaled: WindowPosition, now: WindowPosition, answer: FrameResult?,
                    problem: RestoreProblem?, exists: Bool, minimized: Bool, appHidden: Bool, spaceShowing: Bool,
                    onScreen: Bool) {
            self.id = id
            self.pid = pid
            self.journaled = journaled
            self.now = now
            self.answer = answer
            self.problem = problem
            self.exists = exists
            self.minimized = minimized
            self.appHidden = appHidden
            self.spaceShowing = spaceShowing
            self.onScreen = onScreen
        }
    }

    /// Why Accessibility cannot reach a window that still exists, in the order they are checked.
    public enum Reason: String, Equatable, Sendable, CustomStringConvertible {
        case minimized = "the window server has it minimized, as it does a window its app closed and kept"
        case appHidden = "its app is hidden"
        case onNoSpace = "it is on no Space"
        case spaceNotShowing = "no display is showing its Space"
        case notOnScreen = "it is not drawn on screen"

        public var description: String { rawValue }
    }

    public enum Verdict: Equatable, Sendable {
        /// Left to the restore, which maps it as it always has.
        case upstream
        /// At its journaled frame and Space: restored, with a result that counts as matched.
        case restored(FrameResult)
        /// Kept as `RestoreProblem.notShowing`, which retries.
        case kept(Reason)
    }

    /// Why nothing can reach the window now, nil when something can.
    public static func outOfReach(_ window: Facts) -> Reason? {
        if window.minimized { return .minimized }
        if window.appHidden { return .appHidden }
        if window.now.spaceID == 0 { return .onNoSpace }
        if !window.spaceShowing { return .spaceNotShowing }
        return window.onScreen ? nil : .notOnScreen
    }

    /// A window with a problem, read back at its frame, or gone is the restore's. One the window server has within 2 pt
    /// of its journaled frame, on its journaled Space unless that is not known, is restored. One Accessibility read
    /// nothing back for (a readback with no frame) that is out of reach is kept. The rest are the restore's.
    public static func verdict(_ window: Facts) -> Verdict {
        guard window.problem == nil, window.answer?.matched != true, window.exists else { return .upstream }
        let journaled = window.journaled
        if journaled.spaceID == 0 || window.now.spaceID == journaled.spaceID,
           window.now.frame.isClose(to: journaled.frame, within: 2) {
            let job = FrameJob(pid: window.pid, id: window.id, frame: journaled.frame)
            return .restored(FrameResult(job: job, target: journaled.frame, got: window.now.frame))
        }
        if let answer = window.answer, answer.got == nil, let reason = outOfReach(window) { return .kept(reason) }
        return .upstream
    }

    /// The problem a kept window gets. It retries, so the window's entry, and with it its original frame, stays in the
    /// journal until a restore can reach the window.
    public static func problem(for window: Facts) -> RestoreProblem {
        .notShowing(wanted: window.journaled.frame)
    }

    /// Whether a restore now could reach the window, for the menu's count of windows to restore: it exists and is not
    /// out of reach. A window on a Space no display shows counts, as Accessibility reaches those.
    public static func reachable(_ window: Facts) -> Bool {
        guard window.exists else { return false }
        let reason = outOfReach(window)
        return reason == nil || reason == .spaceNotShowing
    }

    /// The log line for a verdict, nil for a window left to the restore.
    public static func line(_ window: Facts, _ verdict: Verdict) -> String? {
        let head = "window \(window.id) (Space \(window.now.spaceID)): "
        switch verdict {
        case .upstream:
            return nil
        case .restored:
            let said = window.answer.map { $0.got.map { "Accessibility read back \($0)" } ?? "Accessibility read nothing back" }
                ?? "its app did not answer"
            return head + "\(said), but the window server has it at \(window.now.frame), within 2 pt of its original "
                + "frame \(window.journaled.frame), so it counts as restored"
        case .kept(let reason):
            return head + "Accessibility read nothing back and \(reason), so its original frame \(window.journaled.frame) "
                + "stays in the journal to try again"
        }
    }
}
