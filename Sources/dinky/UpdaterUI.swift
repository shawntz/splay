import AppKit
import DinkyConfig
import Sparkle

// Sparkle shows a scheduled update alert without taking focus while its app is in the background. Splay has no
// Dock icon and is always in the background, so that alert would open behind other windows and go unseen.
// Sparkle's gentle reminders (https://sparkle-project.org/documentation/gentle-reminders/) let the app show such
// an update itself. Splay adds "↑" after the workspace number and puts an item for the update above Check for
// Updates… in the menu, and keeps both until the update session ends. Choosing the item calls Sparkle's
// checkForUpdates, which brings the update it is holding to the front and makes Splay active. So an alert that
// slips behind other windows, as it easily does under a tiling window manager, can always be brought back.

/// The update a scheduled check found, from when Sparkle reports it until its session ends. Kept apart from
/// Sparkle so it can be tested without an updater running.
struct UpdateReminder: Equatable {
    /// The display version of the update, or nil while there is none.
    private(set) var pendingVersion: String?

    /// Whether Sparkle shows a scheduled update itself. It does when it proposes to show the update in immediate
    /// focus, which for an app with no Dock icon it does only within a few seconds of the updater starting, as at
    /// launch, and for an update its feed marks critical. At any other time its alert would open behind other
    /// windows, so only the mark and the menu item tell the user.
    static func sparkleShowsScheduledUpdate(inImmediateFocus immediateFocus: Bool, isCritical: Bool) -> Bool {
        immediateFocus || isCritical
    }

    /// Sparkle is about to show an update or to leave showing it to Splay. One from a scheduled check is marked
    /// either way, since even an alert Sparkle shows can end up behind other windows. One the user asked for is
    /// not: they are looking at it.
    mutating func willShow(version: String, scheduled: Bool) {
        pendingVersion = scheduled ? version : nil
    }

    /// The update session is ending: the update was installed, skipped or put off.
    mutating func clear() {
        pendingVersion = nil
    }

    /// What follows the workspace number in the menu bar.
    var titleMark: String {
        pendingVersion == nil ? "" : "↑"
    }

    /// The title of the menu item that brings the update to the front.
    var menuTitle: String? {
        pendingVersion.map { "Update to \(Brand.displayName) \($0)…" }
    }
}

/// The delegate of Sparkle's standard user driver, which calls it on the main thread.
final class UpdaterUI: NSObject, SPUStandardUserDriverDelegate {
    /// Sparkle keeps only a weak reference to its delegate, so the one the app uses lives here for the life of
    /// the process.
    static let shared = UpdaterUI()

    var reminder = UpdateReminder()

    var supportsGentleScheduledUpdateReminders: Bool { true }

    // Asked for scheduled checks only. Sparkle's header asks that this change nothing, so the update is marked in
    // the next method.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        UpdateReminder.sparkleShowsScheduledUpdate(inImmediateFocus: immediateFocus, isCritical: update.isCriticalUpdate)
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        reminder.willShow(version: update.displayVersionString, scheduled: !state.userInitiated)
    }

    // Not cleared when the alert first gets attention: the alert can still slip behind other windows after
    // that, and the item is then the way back to it.
    func standardUserDriverWillFinishUpdateSession() {
        reminder.clear()
    }

    /// The menu item for the update, or nil while there is none.
    @MainActor func menuItem(target: AnyObject, action: Selector) -> NSMenuItem? {
        guard let title = reminder.menuTitle else { return nil }
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }
}
