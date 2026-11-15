import CoreGraphics
import Testing
@testable import DinkyLayout

private let peek = Workspace.peek

/// A scrolling workspace with windows 1...n inserted in order, as in ScrollingTests: n is focused and in view, and
/// the columns go between 0 and 1000, so a share of 1 is 1000 wide.
private func strip(_ n: Int, width: Double = 0.5) -> Workspace {
    var ws = Workspace(bounds: rect(-peek, 0, 1000 + 2 * peek, 600), algorithm: .scrolling)
    ws.columnWidth = width
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

/// Left edges of the windows as the strip lays them out, on screen or not.
private func lefts(_ ws: Workspace) -> [CGFloat] {
    let frames = ws.tiledLayout().frames
    return ws.windows.map { frames[$0]!.minX }
}

private func width(_ ws: Workspace, _ id: WindowID) -> CGFloat? {
    ws.tiledLayout().frames[id]?.width
}

/// Preset widths, setting a width and maximising a column, as niri's switch-preset-column-width,
/// set-column-width and maximize-column do.
struct ScrollingWidthsTests {
    @Test func `The presets are a third, a half and two thirds`() {
        #expect(Workspace(bounds: rect(0, 0, 1000, 600), algorithm: .scrolling).presetColumnWidths == [1.0 / 3, 0.5, 2.0 / 3])
    }

    @Test func `Cycling steps up through the presets and wraps`() {
        var ws = strip(3)
        ws.focus(2)
        var widths: [CGFloat?] = []
        for _ in 0..<4 {
            #expect(ws.cycleColumnWidth() == true)
            widths.append(width(ws, 2))
        }
        #expect(widths == [667, 333, 500, 667])
    }

    @Test func `Cycling backward steps down and wraps`() {
        var ws = strip(3)
        ws.focus(2)
        var widths: [CGFloat?] = []
        for _ in 0..<4 {
            #expect(ws.cycleColumnWidth(backward: true) == true)
            widths.append(width(ws, 2))
        }
        #expect(widths == [333, 667, 500, 333])
    }

    @Test func `The shipped width counts as a half`() {
        var up = strip(3, width: 0.49)
        up.focus(2)
        #expect(up.cycleColumnWidth() == true)
        #expect(width(up, 2) == 667)
        var down = strip(3, width: 0.49)
        down.focus(2)
        #expect(down.cycleColumnWidth(backward: true) == true)
        #expect(width(down, 2) == 333)
    }

    @Test func `A width between presets goes to the next one that way`() {
        var ws = strip(3)
        ws.focus(2)
        #expect(ws.setColumnWidth(0.4) == true)
        #expect(ws.cycleColumnWidth() == true)
        #expect(width(ws, 2) == 500)
        #expect(ws.setColumnWidth(0.4) == true)
        #expect(ws.cycleColumnWidth(backward: true) == true)
        #expect(width(ws, 2) == 333)
    }

    @Test func `Presets a minimum size swallows are skipped`() {
        var ws = strip(3)
        ws.focus(2)
        ws.minimumSizes[2] = CGSize(width: 600, height: 0)
        #expect(width(ws, 2) == 600)
        #expect(ws.cycleColumnWidth(backward: true) == true, "a third shows as 600 too")
        #expect(width(ws, 2) == 667)
        #expect(ws.cycleColumnWidth() == true)
        #expect(width(ws, 2) == 600)
        #expect(ws.cycleColumnWidth() == true, "a half shows as 600 too")
        #expect(width(ws, 2) == 667)
    }

    @Test func `A lap the minimum size swallows whole changes nothing`() {
        var ws = strip(3)
        ws.focus(2)
        ws.minimumSizes[2] = CGSize(width: 800, height: 0)
        let before = ws
        #expect(ws.cycleColumnWidth() == false)
        #expect(ws.cycleColumnWidth(backward: true) == false)
        #expect(ws == before)
    }

    @Test func `A lone column ignores the presets, and so does an empty list`() {
        var lone = strip(1)
        #expect(lone.cycleColumnWidth() == false)
        lone.insert(2)
        #expect(width(lone, 1) == 500)
        var none = strip(3)
        none.focus(2)
        none.presetColumnWidths = []
        let before = none
        #expect(none.cycleColumnWidth() == false)
        #expect(none == before)
    }

    @Test func `Every window of a stacked column takes the preset`() {
        var ws = strip(3)
        ws.join(.left)
        #expect(shape(ws.root) == "h[1 v[2 3]]")
        #expect(ws.cycleColumnWidth() == true)
        #expect(width(ws, 2) == 667 && width(ws, 3) == 667)
        #expect(ws.columnWidths[2] == ws.columnWidths[3])
    }

    @Test func `Cycling ends fullscreen and shows the column whole`() {
        var ws = strip(3)
        ws.toggleFullscreen()
        #expect(ws.fullscreen == 3)
        #expect(ws.cycleColumnWidth() == true)
        #expect(ws.fullscreen == nil)
        #expect(lefts(ws) == [-642, -142, 358])
        #expect(ws.isInView(3))
    }

    @Test func `Setting the width directly keeps the limits of a resize`() {
        var ws = strip(2)
        #expect(ws.setColumnWidth(0.3) == true)
        #expect(width(ws, 2) == 300)
        #expect(ws.setColumnWidth(0.3) == false, "nothing changed")
        #expect(ws.setColumnWidth(2) == true)
        #expect(width(ws, 2) == 1000, "no wider than between the gutters")
        #expect(ws.setColumnWidth(0) == true)
        #expect(width(ws, 2) == 100, "no narrower than a tenth")
        var lone = strip(1)
        #expect(lone.setColumnWidth(0.3) == false, "a lone column fills the screen")
        lone.insert(2)
        #expect(width(lone, 1) == 500)
    }

    @Test func `Maximising fills the width between the gutters, and toggling again restores the width`() {
        var ws = strip(3)
        ws.focus(2)
        #expect(ws.setColumnWidth(0.4) == true)
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(ws.tiledLayout().frames[2] == rect(0, 0, 1000, 600))
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(width(ws, 2) == 400)
        #expect(ws.toggleMaximizeColumn() == true, "and again")
        #expect(width(ws, 2) == 1000)
    }

    @Test func `Changing the width another way forgets the width maximising kept`() {
        var resized = strip(3)
        resized.focus(2)
        resized.toggleMaximizeColumn()
        #expect(resized.resize(by: -100) == true)
        #expect(resized.toggleMaximizeColumn() == true, "maximises again")
        #expect(width(resized, 2) == 1000)
        #expect(resized.toggleMaximizeColumn() == true)
        #expect(width(resized, 2) == 900)

        var cycled = strip(3)
        cycled.focus(2)
        cycled.toggleMaximizeColumn()
        #expect(cycled.cycleColumnWidth() == true)
        #expect(width(cycled, 2) == 333)
        #expect(cycled.toggleMaximizeColumn() == true)
        #expect(width(cycled, 2) == 1000)

        var balanced = strip(3)
        balanced.focus(2)
        balanced.toggleMaximizeColumn()
        balanced.balanceSizes()
        #expect(balanced.toggleMaximizeColumn() == true)
        #expect(width(balanced, 2) == 1000)
    }

    @Test func `A window leaving forgets the width maximising kept`() {
        var ws = strip(3)
        ws.focus(2)
        ws.toggleMaximizeColumn()
        ws.remove(2)
        ws.insert(2)
        #expect(width(ws, 2) == 500)
        #expect(ws.toggleMaximizeColumn() == true, "nothing to restore")
        #expect(width(ws, 2) == 1000)
    }

    @Test func `A tab taking a maximised window's place keeps the width to restore`() {
        var ws = strip(3)
        ws.focus(2)
        ws.toggleMaximizeColumn()
        ws.replace(2, with: 9)
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(width(ws, 9) == 500)
    }

    @Test func `Maximising a stacked column widens every window, and a lone column cannot`() {
        var ws = strip(3)
        ws.join(.left)
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(width(ws, 2) == 1000 && width(ws, 3) == 1000)
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(width(ws, 2) == 500 && width(ws, 3) == 500)
        var lone = strip(1)
        #expect(lone.toggleMaximizeColumn() == false)
        lone.insert(2)
        #expect(width(lone, 1) == 500)
    }

    @Test func `Maximising ends fullscreen and shows the column`() {
        var ws = strip(3)
        ws.focus(1)
        ws.toggleFullscreen()
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(ws.fullscreen == nil)
        #expect(ws.isInView(1))
    }

    @Test func `Other layouts have no columns to size`() {
        var tiles = workspace(2)
        let before = tiles
        #expect(tiles.cycleColumnWidth() == false)
        #expect(tiles.setColumnWidth(0.3) == false)
        #expect(tiles.toggleMaximizeColumn() == false)
        #expect(tiles == before)
    }


    @Test func `Cycling backward from below every preset wraps to the widest`() {
        var ws = strip(3)
        ws.focus(2)
        ws.setColumnWidth(0.2)
        #expect(ws.cycleColumnWidth(backward: true) == true)
        #expect(width(ws, 2) == 667)
    }

    @Test func `A width a lone column swallows keeps the width maximising kept`() {
        var ws = strip(2)
        #expect(ws.toggleMaximizeColumn() == true)
        ws.remove(1)
        #expect(ws.setColumnWidth(0.3) == false, "a lone column fills the screen whatever its width")
        ws.insert(5)
        ws.focus(2)
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(width(ws, 2) == 500)
    }

    @Test func `A maximised stack keeps the width to restore when its focused window closes`() {
        var ws = strip(3)
        ws.join(.left)
        #expect(shape(ws.root) == "h[1 v[2 3]]")
        ws.toggleMaximizeColumn()
        ws.remove(3)
        #expect(ws.focused == 2)
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(width(ws, 2) == 500)
    }

    @Test func `Maximising still works on a stacked column a swap left with two widths`() {
        var ws = strip(3)
        ws.join(.left)
        ws.toggleMaximizeColumn()
        ws.swap(1, 2)
        #expect(shape(ws.root) == "h[2 v[1 3]]")
        ws.focus(3)
        #expect(width(ws, 3) == 500, "the stack shows the width of its first window, and 3 still keeps 0.5 to restore")
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(width(ws, 1) == 1000 && width(ws, 3) == 1000)
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(width(ws, 1) == 500 && width(ws, 3) == 500)
    }

    @Test func `A width kept for another column is not given to a stack that is not maximised`() {
        var ws = strip(3)
        ws.focus(1)
        ws.setColumnWidth(0.7)
        ws.focus(3)
        ws.join(.left)
        ws.toggleMaximizeColumn()
        ws.swap(1, 2)
        ws.focus(3)
        #expect(shape(ws.root) == "h[2 v[1 3]]")
        #expect(width(ws, 3) == 700, "the stack shows 1's width, while 3 keeps the 0.5 its old column had")
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(width(ws, 1) == 1000 && width(ws, 3) == 1000, "maximised, not narrowed to 500")
        #expect(ws.toggleMaximizeColumn() == true)
        #expect(width(ws, 1) == 700 && width(ws, 3) == 700, "and back to the width it showed")
    }
}
