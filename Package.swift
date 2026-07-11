// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RowPlayStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RowPlayStudio", targets: ["RowPlayStudio"]),
        .library(name: "RowPlayCore", targets: ["RowPlayCore"]),
        .library(name: "RowPlayMacOS", targets: ["RowPlayMacOS"])
    ],
    targets: [
        .target(
            name: "RowPlayCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "RowPlayMacOS",
            dependencies: ["RowPlayCore"]
        ),
        .executableTarget(
            name: "RowPlayStudio",
            dependencies: ["RowPlayMacOS", "RowPlayCore"]
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
            dependencies: ["RowPlayStudio", "RowPlayMacOS", "RowPlayCore"]
        )
    ]
)
