// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ieum",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ieum-cli", targets: ["ieum-cli"]),
        .executable(name: "Ieum", targets: ["Ieum"]),
        .executable(name: "ieum-bench", targets: ["IeumBench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Audio capture, speech engines, output formatting and script recording, shared by the CLI and the app.
        .target(
            name: "IeumCore",
            path: "Sources/IeumCore"
        ),
        .executableTarget(
            name: "ieum-cli",
            dependencies: [
                "IeumCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/IeumCLI",
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
            name: "Ieum",
            dependencies: ["IeumCore"],
            path: "Sources/Ieum"
        ),
        // Developer tool: repeatable latency / accuracy / cost measurements (`make bench`).
        .executableTarget(
            name: "IeumBench",
            dependencies: [
                "IeumCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/IeumBench"
        ),
        .testTarget(
            name: "IeumTests",
            dependencies: ["IeumCore"],
            path: "Tests/IeumTests"
        ),
    ]
)
