import CoreGraphics
import Testing
@testable import DinkyLayout

private let peek = Workspace.peek

/// A scrolling workspace with windows 1...n inserted in order, as in ScrollingTests: n is focused and in view, and
/// the columns go between 0 and 1000 when there are no walls.
private func strip(_ n: Int, width: Double = 0.5, walls: Set<Direction> = []) -> Workspace {
    var ws = Workspace(bounds: rect(-peek, 0, 1000 + 2 * peek, 600), algorithm: .scrolling)
    ws.columnWidth = width
    ws.walls = walls
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

/// Left edges of the windows as the strip lays them out, on screen or not.
private func lefts(_ ws: Workspace) -> [CGFloat] {
    let frames = ws.tiledLayout().frames
    return ws.windows.map { frames[$0]!.minX }
}

/// The focused column stays put on screen when columns change around it, as in niri.
struct ScrollingAnchorTests {
    @Test func `Closing a column left of the focused one leaves it where it is`() {
        var ws = strip(5)
        ws.focus(3)
        #expect(lefts(ws) == [-1000, -500, 0, 500, 1000])
        ws.remove(1)
        #expect(ws.focused == 3)
        #expect(lefts(ws) == [-500, 0, 500, 1000])
    }

    @Test func `A focused column the end of the strip pulls along still shows whole`() {
        var ws = strip(4)
        ws.focus(2)
        #expect(lefts(ws) == [-500, 0, 500, 1000])
        ws.remove(1)
        #expect(lefts(ws) == [-25, 475, 975], "the first column reaches into the empty gutter")
        #expect(ws.isInView(2))
    }

    @Test func `Closing a column right of the view moves nothing in view`() {
        var ws = strip(5)
        ws.focus(2)
        let before = ws.layout().frames
        ws.remove(5)
        let after = ws.layout().frames
        for id: WindowID in [1, 2, 3, 4] { #expect(after[id] == before[id]) }
    }

    @Test func `Columns left that fit are centred`() {
        var ws = strip(3, width: 0.49)
        ws.focus(2)
        ws.remove(1)
        #expect(ws.layout().frames[2] == rect(10, 0, 490, 600))
        #expect(ws.layout().frames[3] == rect(500, 0, 490, 600))
        var pair = strip(2)
        pair.remove(1)
        #expect(pair.layout().frames[2] == rect(-peek, 0, 1000 + 2 * peek, 600), "a lone column fills the screen")
    }

    @Test func `Closing a column beside a wall leaves the focused one where it is`() {
        var left = strip(5, walls: [.left])
        left.focus(3)
        #expect(lefts(left) == [-1051, -538, -25, 488, 1001], "no gutter at the wall")
        left.remove(1)
        #expect(lefts(left) == [-538, -25, 488, 1001])
        var right = strip(5, walls: [.right])
        right.focus(3)
        #expect(lefts(right) == [-1026, -513, 0, 513, 1026])
        right.remove(1)
        #expect(lefts(right) == [-513, 0, 513, 1026])
    }

    @Test func `Closing a window of a stacked column moves no column`() {
        var ws = strip(5)
        ws.focus(2)
        ws.join(.left)
        #expect(shape(ws.root) == "h[v[1 2] 3 4 5]")
        ws.focus(4)
        let before = lefts(ws)
        ws.remove(1)
        #expect(lefts(ws) == Array(before.dropFirst()))
        var focusedStack = strip(4)
        focusedStack.focus(3)
        focusedStack.join(.left)
        #expect(lefts(focusedStack) == [-475, 25, 25, 525])
        focusedStack.remove(2)
        #expect(lefts(focusedStack) == [-475, 25, 525])
    }

    @Test func `A column left of the focused one growing to a minimum width does not push it along`() {
        var ws = strip(5)
        ws.focus(3)
        ws.minimumSizes[1] = CGSize(width: 800, height: 0)
        #expect(lefts(ws) == [-1300, -500, 0, 500, 1000])
        ws.minimumSizes[2] = CGSize(width: 1100, height: 0)
        #expect(lefts(ws) == [-1900, -1100, 0, 500, 1000], "however far it would have gone")
        #expect(ws.isInView(3))
        ws.minimumSizes = [:]
        #expect(lefts(ws) == [-1000, -500, 0, 500, 1000])
    }

    @Test func `A tab taking the place of a wider window left of the focused one does not pull it along`() {
        var ws = strip(5)
        ws.minimumSizes[1] = CGSize(width: 800, height: 0)
        ws.focus(3)
        #expect(lefts(ws) == [-1300, -500, 0, 500, 1000])
        ws.replace(1, with: 9)
        #expect(ws.windows == [9, 2, 3, 4, 5])
        #expect(lefts(ws) == [-1000, -500, 0, 500, 1000])
    }

    @Test func `Windows inserted one after another line up in that order`() {
        var ws = Workspace(bounds: rect(-peek, 0, 1000 + 2 * peek, 600), algorithm: .scrolling)
        for id: WindowID in [7, 3, 5] { ws.insert(id) }
        #expect(ws.windows == [7, 3, 5])
        ws.focus(3)
        for id: WindowID in [8, 9] { ws.insert(id) }
        #expect(ws.windows == [7, 3, 8, 9, 5], "after the focused column, still in order")
    }


    @Test func `A tab switch in a widened column left of the focused one leaves it where it is`() {
        var ws = strip(3)
        ws.focus(1)
        ws.setColumnWidth(0.9)
        ws.minimumSizes[1] = CGSize(width: 100, height: 0)
        ws.focus(3)
        let before = ws.tiledLayout().frames[3]
        ws.replace(1, with: 9)
        #expect(ws.tiledLayout().frames[3] == before)
    }

    @Test func `The focused column growing to a minimum width past the edge still shows whole`() {
        var ws = strip(4)
        ws.focus(1)
        ws.focus(2)
        #expect(ws.tiledLayout().frames[2]?.minX == 475)
        ws.minimumSizes[2] = CGSize(width: 800, height: 0)
        let frame = ws.tiledLayout().frames[2]!
        #expect(frame.minX >= 0 && frame.maxX <= 1000)
    }
}
