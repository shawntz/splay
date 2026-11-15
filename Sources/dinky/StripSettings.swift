import CoreGraphics
import DinkyConfig
import DinkyLayout

// The strip's [scrolling] keys beyond column-width, in the layout engine's terms. The coordinator sets them
// wherever it sets column-width: on a new tree and on every tree when the config is applied.
extension Workspace {
    mutating func applyStrip(_ scrolling: Scrolling) {
        centerFocusedColumn = scrolling.layoutCentring
        presetColumnWidths = scrolling.presetColumnWidths
        sliver = CGFloat(scrolling.peek)
    }
}

extension Scrolling {
    /// When focusing a column centres it, in the layout engine's terms.
    var layoutCentring: DinkyLayout.CenterFocusedColumn {
        switch centerFocusedColumn {
        case .never: .never
        case .always: .always
        case .onOverflow: .onOverflow
        }
    }
}
