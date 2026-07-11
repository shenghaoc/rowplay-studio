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
        .target(
            name: "RowPlayCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "RowPlayStudio",
            dependencies: ["RowPlayCore"]
        ),
        .testTarget(
            name: "RowPlayCoreTests",
            dependencies: ["RowPlayCore"],
            resources: [
                .copy("Fixtures/duration-band-parity.json"),
                .copy("Fixtures/performance-predictor-parity.json"),
                .copy("Fixtures/Concept2/rower-steady.fixture.json"),
                .copy("Fixtures/Concept2/rower-interval.fixture.json"),
                .copy("Fixtures/Concept2/ski-steady.fixture.json"),
                .copy("Fixtures/Concept2/bike-steady.fixture.json"),
                .copy("Fixtures/Concept2/REDACTION.md"),
            ]
        ),
        .testTarget(
            name: "RowPlayStudioTests",
            dependencies: ["RowPlayStudio", "RowPlayCore"]
        )
    ]
)
