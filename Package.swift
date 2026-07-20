// swift-tools-version: 6.3

import PackageDescription

func makeCoreTestTarget(dependencies: [Target.Dependency] = ["RowPlayCore"]) -> Target {
    .testTarget(
        name: "RowPlayCoreTests",
        dependencies: dependencies,
        resources: [
            .copy("Fixtures/duration-band-parity.json"),
            .copy("Fixtures/performance-predictor-parity.json"),
            .copy("Fixtures/Concept2/rower-steady.fixture.json"),
            .copy("Fixtures/Concept2/rower-interval.fixture.json"),
            .copy("Fixtures/Concept2/ski-steady.fixture.json"),
            .copy("Fixtures/Concept2/bike-steady.fixture.json"),
            .copy("Fixtures/Concept2/REDACTION.md"),
            .copy("Fixtures/stroke-pose-parity.json"),
            .copy("Fixtures/replay-race-gap-parity.json"),
            .copy("Fixtures/replay-rival-sources-parity.json"),
            .copy("Fixtures/replay-race-result-parity.json"),
        ]
    )
}

#if !os(macOS)
let products: [Product] = [
    .library(name: "RowPlayCore", targets: ["RowPlayCore"])
]

let targets: [Target] = [
    .systemLibrary(
        name: "CSQLite3",
        pkgConfig: "sqlite3",
        providers: [
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
    makeCoreTestTarget(dependencies: ["RowPlayCore", "CSQLite3"]),
]
#else
let products: [Product] = [
    .executable(name: "RowPlayStudio", targets: ["RowPlayStudio"]),
    .library(name: "RowPlayCore", targets: ["RowPlayCore"]),
    .library(name: "RowPlayPlatform", targets: ["RowPlayPlatform"])
]

let targets: [Target] = [
    .target(
        name: "RowPlayCore",
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
        dependencies: ["RowPlayPlatform", "RowPlayCore"],
        resources: [
            .process("Assets")
        ]
    ),
    makeCoreTestTarget(),
    .testTarget(
        name: "RowPlayPlatformTests",
        dependencies: ["RowPlayPlatform", "RowPlayCore"]
    ),
    .testTarget(
        name: "RowPlayStudioTests",
        dependencies: ["RowPlayStudio", "RowPlayCore"]
    ),
]
#endif

let package = Package(
    name: "RowPlayStudio",
    platforms: [
        .macOS(.v26)
    ],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
