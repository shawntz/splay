// swift-tools-version:6.0
import PackageDescription

// Renders the demo animations in docs/assets/demo from Splay's layout engine. A package of its own, so the app's
// `swift build` never compiles it. Build it in debug: it reads engine internals through `@testable import`.
let package = Package(
    name: "DemoReel",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(name: "dinky", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "demoreel",
            dependencies: [
                .product(name: "DinkyLayout", package: "dinky"),
                .product(name: "DinkyConfig", package: "dinky"),
                .product(name: "DinkyCommands", package: "dinky"),
            ],
            path: "Sources/DemoReel",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
