import CoreGraphics

// Moving focus along the strip as niri does: a column is entered at the window last focused in it, not the one
// beside the window focus leaves, and focus can jump to either end of the strip.

extension Workspace {
    /// Focus the window at the `side` edge. In the strip, left and right go to the first and last column, at its
    /// most recently focused window; elsewhere, and up and down, the window `edgeWindow` finds. False when focus
    /// did not move.
    @discardableResult
    public mutating func focusEdge(_ side: Direction) -> Bool {
        let target = isScrolling && side.orientation == .horizontal && !root.children.isEmpty
            ? mostRecentWindow(inColumn: side.isForward ? root.children.count - 1 : 0)
            : edgeWindow(side)
        guard let target, target != focused else { return false }
        focus(target)
        return true
    }

    /// Where a step from `id` to the neighbour `target` lands: in the strip, a step into another column lands on
    /// that column's most recently focused window. Steps within a column, which up and down always are, and steps
    /// in other layouts keep `target`.
    func columnEntry(_ target: WindowID?, from id: WindowID) -> WindowID? {
        guard isScrolling, let target, let column = root.path(of: target)?.first,
              column != root.path(of: id)?.first else { return target }
        return mostRecentWindow(inColumn: column)
    }

    /// The window last focused in column `index`.
    func mostRecentWindow(inColumn index: Int) -> WindowID? {
        switch root.children[index] {
        case .window(let id): id
        case .container(let c): c.mostRecentWindow
        }
    }
}
