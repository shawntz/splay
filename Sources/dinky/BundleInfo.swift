import DinkyConfig
import Foundation

// The command line is mostly run through a link to the executable inside the app, as `just install` makes one.
// A process started that way has no bundle of its own, so the app's Info.plist is found from where the link leads.

/// The Info.plist of the app whose `Contents/MacOS` holds the executable at `url`, links followed. Nil for an
/// executable outside an app, such as a bare SwiftPM build.
func bundleInfo(ofExecutable url: URL) -> [String: Any]? {
    let app = url.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard app.pathExtension == "app" else { return nil }
    return Bundle(url: app)?.infoDictionary
}

/// What `version` prints: the name, then the version and build number of the app the executable belongs to, of
/// `fallback` when it belongs to none, or `dev (0)`.
func versionLine(executable: URL?, fallback: [String: Any]?) -> String {
    let info = executable.flatMap(bundleInfo(ofExecutable:)) ?? fallback
    return "\(Brand.name) \(info?["CFBundleShortVersionString"] ?? "dev") (\(info?["CFBundleVersion"] ?? "0"))"
}
