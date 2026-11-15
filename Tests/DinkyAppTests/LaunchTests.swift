import Darwin
import Testing
@testable import dinky

/// How the app decides which signals quit it and whose Accessibility grant it answers to. Nothing here starts
/// the app, asks for Accessibility or installs a handler.
struct LaunchTests {
    @Test func `A hangup quits and restores, unless the run was started to outlive its terminal`() {
        #expect(quitSignals(hangupIgnored: false) == [SIGTERM, SIGINT, SIGHUP])
        #expect(quitSignals(hangupIgnored: true) == [SIGTERM, SIGINT], "as under nohup")
    }

    @Test func `An ignored hangup is seen as ignored`() {
        let before = hangupIsIgnored()
        let previous = signal(SIGHUP, SIG_IGN)
        #expect(hangupIsIgnored())
        signal(SIGHUP, previous)
        #expect(hangupIsIgnored() == before)
    }

    @Test func `A process answers to its own grant only when it is responsible for itself`() {
        #expect(heldToOwnGrant(responsible: 500, own: 500, parent: 1), "opened from Finder or with open")
        #expect(!heldToOwnGrant(responsible: 77, own: 500, parent: 400), "typed in a terminal")
        #expect(!heldToOwnGrant(responsible: 77, own: 500, parent: 1), "started from a terminal and detached from it")
        #expect(heldToOwnGrant(responsible: nil, own: 500, parent: 1), "macOS does not say: launchd as parent")
        #expect(!heldToOwnGrant(responsible: nil, own: 500, parent: 400))
        #expect(grantHolderName(responsible: 500, own: 500) == nil)
        #expect(grantHolderName(responsible: nil, own: 500) == nil)
    }

    @Test func `macOS says which process is responsible for this one`() {
        #expect((responsiblePID() ?? 0) > 0, "the lookup is gone, so the Accessibility window falls back to the parent")
    }
}
