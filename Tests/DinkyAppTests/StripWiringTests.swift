import CoreGraphics
import DinkyCommands
import DinkyConfig
import DinkyLayout
import Foundation
import Testing
@testable import dinky

/// The strip's `[scrolling]` keys and commands, from the config and the dispatcher to the layout engine.
/// Workspaces and a coordinator that never starts: no WindowServer, no AX, no global AppState.
struct StripWiringTests {
    private func strip(_ ids: [WindowID] = [11, 12, 13], focused: WindowID = 12,
                       algorithm: TilingAlgorithm = .scrolling) -> Workspace {
        var workspace = Workspace(bounds: CGRect(x: 0, y: 0, width: 1000, height: 600), algorithm: algorithm)
        for id in ids { workspace.insert(id) }
        workspace.focus(focused)
        return workspace
    }

    @Test func theStripKeysReachTheWorkspace() {
        var scrolling = Scrolling()
        scrolling.centerFocusedColumn = .always
        scrolling.presetColumnWidths = [0.25, 0.75]
        scrolling.peek = 10
        var workspace = strip()
        workspace.applyStrip(scrolling)
        #expect(workspace.centerFocusedColumn == .always)
        #expect(workspace.presetColumnWidths == [0.25, 0.75])
        #expect(workspace.sliver == 10)
    }

    @Test func eachCentringChoiceMeansTheSameToTheEngine() {
        let pairs: [(DinkyConfig.CenterFocusedColumn, DinkyLayout.CenterFocusedColumn)] = [
            (.never, .never), (.always, .always), (.onOverflow, .onOverflow),
        ]
        for (config, engine) in pairs {
            var scrolling = Scrolling()
            scrolling.centerFocusedColumn = config
            #expect(scrolling.layoutCentring == engine, "\(config)")
        }
    }

    @Test func theConfigDefaultsAreTheEngines() {
        let engine = strip()
        var configured = strip()
        configured.applyStrip(Config().scrolling)
        #expect(configured.centerFocusedColumn == engine.centerFocusedColumn)
        #expect(configured.sliver == engine.sliver)
        // TOML has no thirds; five places are the same pixels on any display.
        #expect(configured.presetColumnWidths.count == engine.presetColumnWidths.count)
        for (written, exact) in zip(configured.presetColumnWidths, engine.presetColumnWidths) {
            #expect(abs(written - exact) < 0.0001, "\(written) for \(exact)")
        }
    }

    @Test func aParkedColumnLeavesThePeekTheConfigAsksFor() throws {
        var scrolling = Scrolling()
        scrolling.peek = 10
        var workspace = strip([11, 12, 13, 14], focused: 11)
        workspace.applyStrip(scrolling)
        let parked = try #require(workspace.layout().frames[14])
        #expect(parked.minX == 990)
    }

    // MARK: Commands

    /// The change `command` makes, against the engine call it stands for, on a copy of `workspace` each.
    private func expectSame(_ command: Command, as call: (inout Workspace) -> Bool, on workspace: Workspace,
                            changes: Bool, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let (_, change) = try #require(Dispatcher.stripChange(command), sourceLocation: sourceLocation)
        var dispatched = workspace, direct = workspace
        let result = change(&dispatched)
        #expect(result == call(&direct), sourceLocation: sourceLocation)
        #expect(result == changes, sourceLocation: sourceLocation)
        #expect(dispatched == direct, sourceLocation: sourceLocation)
    }

    @Test func eachStripCommandRunsItsEngineCall() throws {
        let workspace = strip()
        try expectSame(.centerColumn, as: { $0.centerColumn() }, on: workspace, changes: true)
        try expectSame(.columnWidth(.next), as: { $0.cycleColumnWidth() }, on: workspace, changes: true)
        try expectSame(.columnWidth(.prev), as: { $0.cycleColumnWidth(backward: true) }, on: workspace, changes: true)
        try expectSame(.columnWidth(.share(0.4)), as: { $0.setColumnWidth(0.4) }, on: workspace, changes: true)
        try expectSame(.maximizeColumn, as: { $0.toggleMaximizeColumn() }, on: workspace, changes: true)
        try expectSame(.focusColumn(.first), as: { $0.focusEdge(.left) }, on: workspace, changes: true)
        try expectSame(.focusColumn(.last), as: { $0.focusEdge(.right) }, on: workspace, changes: true)
    }

    @Test func columnWidthNextAndPrevGoOppositeWays() throws {
        let (_, next) = try #require(Dispatcher.stripChange(.columnWidth(.next)))
        let (_, prev) = try #require(Dispatcher.stripChange(.columnWidth(.prev)))
        var wider = strip(), narrower = strip()
        _ = next(&wider)
        _ = prev(&narrower)
        let before = try #require(strip().layout().frames[12]).width
        #expect(try #require(wider.layout().frames[12]).width > before)
        #expect(try #require(narrower.layout().frames[12]).width < before)
    }

    @Test func focusColumnReachesEitherEndOfTheStrip() throws {
        let (_, first) = try #require(Dispatcher.stripChange(.focusColumn(.first)))
        let (_, last) = try #require(Dispatcher.stripChange(.focusColumn(.last)))
        var workspace = strip()
        #expect(first(&workspace))
        #expect(workspace.focused == 11)
        #expect(!first(&workspace), "already there")
        #expect(last(&workspace))
        #expect(workspace.focused == 13)
    }

    /// As swap-with-master outside a master layout: nothing to do, and nothing done.
    @Test(arguments: [TilingAlgorithm.dwindle(.tiles), .master, .fixed(rows: 1, columns: 3, expand: .columns)])
    func inAnotherLayoutTheStripCommandsHaveNothingToDo(algorithm: TilingAlgorithm) throws {
        let workspace = strip(algorithm: algorithm)
        for command: Command in [.centerColumn, .columnWidth(.next), .columnWidth(.prev), .columnWidth(.share(0.4)),
                                 .maximizeColumn, .focusColumn(.first), .focusColumn(.last)] {
            let (name, change) = try #require(Dispatcher.stripChange(command))
            var changed = workspace
            #expect(!change(&changed), "\(name)")
            #expect(changed == workspace, "\(name)")
        }
    }

    @Test func repliesNameTheCommandAsWritten() throws {
        let names = try [Command.centerColumn, .columnWidth(.next), .columnWidth(.prev), .columnWidth(.share(0.4)),
                         .maximizeColumn, .focusColumn(.first), .focusColumn(.last)]
            .map { try #require(Dispatcher.stripChange($0)).name }
        #expect(names == ["center-column", "column-width next", "column-width prev", "column-width 0.4",
                          "maximize-column", "focus-column first", "focus-column last"])
        #expect(Dispatcher.stripChange(.fullscreen) == nil)
    }

    // MARK: debug-state

    @Test func everyTreeNamesItsLayoutAsListWorkspacesDoes() {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-strip-\(UUID())")
        let coordinator = Coordinator(displays: DisplayModel(), config: Config(), applier: FrameApplier(supportURL: support))
        coordinator.workspaces[1] = strip()
        coordinator.workspaces[2] = strip(algorithm: .dwindle(.accordion))
        coordinator.workspaces[3] = strip(algorithm: .fixed(rows: 2, columns: 2, expand: .rows))
        coordinator.workspaces[4] = strip(algorithm: .master)
        #expect([1, 2, 3, 4].map { coordinator.layoutName(ofWorkspace: $0) } == ["scrolling", "dwindle", "fixed", "master"])
    }
}

/// Walking the strip with quick or held presses: focusing another app's window is asynchronous, so a command can
/// arrive while macOS still reports the window before in front.
struct CommandWindowTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func aCommandStartsFromTheWindowJustFocusedUntilMacOSCatchesUp() {
        #expect(Coordinator.justFocused((id: 12, until: now + 0.5), now: now) { _ in true } == 12)
    }

    @Test func afterTheGraceTheFrontWindowCountsAgain() {
        #expect(Coordinator.justFocused((id: 12, until: now), now: now) { _ in true } == nil)
        #expect(Coordinator.justFocused((id: 12, until: now - 1), now: now) { _ in true } == nil)
        #expect(Coordinator.justFocused(nil, now: now) { _ in true } == nil)
    }

    @Test func aJustFocusedWindowNoLongerTiledGivesWayToTheFrontWindow() {
        #expect(Coordinator.justFocused((id: 12, until: now + 0.5), now: now) { $0 != 12 } == nil)
    }

    /// The second of two quick presses: the tree went to 12 on the first, and macOS has not caught up yet.
    @Test func aSecondQuickPressWalksOnFromTheWindowJustFocused() {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-walk-\(UUID())")
        let coordinator = Coordinator(displays: DisplayModel(), config: Config(), applier: FrameApplier(supportURL: support))
        var workspace = Workspace(bounds: CGRect(x: 0, y: 0, width: 1000, height: 600), algorithm: .scrolling)
        for id: WindowID in [11, 12, 13] {
            workspace.insert(id)
            coordinator.placements[id] = Placement(floating: false, space: 7)
        }
        workspace.focus(12)
        coordinator.workspaces[7] = workspace
        coordinator.focusing = (12, Date() + 60)
        #expect(coordinator.command { $0.focus(.right) ? $0.focused : nil } == 13)
        #expect(coordinator.workspaces[7]?.focused == 13)
    }

    /// Quick press, then a workspace switch: the window just focused is on a Space no longer shown, and a command
    /// starting from it would switch back.
    @Test func theGraceEndsForAWindowWhoseSpaceIsNoLongerShown() {
        let display = Display(uuid: "main", id: 0, frame: .zero, visibleArea: .zero, isMain: true,
                              spaces: [7, 8], userSpaces: [7, 8], currentSpaceID: 8)
        let model = DisplayModel(readSnapshot: { [display] })
        model.reconcile()
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-sight-\(UUID())")
        let coordinator = Coordinator(displays: model, config: Config(), applier: FrameApplier(supportURL: support))
        coordinator.placements[12] = Placement(floating: false, space: 7)
        coordinator.placements[13] = Placement(floating: false, space: 8)
        coordinator.placements[14] = Placement(floating: true, space: nil)
        #expect(!coordinator.isTiledInSight(12), "its Space was switched away from")
        #expect(coordinator.isTiledInSight(13))
        #expect(!coordinator.isTiledInSight(14), "floating")
        #expect(!coordinator.isTiledInSight(99), "not a window Splay knows")
        coordinator.focusing = (12, Date() + 60)
        #expect(coordinator.justFocusedWindow == nil, "the front window is the one to go by")
        coordinator.focusing = (13, Date() + 60)
        #expect(coordinator.justFocusedWindow == 13)
        #expect(coordinator.commandWindow == 13)
        #expect(coordinator.hasFocus(13), "the keyboard is on its way to it")
    }

    /// Quick press, then focus sent to a display with no window on it: a command from the window just focused
    /// would pull the keyboard back to the display left behind.
    @Test func theGraceEndsWhenADisplayWithNoWindowTakesTheFocus() {
        let displays = [("A", UInt64(7), true), ("B", UInt64(9), false)].map { uuid, space, main in
            Display(uuid: uuid, id: 0, frame: .zero, visibleArea: .zero, isMain: main,
                    spaces: [space], userSpaces: [space], currentSpaceID: space)
        }
        let model = DisplayModel(readSnapshot: { displays })
        model.reconcile()
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-override-\(UUID())")
        let coordinator = Coordinator(displays: model, config: Config(), applier: FrameApplier(supportURL: support))
        coordinator.placements[12] = Placement(floating: false, space: 7)
        coordinator.focusing = (12, Date() + 60)
        #expect(coordinator.justFocusedWindow == 12)
        model.focusOverride = "B"
        #expect(coordinator.justFocusedWindow == nil)
        model.focusOverride = "A"
        #expect(coordinator.justFocusedWindow == 12, "its own display has the focus")
    }
}

/// The strip's commands through the coordinator, as the dispatcher runs them for a key, the CLI or a rule.
/// A coordinator that never starts, with no display, so nothing is written to a window.
struct StripDispatchTests {
    /// A strip of 11, 12 and 13 on Space 7, 12 focused in the tree.
    private func coordinator(_ ids: [WindowID] = [11, 12, 13], algorithm: TilingAlgorithm = .scrolling) -> Coordinator {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("dinky-dispatch-\(UUID())")
        let coordinator = Coordinator(displays: DisplayModel(), config: Config(), applier: FrameApplier(supportURL: support))
        var workspace = Workspace(bounds: CGRect(x: 0, y: 0, width: 1000, height: 600), algorithm: algorithm)
        for id in ids {
            workspace.insert(id)
            coordinator.placements[id] = Placement(floating: false, space: 7)
        }
        workspace.focus(12)
        coordinator.workspaces[7] = workspace
        return coordinator
    }

    private func widths(_ coordinator: Coordinator) throws -> [WindowID: CGFloat] {
        try #require(coordinator.workspaces[7]).layout().frames.mapValues(\.width)
    }

    /// `run = 'column-width 0.33'` for a window that opened while another had focus.
    @Test func aRulesStripCommandChangesTheRulesWindowNotTheFocusedOne() throws {
        let coordinator = coordinator()
        coordinator.focusing = (12, Date() + 60)
        let before = try widths(coordinator)
        #expect(coordinator.strip(.columnWidth(.share(0.33)), window: 13) == .changed("column-width 0.33"))
        let after = try widths(coordinator)
        #expect(after[13] != before[13], "the rule's window")
        #expect(after[12] == before[12], "the window that had focus")
    }

    @Test func withNoWindowGivenTheCommandWindowsColumnChanges() throws {
        let coordinator = coordinator()
        coordinator.focusing = (12, Date() + 60)
        let before = try widths(coordinator)
        #expect(coordinator.strip(.maximizeColumn) == .changed("maximize-column"))
        let after = try widths(coordinator)
        #expect(try #require(after[12]) > (try #require(before[12])))
        #expect(after[13] == before[13])
    }

    @Test func aWindowThatIsNotTiledHasNoColumn() {
        let coordinator = coordinator()
        coordinator.placements[14] = Placement(floating: true, space: nil)
        #expect(coordinator.strip(.centerColumn, window: 14) == .notTiled("center-column"))
        #expect(coordinator.strip(.maximizeColumn, window: 99) == .notTiled("maximize-column"))
    }

    @Test func focusColumnReportsTheWindowForTheKeyboard() {
        let coordinator = coordinator()
        #expect(coordinator.strip(.focusColumn(.first), window: 13) == .focus(11))
        #expect(coordinator.workspaces[7]?.focused == 11)
        #expect(coordinator.strip(.focusColumn(.first), window: 11) == .nothing("focus-column first"))
        #expect(coordinator.strip(.focusColumn(.last), window: 11) == .focus(13))
    }

    @Test func inAnotherLayoutThereIsNothingToDo() {
        let coordinator = coordinator(algorithm: .dwindle(.tiles))
        #expect(coordinator.strip(.columnWidth(.next), window: 12) == .nothing("column-width next"))
        #expect(coordinator.strip(.focusColumn(.last), window: 12) == .nothing("focus-column last"))
    }

    @Test func otherCommandsAreNotTheStrips() {
        #expect(coordinator().strip(.fullscreen, window: 12) == .notStrip)
    }

    /// A rule sizing a window that opened behind the focused one, or one of many at launch: the keyboard is still
    /// on the focused window, so the strip must not scroll away from it.
    @Test func aRulesWidthLeavesTheViewOnTheFocusedWindow() throws {
        let coordinator = coordinator([11, 12, 13, 14])
        let before = try widths(coordinator)
        #expect(coordinator.strip(.maximizeColumn, window: 14) == .changed("maximize-column"))
        #expect(try #require(try widths(coordinator)[14]) > (try #require(before[14])))
        #expect(coordinator.workspaces[7]?.focused == 12)
        #expect(coordinator.isInView(12))
        #expect(coordinator.strip(.columnWidth(.share(0.33)), window: 14) == .changed("column-width 0.33"))
        #expect(coordinator.workspaces[7]?.focused == 12)
        #expect(coordinator.isInView(12))
    }

    @Test func centringARulesWindowScrollsToItAndStays() {
        let coordinator = coordinator([11, 12, 13, 14])
        #expect(coordinator.strip(.centerColumn, window: 14) == .changed("center-column"))
        #expect(coordinator.workspaces[7]?.focused == 14)
    }

    @Test func theDispatcherHandsARulesWindowToTheCoordinator() throws {
        let coordinator = coordinator()
        let before = try widths(coordinator)
        let reply = Dispatcher.strip(.columnWidth(.share(0.33)), window: 13, coordinator: coordinator)
        #expect(reply.ok)
        #expect(reply.text == "column-width 0.33")
        let after = try widths(coordinator)
        #expect(after[13] != before[13])
        #expect(after[12] == before[12])
        #expect(Dispatcher.strip(.maximizeColumn, window: 13, coordinator: nil).text == "tiling is not running")
    }

    @Test func repliesNameTheWindowThatHasNoColumn() {
        let command = Command.maximizeColumn
        let rule = Dispatcher.reply(to: command, .notTiled("maximize-column"), window: 13)
        #expect(rule?.ok == false)
        #expect(rule?.text == "maximize-column: window 13 is not tiled")
        #expect(Dispatcher.reply(to: command, .notTiled("maximize-column"), window: nil)?.text
                == "maximize-column: the focused window is not tiled")
        let nothing = Dispatcher.reply(to: command, .nothing("maximize-column"), window: nil)
        #expect(nothing?.ok == true)
        #expect(nothing?.text == "maximize-column: nothing to do")
        #expect(Dispatcher.reply(to: command, .changed("maximize-column"), window: nil)?.text == "maximize-column")
        #expect(Dispatcher.reply(to: .focusColumn(.first), .focus(11), window: nil) == nil, "focus answers that one")
    }
}
