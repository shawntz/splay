import CoreGraphics
import Testing
@testable import DinkyLayout

private let peek = Workspace.peek

/// A scrolling workspace with windows 1...n inserted in order, as in ScrollingTests: n is focused and in view, and
/// with the default sliver and no gaps or walls the columns go between 0 and 1000.
private func strip(_ n: Int, walls: Set<Direction> = [], sliver: CGFloat = Workspace.peek) -> Workspace {
    var ws = Workspace(bounds: rect(-peek, 0, 1000 + 2 * peek, 600), algorithm: .scrolling)
    ws.columnWidth = 0.5
    ws.walls = walls
    ws.sliver = sliver
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

/// Left edges of the windows as the strip lays them out, on screen or not.
private func lefts(_ ws: Workspace) -> [CGFloat] {
    let frames = ws.tiledLayout().frames
    return ws.windows.map { frames[$0]!.minX }
}

/// The sliver of a parked window, and the focused column staying in view when the strip's geometry or a column's
/// layout changes under it.
struct ScrollingInViewTests {
    @Test func `The sliver is 25 points unless set`() {
        var ws = strip(4)
        #expect(ws.sliver == 25)
        ws.focus(2)
        let frames = ws.layout().frames
        #expect(frames[1]!.maxX == 0, "25 points showing")
        #expect(frames[4]!.minX == 1000)
    }

    @Test func `A 1 point sliver leaves 1 point of a parked window on screen`() {
        var ws = strip(5, sliver: 1)
        ws.focus(2)
        #expect(lefts(ws) == [-548, -24, 500, 1024, 1548], "columns 524 wide between gutters of 1 point")
        let frames = ws.layout().frames
        #expect(frames[1]!.maxX == -24, "1 point showing")
        #expect(frames[4]!.minX == 1024 && frames[5]!.minX == 1024)
    }

    @Test func `A wider sliver keeps the focused column in view`() {
        var ws = strip(5)
        ws.focus(3)
        ws.sliver = 125
        #expect(lefts(ws) == [-700, -300, 100, 500, 900])
        #expect(ws.isInView(3))
    }

    @Test func `Narrower bounds keep the focused column in view`() {
        var ws = strip(5)
        ws.focus(3)
        #expect(lefts(ws) == [-1000, -500, 0, 500, 1000])
        ws.bounds = rect(-peek, 0, 500 + 2 * peek, 600)
        #expect(lefts(ws) == [-500, -250, 0, 250, 500])
        #expect(ws.isInView(3))
    }

    @Test func `Moving to another display keeps the focused column in view`() {
        var ws = strip(5)
        ws.focus(3)
        ws.bounds = rect(2000 - peek, 0, 500 + 2 * peek, 600)
        #expect(lefts(ws) == [1500, 1750, 2000, 2250, 2500])
        #expect(ws.isInView(3))
    }

    @Test func `Wider gaps keep the focused column in view`() {
        var ws = strip(5)
        ws.focus(3)
        ws.gaps = Gaps(all: 150)
        #expect(lefts(ws) == [-625, -175, 200, 575, 950])
        #expect(ws.isInView(3))
    }

    @Test func `Losing a wall keeps the focused column in view`() {
        var ws = strip(5, walls: [.left, .right])
        ws.focus(3)
        #expect(lefts(ws) == [-1075, -550, -25, 500, 1025])
        ws.walls = []
        #expect(lefts(ws) == [-1000, -500, 0, 500, 1000])
        #expect(ws.isInView(3))
    }

    @Test func `A centred column stays centred on new bounds`() {
        var ws = strip(5)
        ws.focus(3)
        ws.centerColumn()
        ws.bounds = rect(-peek, 0, 500 + 2 * peek, 600)
        #expect(lefts(ws) == [-375, -125, 125, 375, 625])
    }

    @Test func `The same geometry again changes nothing`() {
        var ws = strip(5)
        ws.focus(1)
        let before = ws
        ws.bounds = before.bounds
        ws.gaps = before.gaps
        ws.walls = before.walls
        ws.sliver = before.sliver
        #expect(ws == before)
    }

    @Test func `Splitting a column into columns keeps the focused window in view`() {
        var ws = strip(5)
        ws.focus(5)
        ws.join(.left)
        ws.focus(5)
        ws.setOrientation(.horizontal)
        #expect(shape(ws.root) == "h[1 2 3 4 5]")
        #expect(ws.focused == 5)
        #expect(ws.isInView(5))
        #expect(lefts(ws) == [-1475, -975, -475, 25, 525])
    }
}
