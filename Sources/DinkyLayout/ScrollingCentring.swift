import CoreGraphics

// Centring the focused column on the display, after niri's `center-focused-column` and `center-column`. While a
// column is to be centred the scroll follows from it rather than from `scrollOffset`, so the centring survives
// whatever resizes the strip around it and lets an end column leave empty space beside it.

/// When focusing a column of the strip centres it on the display, as niri's `center-focused-column`.
public enum CenterFocusedColumn: Equatable, Sendable {
    /// Scroll as little as shows the column whole.
    case never
    /// Centre every column focus goes to.
    case always
    /// Centre a column that does not fit in view beside the one focus came from; else as `never`.
    case onOverflow
}

extension Workspace {
    /// Centre the focused column on the display now, whatever `centerFocusedColumn` says, and keep it centred while
    /// focus stays in it. False when nothing moved: a lone column, a column already centred, or no strip.
    @discardableResult
    public mutating func centerColumn() -> Bool {
        guard isScrolling, let focused, let index = root.path(of: focused)?.first else { return false }
        let before = tiledLayout()
        centredColumn = Set(root.children[index].windows)
        reveal(focused)
        return tiledLayout() != before
    }

    /// The scroll offset that centres the focused column's windows inside the outer gaps, while it is to be
    /// centred: always, or since `centerColumn()` or the on-overflow rule centred it. Nil otherwise.
    func centredOffset(for spans: [(start: CGFloat, width: CGFloat)], in area: CGRect) -> CGFloat? {
        guard isScrolling, let focused, let index = root.path(of: focused)?.first, spans.indices.contains(index),
              centerFocusedColumn == .always || !centredColumn.isDisjoint(with: root.children[index].windows)
        else { return nil }
        // The half gaps either side are the column's but not its windows', and an end column has only one.
        let gap = gaps.horizontal, span = spans[index]
        let lead = index > 0 ? gap / 2 : 0, trail = index < spans.count - 1 ? gap / 2 : 0
        return (area.minX + span.start + (lead + span.width - trail) / 2 - gaps.inset(bounds).midX).rounded()
    }

    /// Before focus moves to `id`: a centred column stays centred while focus stays in it, and focus leaving it
    /// for another column ends that. Then with `onOverflow` the new column is centred if it does not fit in view
    /// beside the one focus came from. Refocusing the focused window, as the app does before every command, or
    /// focus arriving from nowhere, as when the focused window closed, leaves the scroll to the fit.
    mutating func updateCentring(focusing id: WindowID) {
        guard isScrolling, let index = root.path(of: id)?.first else { return }
        let area = stripArea, spans = columnSpans(in: area)
        // A fit after the centring ends starts from what shows now.
        if let centred = centredOffset(for: spans, in: area) { scrollOffset = centred }
        let column = Set(root.children[index].windows)
        let previous = focused.flatMap { root.path(of: $0)?.first }
        if previous.map({ $0 == index }) ?? !centredColumn.isDisjoint(with: column) {
            // Focus moving in another layout ends nothing there, so a column centred before the strip gave way to
            // one may not be this one when the strip returns. Only this column's own centring carries on.
            centredColumn = centredColumn.isDisjoint(with: column) ? [] : column
            return
        }
        centredColumn = []
        guard centerFocusedColumn == .onOverflow, let previous else { return }
        // As niri does, the neighbour on the side focus came from stands in for the column it came from, so a jump
        // to a column that fits beside its neighbour fits too.
        let source = spans[previous < index ? index - 1 : index + 1], target = spans[index]
        let start = min(source.start, target.start)
        let end = max(source.start + source.width, target.start + target.width)
        if end - start > area.width { centredColumn = column }
    }
}
