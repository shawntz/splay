import CoreGraphics
import Testing
@testable import DinkyLayout

// Splay: what a restore makes of a window its own passes left without a verdict. The incident's numbers: Slack's
// window 16297, journaled full screen on Space 1, closed with Cmd-W at its tile and kept by Slack.

private let full = rect(0, 33, 1512, 949)
private let tiled = rect(1487, 41, 704, 933)

private func readback(got: CGRect?) -> FrameResult {
    FrameResult(job: FrameJob(pid: 1, id: 1, frame: full), target: full, got: got, written: true)
}

/// A window that exists, on screen on the showing Space 1 at its tile, journaled at `full` on Space 1, that the restore
/// wrote and read nothing back for. `answer: .some(nil)` is an app that did not answer.
private func window(_ id: WindowID = 1, on space: UInt64 = 1, at frame: CGRect = tiled, journaled: UInt64 = 1,
                    minimized: Bool = false, appHidden: Bool = false, showing: Bool = true, onScreen: Bool = true,
                    answer: FrameResult?? = nil, problem: RestoreProblem? = nil, exists: Bool = true) -> RestoreKeeps.Facts {
    RestoreKeeps.Facts(id: id, pid: 1, journaled: WindowPosition(frame: full, spaceID: journaled),
                       now: WindowPosition(frame: frame, spaceID: space), answer: answer ?? readback(got: nil),
                       problem: problem, exists: exists, minimized: minimized, appHidden: appHidden,
                       spaceShowing: showing, onScreen: onScreen)
}

private func verdict(_ window: RestoreKeeps.Facts) -> RestoreKeeps.Verdict { RestoreKeeps.verdict(window) }

private func restored(_ window: RestoreKeeps.Facts) -> Bool {
    if case .restored(let result) = verdict(window) { result.matched } else { false }
}

struct RestoreKeepsVerdictTests {
    @Test func `The incident: a window its app closed and kept is kept, with its original frame`() {
        let closed = window(16297, minimized: true, onScreen: false)
        #expect(verdict(closed) == .kept(.minimized))
        #expect(RestoreKeeps.line(closed, verdict(closed)) == "window 16297 (Space 1): Accessibility read nothing back "
            + "and the window server has it minimized, as it does a window its app closed and kept, so its original "
            + "frame (0.0, 33.0, 1512.0, 949.0) stays in the journal to try again")
    }

    @Test func `Each reason alone keeps a window Accessibility read nothing back for`() {
        #expect(RestoreKeeps.outOfReach(window()) == nil)
        #expect(verdict(window(minimized: true)) == .kept(.minimized))
        #expect(verdict(window(appHidden: true)) == .kept(.appHidden))
        #expect(verdict(window(on: 0)) == .kept(.onNoSpace))
        #expect(verdict(window(on: 45, journaled: 45, showing: false)) == .kept(.spaceNotShowing))
        #expect(verdict(window(onScreen: false)) == .kept(.notOnScreen))
    }

    @Test func `With several reasons the first is named`() {
        #expect(verdict(window(on: 45, journaled: 45, minimized: true, appHidden: true, showing: false, onScreen: false))
                == .kept(.minimized), "closed and kept on a Desktop not showing, its app hidden too")
        #expect(verdict(window(on: 0, appHidden: true, onScreen: false)) == .kept(.appHidden))
        #expect(verdict(window(on: 0, showing: false, onScreen: false)) == .kept(.onNoSpace))
        #expect(verdict(window(on: 45, journaled: 45, showing: false, onScreen: false)) == .kept(.spaceNotShowing))
    }

    @Test func `A window on screen on a showing Desktop that could not be read is the restore's, to drop as unreadable`() {
        #expect(verdict(window()) == .upstream)
        #expect(RestoreKeeps.line(window(), .upstream) == nil, "nothing logged")
    }

    @Test func `A window read back at another frame, or whose app did not answer, is the restore's even out of reach`() {
        #expect(verdict(window(minimized: true, answer: readback(got: tiled))) == .upstream)
        #expect(verdict(window(on: 0, appHidden: true, onScreen: false, answer: readback(got: tiled))) == .upstream)
        #expect(verdict(window(minimized: true, answer: .some(nil))) == .upstream)
        #expect(verdict(window(on: 45, journaled: 45, showing: false, onScreen: false, answer: .some(nil))) == .upstream)
    }

    @Test func `A window with a problem already keeps it, in place or out of reach`() {
        #expect(verdict(window(minimized: true, onScreen: false, problem: .didNotArrive)) == .upstream)
        #expect(verdict(window(at: full, problem: .spaceMoveFailed)) == .upstream)
        #expect(verdict(window(on: 45, journaled: 45, showing: false, problem: .spaceGone)) == .upstream)
    }

    @Test func `A window read back at its frame, or gone, is the restore's`() {
        #expect(verdict(window(at: full, answer: readback(got: full))) == .upstream, "the restore's own result stands")
        #expect(verdict(window(minimized: true, onScreen: false, exists: false)) == .upstream)
        #expect(verdict(window(at: full, exists: false)) == .upstream)
    }

    @Test func `A kept window's problem retries and carries its original frame`() {
        let kept = window(minimized: true, onScreen: false)
        #expect(RestoreKeeps.problem(for: kept) == .notShowing(wanted: full))
        #expect(RestoreKeeps.problem(for: kept).retries, "or the journal would forget the window")
    }

    @Test func `The window server's frame and Space count as restored whatever Accessibility said`() {
        let near = rect(1, 34, 1512, 949)
        guard case .restored(let result) = verdict(window(at: near)) else { Issue.record("not restored"); return }
        #expect(result.matched && result.target == full && result.got == near && result.job.id == 1)
        #expect(restored(window(at: full, minimized: true, onScreen: false)), "closed and kept, already back")
        #expect(restored(window(at: full, answer: readback(got: tiled))), "another frame read back")
        #expect(restored(window(at: full, answer: .some(nil))), "its app did not answer")
        #expect(restored(window(on: 45, at: full, journaled: 45, showing: false, onScreen: false)), "a Desktop not showing")
    }

    @Test func `In place is within 2 pt on every edge, and not past it`() {
        for frame in [rect(2, 35, 1512, 949), rect(-2, 31, 1512, 949), rect(0, 33, 1514, 951), rect(0, 33, 1510, 947)] {
            #expect(restored(window(at: frame)), "\(frame)")
        }
        for frame in [rect(2.5, 33, 1512, 949), rect(0, 30.5, 1512, 949), rect(0, 33, 1514.5, 949), rect(0, 33, 1512, 946.5)] {
            #expect(verdict(window(at: frame)) == .upstream, "\(frame)")
            #expect(verdict(window(at: frame, minimized: true)) == .kept(.minimized), "\(frame)")
        }
    }

    @Test func `In place needs its journaled Space, unless that is not known`() {
        #expect(verdict(window(on: 1, at: full, journaled: 45)) == .upstream, "right frame, another Space")
        #expect(verdict(window(on: 1, at: full, journaled: 45, minimized: true)) == .kept(.minimized))
        #expect(verdict(window(on: 0, at: full, journaled: 45)) == .kept(.onNoSpace))
        #expect(restored(window(on: 45, at: full, journaled: 0, showing: false)))
        #expect(restored(window(on: 0, at: full, journaled: 0)))
    }

    @Test func `A window counted restored says what Accessibility said and where the window server has it`() {
        let f = "(0.0, 33.0, 1512.0, 949.0)", near = rect(1, 34, 1512, 949)
        let tail = "but the window server has it at (1.0, 34.0, 1512.0, 949.0), within 2 pt of its original frame \(f), "
            + "so it counts as restored"
        func line(_ w: RestoreKeeps.Facts) -> String? { RestoreKeeps.line(w, verdict(w)) }
        #expect(line(window(7, at: near)) == "window 7 (Space 1): Accessibility read nothing back, " + tail)
        #expect(line(window(7, at: near, answer: readback(got: tiled)))
                == "window 7 (Space 1): Accessibility read back (1487.0, 41.0, 704.0, 933.0), " + tail)
        #expect(line(window(7, at: near, answer: .some(nil))) == "window 7 (Space 1): its app did not answer, " + tail)
    }

    @Test func `Each reason reads plainly in the log`() {
        func line(_ w: RestoreKeeps.Facts) -> String? { RestoreKeeps.line(w, verdict(w)) }
        let tail = ", so its original frame (0.0, 33.0, 1512.0, 949.0) stays in the journal to try again"
        #expect(line(window(appHidden: true)) == "window 1 (Space 1): Accessibility read nothing back and its app is hidden" + tail)
        #expect(line(window(on: 0)) == "window 1 (Space 0): Accessibility read nothing back and it is on no Space" + tail)
        #expect(line(window(on: 45, journaled: 45, showing: false))
                == "window 1 (Space 45): Accessibility read nothing back and no display is showing its Space" + tail)
        #expect(line(window(onScreen: false)) == "window 1 (Space 1): Accessibility read nothing back and it is not drawn on screen" + tail)
    }
}

struct RestoreKeepsMenuTests {
    @Test func `The menu counts a window that exists and is in reach, whatever the last restore read back`() {
        #expect(RestoreKeeps.reachable(window()))
        #expect(RestoreKeeps.reachable(window(answer: .some(nil))))
        #expect(RestoreKeeps.reachable(window(at: full, answer: readback(got: full))))
    }

    @Test func `A window on a Desktop that is not showing counts, as Accessibility reaches it`() {
        #expect(RestoreKeeps.reachable(window(on: 45, journaled: 45, showing: false, onScreen: false)))
    }

    @Test func `A window closed and kept, gone, or otherwise out of reach is not counted`() {
        #expect(!RestoreKeeps.reachable(window(minimized: true, onScreen: false)), "closed and kept")
        #expect(!RestoreKeeps.reachable(window(on: 45, journaled: 45, minimized: true, showing: false, onScreen: false)),
                "closed and kept on a Desktop not showing")
        #expect(!RestoreKeeps.reachable(window(exists: false)))
        #expect(!RestoreKeeps.reachable(window(appHidden: true)))
        #expect(!RestoreKeeps.reachable(window(on: 0)))
        #expect(!RestoreKeeps.reachable(window(onScreen: false)), "on the showing Desktop, not drawn")
    }
}
