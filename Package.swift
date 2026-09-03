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
            name: "ButterflyCore",
            dependencies: [
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
