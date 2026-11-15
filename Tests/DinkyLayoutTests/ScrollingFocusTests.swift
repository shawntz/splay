import CoreGraphics
import Testing
@testable import DinkyLayout

private let peek = Workspace.peek

/// A scrolling workspace with windows 1...n inserted in order, as in ScrollingTests: n is focused and in view, and
/// the columns go between 0 and 1000.
private func strip(_ n: Int) -> Workspace {
    var ws = Workspace(bounds: rect(-peek, 0, 1000 + 2 * peek, 600), algorithm: .scrolling)
    ws.columnWidth = 0.5
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

/// Left edges of the windows as the strip lays them out, on screen or not.
private func lefts(_ ws: Workspace) -> [CGFloat] {
    let frames = ws.tiledLayout().frames
    return ws.windows.map { frames[$0]!.minX }
}

/// "h[v[1 2] v[3 4]]", with 4 the most recently focused window of the second column and 1 focused.
private func twoStacks() -> Workspace {
    var ws = strip(4)
    ws.focus(2)
    ws.join(.left)
    ws.focus(4)
    ws.join(.left)
    ws.focus(1)
    return ws
}

/// Moving focus along the strip as niri does: into a column at the window last focused there, and to its ends.
struct ScrollingFocusTests {
    @Test func `Focus jumps to the first or last column`() {
        var ws = strip(4)
        ws.focus(2)
        #expect(ws.focusEdge(.right) == true)
        #expect(ws.focused == 4)
        #expect(lefts(ws) == [-975, -475, 25, 525])
        #expect(ws.focusEdge(.right) == false, "already there")
        #expect(ws.focusEdge(.left) == true)
        #expect(ws.focused == 1)
        #expect(lefts(ws) == [-25, 475, 975, 1475])
    }

    @Test func `An end column is entered at its most recently focused window`() {
        var ws = strip(4)
        ws.focus(2)
        ws.join(.left)
        ws.setMode(.accordion)
        ws.setOrientation(.horizontal)
        #expect(shape(ws.root) == "h[ah[1 2] 3 4]")
        ws.focus(4)
        #expect(ws.edgeWindow(.left) == 1, "the window at the edge")
        #expect(ws.focusEdge(.left) == true)
        #expect(ws.focused == 2, "the column's most recent")
    }

    @Test func `Up and down go to the ends of the focused column`() {
        var ws = strip(3)
        ws.join(.left)
        #expect(ws.focusEdge(.up) == true)
        #expect(ws.focused == 2)
        #expect(ws.focusEdge(.down) == true)
        #expect(ws.focused == 3)
        var lone = strip(1)
        #expect(lone.focusEdge(.left) == false && lone.focusEdge(.right) == false)
        var empty = Workspace(bounds: rect(0, 0, 1000, 600), algorithm: .scrolling)
        #expect(empty.focusEdge(.left) == false)
    }

    @Test func `Other layouts focus the window at the edge`() {
        var ws = workspace(3)
        #expect(shape(ws.root) == "h[1 v[2 3]]")
        #expect(ws.focusEdge(.left) == true)
        #expect(ws.focused == 1)
        #expect(ws.focusEdge(.right) == true)
        #expect(ws.focused == 3)
    }

    @Test func `Left and right enter a column at its most recently focused window`() {
        var ws = twoStacks()
        #expect(shape(ws.root) == "h[v[1 2] v[3 4]]")
        #expect(ws.focus(.right) == true)
        #expect(ws.focused == 4, "not 3 beside it")
        #expect(ws.focus(.left) == true)
        #expect(ws.focused == 1, "not 2 beside it")
    }

    @Test func `A swipe enters a column at its most recently focused window too`() {
        var ws = twoStacks()
        #expect(ws.swipeTarget(.right) == 4)
        ws.focus(4)
        #expect(ws.swipeTarget(.left) == 1)
    }

    @Test func `Steps within a column stay beside the window`() {
        var ws = strip(4)
        ws.focus(3)
        ws.join(.left)
        ws.setMode(.accordion)
        ws.setOrientation(.horizontal)
        #expect(shape(ws.root) == "h[1 ah[2 3] 4]")
        ws.focus(2)
        ws.focus(4)
        #expect(ws.focus(.left) == true)
        #expect(ws.focused == 2, "the column's most recent, not 3 nearest")
        #expect(ws.focus(.right) == true)
        #expect(ws.focused == 3, "within the column")
        #expect(ws.focus(.right) == true)
        #expect(ws.focused == 4)
        ws.focus(2)
        #expect(ws.focus(.left) == true)
        #expect(ws.focused == 1)
    }

    @Test func `Up and down are unchanged`() {
        var ws = twoStacks()
        ws.focus(4)
        #expect(ws.focus(.up) == true)
        #expect(ws.focused == 3)
        #expect(ws.focus(.down) == true)
        #expect(ws.focused == 4)
        #expect(ws.focus(.down) == false)
    }
}
