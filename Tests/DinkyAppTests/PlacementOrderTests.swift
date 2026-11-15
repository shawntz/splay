import CoreGraphics
import DinkyConfig
import DinkyLayout
import Foundation
import Testing
@testable import dinky

/// Windows already open go into their trees in on-screen order. Synthetic windows and a coordinator that never
/// starts: no WindowServer, no AX.
struct PlacementOrderTests {
    private func window(_ id: UInt32, x: CGFloat, y: CGFloat = 0) -> Window {
        Window(identity: .init(id: id, pid: -1, firstSeen: .distantPast), appName: nil, bundleID: nil,
               frame: CGRect(x: x, y: y, width: 400, height: 300))
    }

    private func coordinator() -> Coordinator {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-placement-\(UUID())")
        let coordinator = Coordinator(displays: DisplayModel(), config: Config(), applier: FrameApplier(supportURL: support))
        coordinator.workspaces[1] = Workspace(bounds: CGRect(x: 0, y: 0, width: 1000, height: 600), algorithm: .scrolling)
        return coordinator
    }

    @Test func windowsGoLeftToRightAsTheyStand() {
        let windows = [window(30, x: 900), window(10, x: -350), window(40, x: 1500), window(20, x: 400)]
        #expect(Coordinator.placementOrder(windows).map(\.id) == [10, 20, 30, 40])
    }

    @Test func windowsSideBySideGoTopToBottomThenByID() {
        let windows = [window(5, x: 0, y: 300), window(9, x: 0), window(7, x: 0), window(1, x: 600)]
        #expect(Coordinator.placementOrder(windows).map(\.id) == [7, 9, 5, 1])
    }

    @Test func theOrderDoesNotDependOnTheOrderWindowsCameIn() {
        let windows = [window(4, x: 700), window(2, x: 0, y: 300), window(3, x: 0, y: 300), window(1, x: 0)]
        let expected: [UInt32] = [1, 2, 3, 4]
        for start in windows.indices {
            let rotated = Array(windows[start...] + windows[..<start])
            #expect(Coordinator.placementOrder(rotated).map(\.id) == expected)
            #expect(Coordinator.placementOrder(rotated.reversed()).map(\.id) == expected)
        }
    }

    @Test func aBatchGoesIntoTheStripInOnScreenOrder() {
        let coordinator = coordinator()
        let windows = [window(30, x: 900), window(10, x: 0), window(40, x: 1500), window(20, x: 400)]
        for window in windows { coordinator.placements[window.id] = Placement(floating: false, space: 1) }
        coordinator.placingInOrder {
            for window in windows { coordinator.place(window, in: 1) }
            #expect(coordinator.workspaces[1]?.windows == [], "held until the batch ends")
        }
        #expect(coordinator.workspaces[1]?.windows == [10, 20, 30, 40])
        #expect(coordinator.layouts.dirty.contains(1))
    }

    @Test func aBatchSkipsWindowsThatLeftBeforeItEnded() {
        let coordinator = coordinator()
        let windows = [window(3, x: 800), window(1, x: 0), window(2, x: 400)]
        for window in windows { coordinator.placements[window.id] = Placement(floating: false, space: 1) }
        coordinator.placingInOrder {
            for window in windows { coordinator.place(window, in: 1) }
            coordinator.placements[2] = nil
            coordinator.placements[3]?.space = nil
        }
        #expect(coordinator.workspaces[1]?.windows == [1])
    }

    @Test func aBatchUsesEachWindowsLatestFrameOnce() {
        let coordinator = coordinator()
        coordinator.placements[1] = Placement(floating: false, space: 1)
        coordinator.placements[2] = Placement(floating: false, space: 1)
        coordinator.placingInOrder {
            coordinator.place(window(1, x: 0), in: 1)
            coordinator.place(window(2, x: 400), in: 1)
            coordinator.place(window(1, x: 800), in: 1)
        }
        #expect(coordinator.workspaces[1]?.windows == [2, 1])
    }

    @Test func aWindowPlacedOnItsOwnGoesInAtOnceBesideTheFocusedOne() {
        let coordinator = coordinator()
        for id: UInt32 in [1, 2, 3] { coordinator.place(window(id, x: CGFloat(id) * 100), in: 1) }
        coordinator.workspaces[1]?.focus(1)
        coordinator.place(window(9, x: -500), in: 1)
        #expect(coordinator.workspaces[1]?.windows == [1, 9, 2, 3], "a new window opens right of the focused one")
    }

    @Test func aBatchPutsAWindowOnTheSpaceItsPlacementNamesAtTheEnd() {
        let coordinator = coordinator()
        coordinator.workspaces[2] = Workspace(bounds: CGRect(x: 0, y: 0, width: 1000, height: 600), algorithm: .scrolling)
        var moved = window(5, x: 0)
        moved.spaceID = 1
        coordinator.placements[5] = Placement(floating: false, space: 1)
        coordinator.placingInOrder {
            coordinator.place(moved, in: 1)
            coordinator.placements[5]?.space = 2
        }
        #expect(coordinator.workspaces[1]?.windows == [])
        #expect(coordinator.workspaces[2]?.windows == [5], "it moved to another Space before the batch ended")
    }
}
