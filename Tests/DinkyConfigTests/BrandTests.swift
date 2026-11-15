import Foundation
import Testing
@testable import DinkyConfig

/// Upstream Dinky can stay installed beside Splay, so the two must never share a file, a socket or a name.
struct BrandTests {
    @Test func `Every location is Splay's own`() {
        let locations = [Brand.configPath, Brand.socketName, Brand.supportFolder, Brand.logPath]
        // Spelled out, not searched for: "splay" is also inside "display", so a substring test would prove nothing.
        #expect(locations == [".config/splay/splay.toml", "splay.sock", "splay", "Library/Logs/splay.log"])
        for location in locations {
            #expect(!location.lowercased().contains("dinky"), "\(location)")
        }
        #expect(Config.userConfigURL.path.hasSuffix("/" + Brand.configPath))
        #expect(Brand.envPrefix == "SPLAY_")
    }

    @Test func `Upstream's names are not Splay's`() {
        #expect(Brand.upstreamProcessName != Brand.name, "the rival-tiler check would find this app")
        #expect(Brand.upstreamBundleID != Brand.bundleID)
        #expect(!Brand.bundleID.lowercased().contains("dinky"))
    }
}
