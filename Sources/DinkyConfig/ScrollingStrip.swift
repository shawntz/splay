// [scrolling] keys for the strip beyond column-width, after niri's: centring the focused column, the preset
// widths `column-width next` and `prev` step through, and how much of a scrolled-out window stays on screen.

/// When focusing a column centres it on the display, as niri's `center-focused-column`.
public enum CenterFocusedColumn: String, CaseIterable {
    case never, always
    case onOverflow = "on-overflow"
}

extension Scrolling {
    /// Reads the strip keys of a `[scrolling]` table, before `init` rejects the keys nobody read.
    mutating func readStrip(_ t: Table) throws {
        centerFocusedColumn = try t.choice("center-focused-column") ?? centerFocusedColumn
        presetColumnWidths = try t.doubles("preset-column-widths") ?? presetColumnWidths
        if let width = presetColumnWidths.first(where: { !(0.1...1).contains($0) }) {
            throw ConfigError(path: t.path("preset-column-widths"), "each must be 0.1 to 1, not \(width)")
        }
        peek = try t.int("peek") ?? peek
        // At 0 a scrolled-out window would be wholly off screen, and macOS pulls such a window back into view.
        guard (1...100).contains(peek) else { throw ConfigError(path: t.path("peek"), "must be 1 to 100") }
    }
}
