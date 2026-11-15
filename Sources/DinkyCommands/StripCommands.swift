// Commands for the scrolling strip, after niri's `center-column`, `switch-preset-column-width`,
// `set-column-width`, `maximize-column` and `focus-column-first` and `-last`. They act on the focused window's
// column, and in another layout have nothing to do.

/// `column-width`: the next wider or narrower of `[scrolling] preset-column-widths`, or a share of the width.
public enum ColumnWidth: Equatable, Sendable {
    case next, prev
    case share(Double)
}

/// `focus-column`: the strip's first or last column.
public enum ColumnEnd: String, Equatable, Sendable {
    case first, last
}

extension Command {
    /// The strip commands' arguments, as `parse` reads every other command's: nil when they don't fit.
    static func parseStrip(_ name: String, _ args: [String]) throws(CommandError) -> Command? {
        let none = args.isEmpty
        let one = args.count == 1 ? args[0] : nil
        switch name {
        case "center-column":
            return none ? .centerColumn : nil
        case "column-width":
            return try one.flatMap(ColumnWidth.init).map { .columnWidth($0) }
        case "maximize-column":
            return none ? .maximizeColumn : nil
        case "focus-column":
            return one.flatMap(ColumnEnd.init(rawValue:)).map { .focusColumn($0) }
        default:
            return nil
        }
    }
}

extension ColumnWidth {
    /// `next`, `prev` or a plain decimal such as 0.5; a decimal outside 0.1 to 1 throws, saying so.
    init?(_ word: String) throws(CommandError) {
        switch word {
        case "next": self = .next
        case "prev": self = .prev
        default:
            guard word.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), let share = Double(word) else { return nil }
            // The range [scrolling] column-width takes, which the strip clamps a column to anyway.
            guard (0.1...1).contains(share) else { throw CommandError(input: "", message: "a share must be 0.1 to 1") }
            self = .share(share)
        }
    }
}
