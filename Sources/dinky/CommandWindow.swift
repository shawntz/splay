import DinkyLayout
import Foundation

// Walking the strip with quick or held presses. Focusing another app's window is asynchronous, so for a moment
// after `focus(_:)` macOS still reports the window before it in front. A command starting from that window would
// pick the same neighbour again and go nowhere, so while the focus grace lasts a command starts from the window
// just focused, the one `syncFocus` already keeps the tree on. Every command that acts on the focused window
// does, so quick presses act on the same window while it stays tiled.
extension Coordinator {
    /// The window a command given none acts on.
    var commandWindow: WindowID { justFocusedWindow ?? focusedWindow }

    /// The window just focused, while its grace lasts and it is still tiled in sight. Nil when the front window
    /// macOS reports is the one to go by.
    var justFocusedWindow: WindowID? {
        Self.justFocused(focusing, now: Date(), isTiled: isTiledInSight)
    }

    /// Whether the keyboard is on the window or on its way to it.
    func hasFocus(_ id: WindowID) -> Bool {
        id == justFocusedWindow || id == focusedWindow
    }

    /// Whether the window is in a tree on a Space still on screen, on a display that still has the focus, as far
    /// as the display model knows. A Space switched away from takes the window just focused with it, and so does
    /// focus given to a display with no window on it: a command there would switch or jump back.
    func isTiledInSight(_ id: WindowID) -> Bool {
        guard let space = placements[id]?.space else { return false }
        guard let display = displays.display(containingSpace: space) else { return true }
        return display.currentSpaceID == space && (displays.focusOverride ?? display.uuid) == display.uuid
    }

    /// The window just focused, while its grace lasts and it is still tiled; nil when the front window macOS
    /// reports is the one to use.
    static func justFocused(_ focusing: (id: WindowID, until: Date)?, now: Date, isTiled: (WindowID) -> Bool) -> WindowID? {
        guard let focusing, now < focusing.until, isTiled(focusing.id) else { return nil }
        return focusing.id
    }
}

/// The window a command given none moves, floats or lays out: the coordinator's command window, falling back as
/// `focusedWindowID` does to the front app's key window.
func commandWindowID() -> WindowID {
    if let id = AppState.shared.coordinator?.commandWindow, id != 0 { return id }
    return frontWindowID()
}
