// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PokiCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PokiCore", targets: ["PokiCore"])
    ],
    targets: [
        .target(name: "PokiCore"),
        .testTarget(name: "PokiCoreTests", dependencies: ["PokiCore"])
    ]
)

