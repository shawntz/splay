import CoreGraphics
import Testing
@testable import DinkyLayout

private let peek = Workspace.peek

/// A scrolling workspace with windows 1...n inserted in order under `center`, as in ScrollingTests: n is focused,
/// and the columns go between 0 and 1000, centred at 500, when there are no gaps or walls.
private func strip(_ n: Int, width: Double = 0.5, gaps: Gaps = .zero, walls: Set<Direction> = [],
                   center: CenterFocusedColumn = .never) -> Workspace {
    var ws = Workspace(bounds: rect(-peek, 0, 1000 + 2 * peek, 600), gaps: gaps, algorithm: .scrolling)
    ws.columnWidth = width
    ws.walls = walls
    ws.centerFocusedColumn = center
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

/// Left edges of the windows as the strip lays them out, on screen or not.
private func lefts(_ ws: Workspace) -> [CGFloat] {
    let frames = ws.tiledLayout().frames
    return ws.windows.map { frames[$0]!.minX }
}

/// Centring the focused column on the display, as niri's center-focused-column and center-column do.
struct ScrollingCentringTests {
    @Test func `Never is the default and fits as before`() {
        #expect(Workspace(bounds: rect(0, 0, 1000, 600), algorithm: .scrolling).centerFocusedColumn == .never)
        var ws = strip(4)
        #expect(lefts(ws) == [-975, -475, 25, 525])
        ws.focus(1)
        #expect(lefts(ws) == [-25, 475, 975, 1475])
    }

    @Test func `Always centres the focused column on the display`() {
        var ws = strip(5, center: .always)
        #expect(lefts(ws) == [-1750, -1250, -750, -250, 250], "the last column too, with nothing beside it")
        ws.focus(3)
        #expect(lefts(ws) == [-750, -250, 250, 750, 1250])
        ws.focus(1)
        #expect(lefts(ws) == [250, 750, 1250, 1750, 2250])
        #expect(ws.layout().frames[1] == rect(250, 0, 500, 600))
    }

    @Test func `Always centres columns that would fit, and a lone column still fills`() {
        var ws = strip(2, width: 0.49, center: .always)
        #expect(ws.layout().frames[2] == rect(255, 0, 490, 600))
        ws.focus(1)
        #expect(ws.layout().frames[1] == rect(255, 0, 490, 600))
        #expect(strip(1, center: .always).layout().frames[1] == rect(-peek, 0, 1000 + 2 * peek, 600))
    }

    @Test func `Always centres the windows, not the gaps beside them`() {
        var ws = strip(3, gaps: Gaps(all: 10), center: .always)
        ws.focus(1)
        #expect(ws.layout().frames[1] == rect(255, 10, 490, 580))
    }

    @Test func `On overflow fits a column that fits beside the one focus came from`() {
        var ws = strip(4, center: .onOverflow)
        #expect(lefts(ws) == [-975, -475, 25, 525])
        ws.focus(.left)
        #expect(lefts(ws) == [-975, -475, 25, 525], "already in view")
        ws.focus(.left)
        #expect(lefts(ws) == [-500, 0, 500, 1000])
    }

    @Test func `On overflow centres a column that does not fit beside the one focus came from`() {
        var ws = strip(3, width: 2.0 / 3, center: .onOverflow)
        #expect(lefts(ws) == [-1168, -501, 166])
        ws.focus(.left)
        #expect(lefts(ws) == [-501, 166, 833])
        ws.focus(.left)
        #expect(lefts(ws) == [167, 834, 1501])
    }

    @Test func `On overflow a jump fits when the column fits beside its neighbour, as in niri`() {
        var ws = strip(4, center: .onOverflow)
        ws.focus(1)
        #expect(lefts(ws) == [-25, 475, 975, 1475], "1 fits beside 2, though not beside 4")
    }

    @Test func `On overflow fits with no previous column or the same one`() {
        var ws = strip(2, center: .onOverflow)
        #expect(ws.resize(by: 167) == true)
        #expect(lefts(ws) == [-142, 358])
        ws.focus(2)
        #expect(lefts(ws) == [-142, 358], "the same column, though it does not fit beside its neighbour")
        var closing = strip(3, width: 2.0 / 3, center: .onOverflow)
        closing.remove(3)
        #expect(closing.focused == 2)
        #expect(lefts(closing) == [-309, 358], "no previous column: it closed")
    }

    @Test func `Centring the column holds while focus stays in it`() {
        var ws = strip(5)
        ws.focus(3)
        #expect(ws.centerColumn() == true)
        #expect(lefts(ws) == [-750, -250, 250, 750, 1250])
        #expect(ws.centerColumn() == false, "already centred")
        ws.focus(3)
        #expect(lefts(ws) == [-750, -250, 250, 750, 1250], "refocusing keeps it")
        #expect(ws.resize(by: 100) == true)
        #expect(lefts(ws) == [-800, -300, 200, 800, 1300], "resizing keeps it centred")
        ws.focus(.right)
        #expect(lefts(ws) == [-1100, -600, -100, 500, 1000], "another column fits again")
        ws.focus(.left)
        #expect(lefts(ws) == [-1000, -500, 0, 600, 1100], "and coming back does not centre")
    }

    @Test func `Centring holds while focus moves within a stacked column`() {
        var ws = strip(3)
        ws.join(.left)
        #expect(shape(ws.root) == "h[1 v[2 3]]")
        #expect(lefts(ws) == [0, 500, 500], "columns that fit are centred together")
        #expect(ws.centerColumn() == true)
        #expect(lefts(ws) == [-250, 250, 250])
        #expect(ws.focus(.up) == true)
        #expect(ws.focused == 2)
        #expect(lefts(ws) == [-250, 250, 250])
        ws.remove(2)
        #expect(ws.focused == 3)
        #expect(lefts(ws) == [-250, 250], "the column stays, and so does the centring")
    }

    @Test func `On overflow, leaving a centred column for one that fits beside it fits`() {
        var ws = strip(4, center: .onOverflow)
        ws.focus(2)
        #expect(ws.centerColumn() == true)
        #expect(lefts(ws) == [-250, 250, 750, 1250])
        ws.focus(.right)
        #expect(lefts(ws) == [-500, 0, 500, 1000], "3 fits beside 2, so only as far as shows it")
    }

    @Test func `Centring an end column scrolls past the end of the strip`() {
        var ws = strip(3)
        #expect(lefts(ws) == [-475, 25, 525])
        #expect(ws.centerColumn() == true)
        #expect(lefts(ws) == [-750, -250, 250])
        ws.focus(1)
        #expect(ws.centerColumn() == true)
        #expect(lefts(ws) == [250, 750, 1250])
    }

    @Test func `A lone column and other layouts have nothing to centre`() {
        var lone = strip(1)
        #expect(lone.centerColumn() == false)
        #expect(lone.layout().frames[1] == rect(-peek, 0, 1000 + 2 * peek, 600))
        var tiles = workspace(2)
        #expect(tiles.centerColumn() == false)
    }

    @Test(arguments: [CenterFocusedColumn.never, .always])
    func `A width step a minimum size swallows changes nothing under centring`(center: CenterFocusedColumn) {
        var ws = strip(3, center: center)
        ws.focus(2)
        ws.centerColumn()
        ws.minimumSizes[2] = CGSize(width: 700, height: 0)
        #expect(lefts(ws) == [-350, 150, 850])
        let before = ws.tiledLayout()
        #expect(ws.resize(by: 50) == false)
        #expect(ws.tiledLayout() == before)
        #expect(ws.columnWidths[2] == 0.5)
    }

    @Test func `What isInView says stays true under centring`() {
        var ws = strip(3, center: .always)
        ws.focus(2)
        #expect(lefts(ws) == [-250, 250, 750])
        #expect(ws.isInView(2))
        #expect(!ws.isInView(1) && !ws.isInView(3), "half of each neighbour shows")
    }

    @Test func `Closing another column leaves a centred column centred`() {
        var ws = strip(5)
        ws.focus(3)
        ws.centerColumn()
        ws.remove(1)
        #expect(lefts(ws) == [-250, 250, 750, 1250])
        ws.remove(5)
        #expect(lefts(ws) == [-250, 250, 750])
        var always = strip(5, center: .always)
        always.focus(3)
        always.remove(1)
        #expect(lefts(always) == [-250, 250, 750, 1250])
    }

    @Test func `A wall on one side still centres on the display`() {
        for walls: Set<Direction> in [[.left], [.right]] {
            var ws = strip(5, width: 0.4, walls: walls, center: .always)
            ws.focus(3)
            #expect(ws.layout().frames[3] == rect(295, 0, 410, 600), "\(walls)")
        }
    }

    @Test func `A tab taking the centred window's place keeps the centring`() {
        var ws = strip(3)
        ws.centerColumn()
        ws.replace(3, with: 9)
        #expect(lefts(ws) == [-750, -250, 250])
        ws.focus(9)
        #expect(lefts(ws) == [-750, -250, 250])
    }


    @Test func `A hold left behind in another layout does not move to the window focused there`() {
        var ws = strip(4)
        ws.focus(3)
        ws.centerColumn()
        ws.setAlgorithm(.dwindle(.tiles))
        ws.focus(1)
        ws.setAlgorithm(.scrolling)
        #expect(ws.centredColumn.isEmpty)
        #expect(lefts(ws) == [-25, 475, 975, 1475], "column 1 fits at the start, as if nothing had been centred")
    }

    @Test func `A hold on overflow set by itself does not move to another window either`() {
        var ws = strip(4, width: 2.0 / 3)
        ws.centerFocusedColumn = .onOverflow
        ws.focus(.left)
        #expect(ws.centredColumn == [3], "3 does not fit beside 4, so it is centred and held")
        ws.setAlgorithm(.dwindle(.tiles))
        ws.focus(1)
        ws.setAlgorithm(.scrolling)
        #expect(lefts(ws) == [-25, 642, 1309, 1976])
    }

    @Test func `Back in the strip with the centred window still focused, its column is centred again`() {
        var ws = strip(4)
        ws.focus(3)
        ws.centerColumn()
        let centred = lefts(ws)
        ws.setAlgorithm(.dwindle(.tiles))
        ws.setAlgorithm(.scrolling)
        #expect(lefts(ws) == centred)
        #expect(ws.centredColumn == [3])
        ws.setColumnWidth(0.3)
        #expect(lefts(ws) == [-650, -150, 350, 650], "still held: a column only fitted would stay at 250, now 300 wide")
    }
}
