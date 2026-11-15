import Testing
@testable import DinkyCommands

private func parse(_ s: String) throws -> Command { try Command.parse(s) }

/// The scrolling strip's commands: centring and widening the focused column, preset and set widths, and focus at
/// either end of the strip.
struct StripCommandTests {
    @Test func `Center column and maximize column take no arguments`() throws {
        #expect(try parse("center-column") == .centerColumn)
        #expect(try parse("maximize-column") == .maximizeColumn)
        for bad in ["center-column now", "maximize-column 1"] {
            #expect(throws: CommandError.self) { try parse(bad) }
        }
    }

    @Test func `Column width steps through the presets or sets a share`() throws {
        #expect(try parse("column-width next") == .columnWidth(.next))
        #expect(try parse("column-width prev") == .columnWidth(.prev))
        #expect(try parse("column-width 0.5") == .columnWidth(.share(0.5)))
        #expect(try parse("column-width 0.1") == .columnWidth(.share(0.1)))
        #expect(try parse("column-width 1") == .columnWidth(.share(1)))
        #expect(try parse("column-width 1.0") == .columnWidth(.share(1)))
    }

    @Test(arguments: ["column-width", "column-width next prev", "column-width wider", "column-width previous",
                      "column-width 1e-1", "column-width +0.5", "column-width -0.5", "column-width nan", "column-width 0.5.5",
                      "column-width ."])
    func `Column width takes next, prev or a decimal`(line: String) {
        #expect(throws: CommandError.self) { try parse(line) }
    }

    @Test(arguments: ["0", "0.05", "0.09", "1.01", "1.5", "2"])
    func `A share outside 0.1 to 1 says so`(share: String) {
        let error = #expect(throws: CommandError.self) { try parse("column-width \(share)") }
        #expect(error?.description.contains("0.1 to 1") == true, "\(String(describing: error))")
        #expect(error?.description.contains("'column-width \(share)'") == true, "\(String(describing: error))")
    }

    @Test func `Focus column goes to the first or the last column`() throws {
        #expect(try parse("focus-column first") == .focusColumn(.first))
        #expect(try parse("focus-column last") == .focusColumn(.last))
        for bad in ["focus-column", "focus-column middle", "focus-column left", "focus-column 1", "focus-column first last"] {
            #expect(throws: CommandError.self) { try parse(bad) }
        }
    }

    @Test func `The help gives each strip command its syntax`() {
        let syntax = Set(Command.all.map(\.syntax))
        for line in ["center-column", "column-width <next|prev|SHARE>", "maximize-column", "focus-column <first|last>"] {
            #expect(syntax.contains(line), "\(line)")
        }
    }
}
