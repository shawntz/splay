import CoreGraphics

// Column widths by command, after niri's `switch-preset-column-width`, `set-column-width` and `maximize-column`.
// Each ends fullscreen as a resize does, keeps every window of the column at one width, shows the column whole
// afterwards, and undoes a width nothing shows, so it does not drift out of sight. Widths are shares of the width
// between the gutters, as `columnWidth` is.

extension Workspace {
    /// How near a preset a width counts as that preset: about a hundredth, so the default 0.49 is a half.
    static let presetSlack = 0.015

    /// Give the focused column the next of `presetColumnWidths` wider than its width, after the widest the
    /// narrowest, or with `backward` the next narrower, after the narrowest the widest. A preset nothing would show,
    /// as when a minimum size holds the column wider, is passed over. False when no preset changes anything: a lone
    /// column, which fills the screen, no presets, or no strip.
    @discardableResult
    public mutating func cycleColumnWidth(backward: Bool = false) -> Bool {
        let presets = presetColumnWidths.sorted()
        guard isScrolling, !presets.isEmpty else { return false }
        isFullscreen = false
        guard let focused, let column = root.path(of: focused)?.first, root.children.count > 1 else { return false }
        let width = width(ofColumn: column), count = presets.count
        let first = backward
            ? presets.lastIndex { $0 < width - Self.presetSlack } ?? count - 1
            : presets.firstIndex { $0 > width + Self.presetSlack } ?? 0
        for step in 0..<count {
            let preset = presets[(first + (backward ? count - step : step)) % count]
            if applyColumnWidth(preset, to: column) { return true }
        }
        return false
    }

    /// Give the focused column `share` of the width between the gutters, kept between the narrowest a column goes
    /// and the whole of it. False when nothing visibly changed.
    @discardableResult
    public mutating func setColumnWidth(_ share: Double) -> Bool {
        guard isScrolling else { return false }
        isFullscreen = false
        guard let focused, let column = root.path(of: focused)?.first else { return false }
        return applyColumnWidth(share, to: column)
    }

    /// Widen the focused column to the whole width between the gutters, keeping the width it had; again, give it
    /// that width back. Any other width change, or the window leaving, forgets the kept width, and the next toggle
    /// widens again. False when nothing visibly changed, as for a lone column.
    @discardableResult
    public mutating func toggleMaximizeColumn() -> Bool {
        guard isScrolling else { return false }
        isFullscreen = false
        guard let focused, let column = root.path(of: focused)?.first else { return false }
        let windows = root.children[column].windows
        // Only a column shown at the whole width gets its kept width back. A swap can leave a stack showing another
        // window's width while one of its windows still keeps a width from the column it was maximised in: that
        // kept width is stale, and so is one that would show nothing. Maximise then.
        if width(ofColumn: column) == 1, let kept = windows.compactMap({ unmaximizedWidths[$0] }).first,
           applyColumnWidth(kept, to: column) {
            return true
        }
        let width = width(ofColumn: column)
        guard applyColumnWidth(1, to: column) else { return false }
        for id in windows { unmaximizedWidths[id] = width }
        return true
    }

    /// Give column `index` the width `share` and show the focused window's column whole. A width nothing shows is
    /// undone, widths kept for maximised columns included. False then.
    private mutating func applyColumnWidth(_ share: Double, to index: Int) -> Bool {
        let (widths, kept, offset, before) = (columnWidths, unmaximizedWidths, scrollOffset, tiledLayout())
        setWidth(ofColumn: index, share)
        if let focused { reveal(focused) }
        guard tiledLayout() == before else { return true }
        columnWidths = widths
        unmaximizedWidths = kept
        scrollOffset = offset
        return false
    }

    /// A column's width set any other way, or its window leaving, forgets the width maximising kept for it.
    /// A window only gaining a width, as one taking another's place does, keeps it.
    mutating func forgetUnmaximizedWidths(changedFrom old: [WindowID: Double]) {
        guard !unmaximizedWidths.isEmpty else { return }
        unmaximizedWidths = unmaximizedWidths.filter { id, _ in old[id] == nil || columnWidths[id] == old[id] }
    }

    /// `new` takes `old`'s place, as another tab of its group: it keeps the width maximising kept and the
    /// centring. Called before `old`'s width moves to `new`.
    mutating func handOver(_ old: WindowID, to new: WindowID) {
        if let width = unmaximizedWidths.removeValue(forKey: old) { unmaximizedWidths[new] = width }
        if centredColumn.remove(old) != nil { centredColumn.insert(new) }
    }
}
