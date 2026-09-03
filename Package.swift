// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Butterfly",
    platforms: [
        .macOS(.v13)
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
        .package(url: "https://github.com/ddddxxx/SwiftyOpenCC.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "CButterflyWhisper",
            path: "Sources/CButterflyWhisper",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags([
                    "-I/opt/homebrew/include",
                    "-I/usr/local/include"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L/opt/homebrew/lib",
                    "-L/usr/local/lib"
                ]),
                .linkedLibrary("whisper"),
                .linkedLibrary("ggml"),
                .linkedLibrary("ggml-base")
            ]
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
        )
    ]
)
