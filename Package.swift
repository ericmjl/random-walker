// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RandomWalkerCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "RandomWalkerCore", targets: ["RandomWalkerCore"]),
    ],
    targets: [
        .target(
            name: "RandomWalkerCore",
            path: "RandomWalkerCore"
        ),
        .testTarget(
            name: "RandomWalkerCoreTests",
            dependencies: ["RandomWalkerCore"],
            path: "RandomWalkerCoreTests"
        ),
    ]
)
