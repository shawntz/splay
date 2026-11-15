import Foundation
import Testing
@testable import DinkyConfig

/// `[scrolling]`'s strip keys: centring the focused column, the widths `column-width next` and `prev` step
/// through, and how much of a scrolled-out window stays on screen.
struct StripConfigTests {
    @Test func `The strip keys default to what the layout engine does`() {
        let scrolling = Config().scrolling
        #expect(scrolling.centerFocusedColumn == .never)
        #expect(scrolling.presetColumnWidths == [0.33333, 0.5, 0.66667])
        #expect(scrolling.peek == 25)
        #expect(Config.default.scrolling == scrolling, "the shipped file says the same")
    }

    @Test func `The shipped file shows each strip key`() {
        for line in ["center-focused-column = 'never'", "preset-column-widths = [0.33333, 0.5, 0.66667]", "peek = 25"] {
            #expect(Config.defaultTOML.contains("\n\(line) "), "\(line)")
        }
    }

    @Test func `Center focused column is never, always or on-overflow`() throws {
        for (raw, value) in [("never", CenterFocusedColumn.never), ("always", .always), ("on-overflow", .onOverflow)] {
            #expect(try Config.parse("[scrolling]\ncenter-focused-column = '\(raw)'\n").scrolling.centerFocusedColumn == value)
        }
        assertError("[scrolling]\ncenter-focused-column = 'sometimes'\n", path: "scrolling.center-focused-column", line: 2,
                    contains: "'never', 'always', 'on-overflow'")
        assertError("[scrolling]\ncenter-focused-column = true\n", path: "scrolling.center-focused-column", line: 2,
                    contains: "expected a string")
    }

    @Test func `Preset column widths are a list of shares from 0.1 to 1`() throws {
        func presets(_ value: String) throws -> [Double] {
            try Config.parse("[scrolling]\npreset-column-widths = \(value)\n").scrolling.presetColumnWidths
        }
        #expect(try presets("[0.75, 0.25, 0.5]") == [0.75, 0.25, 0.5], "as written; the strip sorts them")
        #expect(try presets("[0.1, 1.0]") == [0.1, 1])
        #expect(try presets("[1]") == [1], "a whole number is a share too")
        #expect(try presets("[]") == [], "an empty list turns cycling off")
        for bad in ["[0.5, 1.5]", "[0.05]", "[0]"] {
            assertError("[scrolling]\npreset-column-widths = \(bad)\n", path: "scrolling.preset-column-widths", line: 2,
                        contains: "0.1 to 1")
        }
        for bad in ["['half']", "0.5", "[[0.5]]"] {
            assertError("[scrolling]\npreset-column-widths = \(bad)\n", path: "scrolling.preset-column-widths", line: 2,
                        contains: "expected a list of numbers")
        }
    }

    @Test func `Peek is 1 to 100 points`() throws {
        for points in [1, 10, 100] {
            #expect(try Config.parse("[scrolling]\npeek = \(points)\n").scrolling.peek == points)
        }
        // At 0 a parked window would be wholly off screen, and macOS pulls such a window back into view.
        for bad in ["0", "101", "-5"] {
            assertError("[scrolling]\npeek = \(bad)\n", path: "scrolling.peek", line: 2, contains: "1 to 100")
        }
        assertError("[scrolling]\npeek = 12.5\n", path: "scrolling.peek", line: 2, contains: "expected an integer")
    }

    @Test func `The strip keys sit beside column-width`() throws {
        let scrolling = try Config.parse("""
            [scrolling]
            column-width = 0.6
            center-focused-column = 'always'
            preset-column-widths = [0.4, 0.8]
            peek = 40
            """).scrolling
        #expect(scrolling.columnWidth == 0.6)
        #expect(scrolling.centerFocusedColumn == .always)
        #expect(scrolling.presetColumnWidths == [0.4, 0.8])
        #expect(scrolling.peek == 40)
        assertError("[scrolling]\nsliver = 10\n", path: "scrolling.sliver", contains: "unknown key")
    }

    /// SchemaTests checks only the schema's keys, so its values for these are checked here.
    @Test func `The schema's strip entries agree with the config`() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/schemas/splay.json")
        let schema = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let scrolling = try #require((properties["scrolling"] as? [String: Any])?["properties"] as? [String: [String: Any]])
        let defaults = Config().scrolling

        let centring = try #require(scrolling["center-focused-column"])
        #expect(centring["enum"] as? [String] == CenterFocusedColumn.allCases.map(\.rawValue))
        #expect(centring["default"] as? String == defaults.centerFocusedColumn.rawValue)

        let presets = try #require(scrolling["preset-column-widths"])
        #expect(presets["default"] as? [Double] == defaults.presetColumnWidths)
        let items = try #require(presets["items"] as? [String: Any])
        #expect(items["minimum"] as? Double == 0.1)
        #expect(items["maximum"] as? Double == 1)

        let peek = try #require(scrolling["peek"])
        #expect(peek["type"] as? String == "integer")
        #expect(peek["default"] as? Int == defaults.peek)
        #expect(peek["minimum"] as? Int == 1)
        #expect(peek["maximum"] as? Int == 100)
    }
}
