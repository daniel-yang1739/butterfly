// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Butterfly",
    platforms: [
        .macOS("13.3")
    ],
    products: [
        .library(
            name: "ButterflyCore",
            targets: ["ButterflyCore"]
        ),
        .executable(
            name: "butterfly-cli",
            targets: ["ButterflyCLI"]
        ),
        .executable(
            name: "ButterflyApp",
            targets: ["ButterflyApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ddddxxx/SwiftyOpenCC.git", exact: "1.0.1")
    ],
    targets: [
        .target(
            name: "CButterflyWhisper",
            dependencies: ["WhisperFramework"],
            path: "Sources/CButterflyWhisper",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ButterflyCore",
            dependencies: [
                "CButterflyWhisper",
                .product(name: "OpenCC", package: "SwiftyOpenCC")
            ],
            path: "Sources/ButterflyCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "ButterflyCLI",
            dependencies: ["ButterflyCore"],
            path: "Sources/ButterflyCLI"
        ),
        .executableTarget(
            name: "ButterflyApp",
            dependencies: ["ButterflyCore"],
            path: "Sources/ButterflyApp"
        ),
        .testTarget(
            name: "ButterflyTests",
            dependencies: ["ButterflyCore"],
            path: "Tests/ButterflyTests"
        ),
        .binaryTarget(
            name: "WhisperFramework",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.2/whisper-v1.9.2-xcframework.zip",
            checksum: "af74fed13ea7f2d5ca2a39d9f58ec177713fafd7cab63aef4e27b79f3ceca80b"
        )
    ]
)
