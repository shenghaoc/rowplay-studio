import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Ported from the web 2D canvas renderer (`src/lib/replay/renderer.ts`, pinned
// commit 4d96480e). Venue environments: sky dome, regatta lake, Nordic stadium,
// and the indoor timber velodrome, with metre-driven material parallax.

// MARK: - Venue Palettes

/// Environment colours are deliberately independent of the two racer accents.
/// Live/ghost colours identify athletes; these colours identify real materials
/// and venue depth.
struct Replay2DVenuePalette {
    let skyTop: Color
    let skyHorizon: Color
    let haze: Color
    let sun: Color
    let ridgeFar: Color
    let ridgeNear: Color
    let foliageFar: Color
    let foliageNear: Color
    let structure: Color
    let structureShade: Color
    let structureLight: Color
    let groundTop: Color
    let groundMid: Color
    let groundBottom: Color
    let surfaceLine: Color
    let surfaceHighlight: Color
    let surfaceShadow: Color
    let marker: Color
    let safety: Color
}

/// Footprint of each sport's signature fixed venue mass (web `VENUE_LANDMARK_2D`).
enum Replay2DVenueLandmark {
    static func size(for sport: Sport) -> CGSize {
        switch sport {
        case .rower: CGSize(width: 34, height: 18)
        case .skierg: CGSize(width: 70, height: 22)
        case .bike: CGSize(width: 14, height: 7)
        }
    }
}

/// Used fields from the web `VENUES_LIGHT` / `VENUES_DARK` tables — hex values
/// verbatim. The source-only `safetyLight` entry had no drawing consumer and is
/// deliberately omitted instead of carrying dead palette state.
enum Replay2DVenueCatalog {
    private static let lightRower = Replay2DVenuePalette(
        skyTop: Color.requiredReplay2DHex("#4d86a8"),
        skyHorizon: Color.requiredReplay2DHex("#f2d29a"),
        haze: Color.requiredReplay2DHex("#f3e2bc"),
        sun: Color.requiredReplay2DHex("#ffe7b0"),
        ridgeFar: Color.requiredReplay2DHex("#9aae90"),
        ridgeNear: Color.requiredReplay2DHex("#4a6d56"),
        foliageFar: Color.requiredReplay2DHex("#5a7a62"),
        foliageNear: Color.requiredReplay2DHex("#2a5244"),
        structure: Color.requiredReplay2DHex("#ece6d9"),
        structureShade: Color.requiredReplay2DHex("#8c7b67"),
        structureLight: Color.requiredReplay2DHex("#ffd68a"),
        groundTop: Color.requiredReplay2DHex("#4a92a3"),
        groundMid: Color.requiredReplay2DHex("#1d6172"),
        groundBottom: Color.requiredReplay2DHex("#0c3a48"),
        surfaceLine: Color.requiredReplay2DHex("#9fd6df"),
        surfaceHighlight: Color.requiredReplay2DHex("#e8f6f7"),
        surfaceShadow: Color.requiredReplay2DHex("#082a37"),
        marker: Color.requiredReplay2DHex("#ef5b42"),
        safety: Color.requiredReplay2DHex("#d9e7e7")
    )
    private static let lightSkierg = Replay2DVenuePalette(
        skyTop: Color.requiredReplay2DHex("#357db3"),
        skyHorizon: Color.requiredReplay2DHex("#dcecf5"),
        haze: Color.requiredReplay2DHex("#f6fbfd"),
        sun: Color.requiredReplay2DHex("#fff5cf"),
        ridgeFar: Color.requiredReplay2DHex("#b8cedb"),
        ridgeNear: Color.requiredReplay2DHex("#66899e"),
        foliageFar: Color.requiredReplay2DHex("#43675d"),
        foliageNear: Color.requiredReplay2DHex("#244a42"),
        structure: Color.requiredReplay2DHex("#e7edf1"),
        structureShade: Color.requiredReplay2DHex("#607887"),
        structureLight: Color.requiredReplay2DHex("#fff1b2"),
        groundTop: Color.requiredReplay2DHex("#f2f7fa"),
        groundMid: Color.requiredReplay2DHex("#d5e4ee"),
        groundBottom: Color.requiredReplay2DHex("#b0c9d8"),
        surfaceLine: Color.requiredReplay2DHex("#8eb5c8"),
        surfaceHighlight: Color.requiredReplay2DHex("#ffffff"),
        surfaceShadow: Color.requiredReplay2DHex("#6f96ab"),
        marker: Color.requiredReplay2DHex("#6d5ef5"),
        safety: Color.requiredReplay2DHex("#1e6292")
    )
    private static let lightBike = Replay2DVenuePalette(
        skyTop: Color.requiredReplay2DHex("#edf3f4"),
        skyHorizon: Color.requiredReplay2DHex("#cbd8da"),
        haze: Color.requiredReplay2DHex("#f8f4e8"),
        sun: Color.requiredReplay2DHex("#fff7d8"),
        ridgeFar: Color.requiredReplay2DHex("#b6c2c4"),
        ridgeNear: Color.requiredReplay2DHex("#87969b"),
        foliageFar: Color.requiredReplay2DHex("#6f817a"),
        foliageNear: Color.requiredReplay2DHex("#4e6d63"),
        structure: Color.requiredReplay2DHex("#d9e1e2"),
        structureShade: Color.requiredReplay2DHex("#596970"),
        structureLight: Color.requiredReplay2DHex("#fff6d4"),
        groundTop: Color.requiredReplay2DHex("#e0c39a"),
        groundMid: Color.requiredReplay2DHex("#c99b68"),
        groundBottom: Color.requiredReplay2DHex("#91623e"),
        surfaceLine: Color.requiredReplay2DHex("#f3eee4"),
        surfaceHighlight: Color.requiredReplay2DHex("#fff8e8"),
        surfaceShadow: Color.requiredReplay2DHex("#503c2f"),
        marker: Color.requiredReplay2DHex("#c83f38"),
        safety: Color.requiredReplay2DHex("#2f7298")
    )
    private static let darkRower = Replay2DVenuePalette(
        skyTop: Color.requiredReplay2DHex("#071724"),
        skyHorizon: Color.requiredReplay2DHex("#294f62"),
        haze: Color.requiredReplay2DHex("#7a9499"),
        sun: Color.requiredReplay2DHex("#f0c67b"),
        ridgeFar: Color.requiredReplay2DHex("#3a5654"),
        ridgeNear: Color.requiredReplay2DHex("#1d3f39"),
        foliageFar: Color.requiredReplay2DHex("#2a4d44"),
        foliageNear: Color.requiredReplay2DHex("#12332d"),
        structure: Color.requiredReplay2DHex("#8c908c"),
        structureShade: Color.requiredReplay2DHex("#3b4648"),
        structureLight: Color.requiredReplay2DHex("#f0b65c"),
        groundTop: Color.requiredReplay2DHex("#1f5a6c"),
        groundMid: Color.requiredReplay2DHex("#0f3644"),
        groundBottom: Color.requiredReplay2DHex("#061c26"),
        surfaceLine: Color.requiredReplay2DHex("#5aa3b4"),
        surfaceHighlight: Color.requiredReplay2DHex("#b6dce2"),
        surfaceShadow: Color.requiredReplay2DHex("#03141c"),
        marker: Color.requiredReplay2DHex("#ef6a4e"),
        safety: Color.requiredReplay2DHex("#60777c")
    )
    private static let darkSkierg = Replay2DVenuePalette(
        skyTop: Color.requiredReplay2DHex("#061522"),
        skyHorizon: Color.requiredReplay2DHex("#28516a"),
        haze: Color.requiredReplay2DHex("#7795a5"),
        sun: Color.requiredReplay2DHex("#e8d5a1"),
        ridgeFar: Color.requiredReplay2DHex("#60798a"),
        ridgeNear: Color.requiredReplay2DHex("#334f60"),
        foliageFar: Color.requiredReplay2DHex("#28473f"),
        foliageNear: Color.requiredReplay2DHex("#142f2b"),
        structure: Color.requiredReplay2DHex("#71838c"),
        structureShade: Color.requiredReplay2DHex("#293c47"),
        structureLight: Color.requiredReplay2DHex("#ffe099"),
        groundTop: Color.requiredReplay2DHex("#cfe3ec"),
        groundMid: Color.requiredReplay2DHex("#9fbfd0"),
        groundBottom: Color.requiredReplay2DHex("#6e93a6"),
        surfaceLine: Color.requiredReplay2DHex("#6f9eb3"),
        surfaceHighlight: Color.requiredReplay2DHex("#f1f7f9"),
        surfaceShadow: Color.requiredReplay2DHex("#456c80"),
        marker: Color.requiredReplay2DHex("#8b7cf5"),
        safety: Color.requiredReplay2DHex("#1f5f85")
    )
    private static let darkBike = Replay2DVenuePalette(
        skyTop: Color.requiredReplay2DHex("#1b2934"),
        skyHorizon: Color.requiredReplay2DHex("#40515b"),
        haze: Color.requiredReplay2DHex("#66767b"),
        sun: Color.requiredReplay2DHex("#f2c981"),
        ridgeFar: Color.requiredReplay2DHex("#45535a"),
        ridgeNear: Color.requiredReplay2DHex("#2c3b43"),
        foliageFar: Color.requiredReplay2DHex("#3d514a"),
        foliageNear: Color.requiredReplay2DHex("#26473e"),
        structure: Color.requiredReplay2DHex("#849198"),
        structureShade: Color.requiredReplay2DHex("#25333c"),
        structureLight: Color.requiredReplay2DHex("#f4d38c"),
        groundTop: Color.requiredReplay2DHex("#9f7650"),
        groundMid: Color.requiredReplay2DHex("#775337"),
        groundBottom: Color.requiredReplay2DHex("#3f2d23"),
        surfaceLine: Color.requiredReplay2DHex("#d9d4ca"),
        surfaceHighlight: Color.requiredReplay2DHex("#ebddc5"),
        surfaceShadow: Color.requiredReplay2DHex("#171412"),
        marker: Color.requiredReplay2DHex("#ef5f53"),
        safety: Color.requiredReplay2DHex("#5fa4c4")
    )

    static func palette(for sport: Sport, darkTheme: Bool) -> Replay2DVenuePalette {
        switch (sport, darkTheme) {
        case (.rower, false): lightRower
        case (.skierg, false): lightSkierg
        case (.bike, false): lightBike
        case (.rower, true): darkRower
        case (.skierg, true): darkSkierg
        case (.bike, true): darkBike
        }
    }
}
