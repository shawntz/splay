import CoreGraphics

// The strip's scroll is kept in points from its start, so a column that closes, grows or shrinks left of the
// focused one would slide the focused one along, out of view even. As in niri, the focused column stays where it is
// on screen when the strip leaves room for it there, and in view whatever happens.

extension Workspace {
    /// Where the focused column's left edge is on screen, with its windows held to `minimums` if given. Nil outside
    /// the strip or with nothing focused.
    func focusedColumnX(minimums: [WindowID: CGSize]? = nil) -> CGFloat? {
        guard isScrolling, let focused, let index = root.path(of: focused)?.first else { return nil }
        let area = stripArea, spans = columnSpans(in: area, minimums: minimums)
        return area.minX + spans[index].start - offset(for: spans, in: area)
    }

    /// Scroll the focused column's left edge back to `x`, as far as the ends of the strip let it go, then as little
    /// more as shows it whole. Nothing for nil.
    mutating func keepFocusedColumn(at x: CGFloat?) {
        guard let x, let focused, let index = root.path(of: focused)?.first else { return }
        let area = stripArea
        scrollOffset = area.minX + columnSpans(in: area)[index].start - x
        reveal(focused)
    }

    /// New minimum sizes resize columns: keep the focused column where the old ones had it.
    mutating func keepFocusedColumn(sizedBy old: [WindowID: CGSize]) {
        guard isScrolling, old != minimumSizes else { return }
        keepFocusedColumn(at: focusedColumnX(minimums: old))
    }

    /// The strip's room changed, with the display, the Dock, the gaps, the walls or the sliver: every column is a
    /// share of it, so show the focused one whole again. Only the scroll changes, so observers calling this do not
    /// set off one another.
    mutating func keepFocusedColumnInView() {
        if let focused { reveal(focused) }
    }
}
