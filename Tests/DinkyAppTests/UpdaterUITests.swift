import AppKit
import DinkyConfig
import Foundation
import Sparkle
import Testing
@testable import dinky

/// How Splay marks an update a scheduled check found, in the menu bar and the menu, until its session ends. No updater is started and no Sparkle window is opened. Sparkle's calls are made by hand here,
/// with the arguments its header describes.
struct UpdaterUITests {
    @Test func `Sparkle shows a scheduled update itself only in immediate focus, or when it is critical`() {
        #expect(UpdateReminder.sparkleShowsScheduledUpdate(inImmediateFocus: true, isCritical: false))
        #expect(!UpdateReminder.sparkleShowsScheduledUpdate(inImmediateFocus: false, isCritical: false))
        #expect(UpdateReminder.sparkleShowsScheduledUpdate(inImmediateFocus: false, isCritical: true))
    }

    @Test func `An update from a scheduled check is marked with its version`() {
        var reminder = UpdateReminder()
        reminder.willShow(version: "0.2", scheduled: true)
        #expect(reminder.pendingVersion == "0.2")
    }

    @Test func `An update the user asked for is not marked`() {
        var reminder = UpdateReminder()
        reminder.willShow(version: "0.2", scheduled: true)
        reminder.willShow(version: "0.2", scheduled: false)
        #expect(reminder.pendingVersion == nil)
    }

    @Test func `The delegate takes on scheduled reminders and answers Sparkle's question by immediate focus`() {
        let ui = UpdaterUI()
        #expect(ui.supportsGentleScheduledUpdateReminders)
        #expect(ui.standardUserDriverShouldHandleShowingScheduledUpdate(SUAppcastItem.empty(), andInImmediateFocus: true))
        #expect(!ui.standardUserDriverShouldHandleShowingScheduledUpdate(SUAppcastItem.empty(), andInImmediateFocus: false))
        #expect(ui.reminder.pendingVersion == nil, "the question changes nothing")
    }

    @Test func `A scheduled update is marked whether Sparkle shows it or leaves it to Splay`() throws {
        let state = try scheduledCheckState()
        for sparkleShows in [false, true] {
            let ui = UpdaterUI()
            ui.standardUserDriverWillHandleShowingUpdate(sparkleShows, forUpdate: try item(build: "42", version: "0.2"), state: state)
            #expect(ui.reminder.pendingVersion == "0.2", "the version people read, not the build number")
        }
    }

    @Test func `Only the end of the session lets go of the update`() throws {
        let ui = UpdaterUI()
        ui.standardUserDriverWillHandleShowingUpdate(false, forUpdate: try item(build: "42", version: "0.2"), state: try scheduledCheckState())
        #expect(ui.reminder.pendingVersion != nil)
        #expect(!ui.responds(to: NSSelectorFromString("standardUserDriverDidReceiveUserAttentionForUpdate:")),
                "attention must not clear it: the alert can slip behind other windows afterwards")
        ui.standardUserDriverWillFinishUpdateSession()
        #expect(ui.reminder.pendingVersion == nil)
    }

    /// Sparkle checks for each optional method by selector before calling it, so a Swift name that misses the
    /// header's selector would be skipped without an error.
    @Test func `The delegate answers to the selectors in Sparkle's header`() {
        let ui = UpdaterUI()
        for name in [
            "supportsGentleScheduledUpdateReminders",
            "standardUserDriverShouldHandleShowingScheduledUpdate:andInImmediateFocus:",
            "standardUserDriverWillHandleShowingUpdate:forUpdate:state:",
            "standardUserDriverWillFinishUpdateSession",
        ] {
            #expect(ui.responds(to: NSSelectorFromString(name)), "\(name)")
        }
    }

    @Test func `The menu bar shows an arrow after the workspace number only while an update waits`() {
        var reminder = UpdateReminder()
        #expect(reminder.titleMark == "")
        reminder.willShow(version: "0.2", scheduled: true)
        #expect(reminder.titleMark == "↑")
        reminder.clear()
        #expect(reminder.titleMark == "")
    }

    @Test @MainActor func `The menu offers the update by name and version, and nothing while there is none`() throws {
        let ui = UpdaterUI()
        let target = NSObject()
        let action = NSSelectorFromString("checkForUpdates:")
        #expect(ui.reminder.menuTitle == nil)
        #expect(ui.menuItem(target: target, action: action) == nil)

        ui.reminder.willShow(version: "0.2", scheduled: true)
        #expect(ui.reminder.menuTitle == "Update to \(Brand.displayName) 0.2…")
        let item = try #require(ui.menuItem(target: target, action: action))
        #expect(item.title == "Update to \(Brand.displayName) 0.2…")
        #expect(item.action == action)
        #expect(item.target === target)
    }

    /// An appcast item as a feed gives it, where the build number and the version people read differ. Sparkle's
    /// dictionary initializer is public but deprecated, so it is reached through a protocol to keep the build
    /// free of warnings.
    private func item(build: String, version: String) throws -> SUAppcastItem {
        let make = SUAppcastItem.self as AppcastItemFromDictionary.Type
        let fields: [AnyHashable: Any] = ["sparkle:version": build, "sparkle:shortVersionString": version, "link": "https://example.com"]
        return try #require(make.init(dictionary: fields) as? SUAppcastItem)
    }

    /// Sparkle's header makes the state's initializer unavailable, but the state supports secure coding. An archive
    /// that only names the class decodes to a state with nothing set, so one the user did not start, as for a
    /// scheduled check.
    private func scheduledCheckState() throws -> SPUUserUpdateState {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName(NSStringFromClass(SPUUserUpdateState.self), for: EmptyArchive.self)
        archiver.encode(EmptyArchive(), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        let state = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: SPUUserUpdateState.self, from: archiver.encodedData))
        #expect(!state.userInitiated)
        return state
    }
}

private protocol AppcastItemFromDictionary { init?(dictionary: [AnyHashable: Any]) }
extension SUAppcastItem: AppcastItemFromDictionary {}

/// Writes no fields, standing in for a class in an archive.
@objc(UpdaterUITestsEmptyArchive) private final class EmptyArchive: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    override init() {}
    init?(coder: NSCoder) {}
    func encode(with coder: NSCoder) {}
}
