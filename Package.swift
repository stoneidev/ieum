// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ieum",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "caption-cli", targets: ["CaptionCLI"]),
        .executable(name: "Ieum", targets: ["OverlayApp"]),
        .executable(name: "caption-bench", targets: ["CaptionBench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Audio capture, speech engines, output formatting and script recording, shared by the CLI and the app.
        .target(
            name: "CaptionCore",
            path: "Sources/CaptionCore"
        ),
        .executableTarget(
            name: "CaptionCLI",
            dependencies: [
                "CaptionCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CaptionCLI",
            linkerSettings: [
                // Embed Info.plist in __TEXT,__info_plist so TCC can read the usage descriptions.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ]),
            ]
        ),
        // Menu-bar live-subtitle overlay. Packaged into an .app by `make app`.
        .executableTarget(
            name: "OverlayApp",
            dependencies: ["CaptionCore"],
            path: "Sources/OverlayApp"
        ),
        // Developer tool: repeatable latency / accuracy / cost measurements (`make bench`).
        .executableTarget(
            name: "CaptionBench",
            dependencies: [
                "CaptionCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CaptionBench"
        ),
        .testTarget(
            name: "CaptionCoreTests",
            dependencies: ["CaptionCore"],
            path: "Tests/CaptionCoreTests"
        ),
    ]
)
