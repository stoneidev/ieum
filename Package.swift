// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac-stt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mac-stt", targets: ["mac-stt"]),
        .executable(name: "STTOverlay", targets: ["STTOverlay"]),
        .executable(name: "stt-bench", targets: ["STTBench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Audio capture, speech engines, output formatting and script recording, shared by the CLI and the app.
        .target(
            name: "MacSTTCore",
            path: "Sources/MacSTTCore"
        ),
        .executableTarget(
            name: "mac-stt",
            dependencies: [
                "MacSTTCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MacSTT",
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
            name: "STTOverlay",
            dependencies: ["MacSTTCore"],
            path: "Sources/STTOverlay"
        ),
        // Developer tool: repeatable latency / accuracy / cost measurements (`make bench`).
        .executableTarget(
            name: "STTBench",
            dependencies: [
                "MacSTTCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/STTBench"
        ),
        .testTarget(
            name: "MacSTTTests",
            dependencies: ["MacSTTCore"],
            path: "Tests/MacSTTTests"
        ),
    ]
)
