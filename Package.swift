// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RowPlayStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RowPlayStudio", targets: ["RowPlayStudio"]),
        .library(name: "RowPlayCore", targets: ["RowPlayCore"])
    ],
    targets: [
        .target(name: "RowPlayCore"),
        .executableTarget(
            name: "RowPlayStudio",
            dependencies: ["RowPlayCore"]
        ),
        .testTarget(
            name: "RowPlayCoreTests",
            dependencies: ["RowPlayCore"],
            resources: [.copy("Fixtures/performance-predictor-parity.json")]
        )
    ]
)

