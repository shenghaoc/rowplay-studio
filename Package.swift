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
        .library(name: "RowPlayPlatform", targets: ["RowPlayPlatform"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite3",
            pkgConfig: "sqlite3",
            providers: [
                .brew(["sqlite3"]),
                .apt(["libsqlite3-dev"])
            ]
        ),
        .target(
            name: "RowPlayCore",
            dependencies: ["CSQLite3"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "RowPlayPlatform",
            dependencies: ["RowPlayCore"]
        ),
        .executableTarget(
            name: "RowPlayStudio",
            dependencies: ["RowPlayPlatform", "RowPlayCore"]
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
            dependencies: ["RowPlayStudio", "RowPlayPlatform", "RowPlayCore"]
        )
    ]
)
