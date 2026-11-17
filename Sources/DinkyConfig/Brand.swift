// The names a user or macOS sees, kept here so renaming the app is one file. Modules, types, symbols and
// queue labels keep upstream's dinky names, so merging upstream stays cheap.
public enum Brand {
    /// The command line name, in commands, paths and message prefixes.
    public static let name = "splay"
    /// The name in sentences in windows, menus and alerts.
    public static let displayName = "Splay"
    public static let bundleID = "com.shawnschwartz.splay"

    /// Relative to the home folder.
    public static let configPath = ".config/\(name)/\(name).toml"
    /// The folder in ~/Library/Application Support.
    public static let supportFolder = name
    /// Relative to the home folder.
    public static let logPath = "Library/Logs/\(name).log"
    /// The socket's file name in $TMPDIR.
    public static let socketName = "\(name).sock"
    /// Hook environment variables start with this, as in SPLAY_WORKSPACE.
    public static let envPrefix = "\(name.uppercased())_"
    /// The page that lists what each release changed.
    public static let changelogURL = "https://shawntz.github.io/splay/changelog/"

    /// Upstream Dinky can be installed beside this app with its own paths. Running both makes two tilers
    /// fight over the same windows, so its process counts as another tiler.
    public static let upstreamProcessName = "dinky"
    public static let upstreamDisplayName = "Dinky"
    public static let upstreamBundleID = "com.brnbw.dinky"
}
