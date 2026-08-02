import Foundation
import RowPlayCore
import simd

/// Pure data describing one sport's premium venue: authored land-use sectors,
/// landmark placements, per-tier feature counts, and the art-directed light,
/// sky, and fog palettes for both themes.
///
/// Every constant is ported verbatim from the pinned RowPlay web reference
/// (`renderer3d.ts` ENVIRONMENTS / SPORT_PROFILES / SUN_OFFSETS /
/// SHADOW_FRAMES and `renderer3dEnvironment.ts` sector tables, commit
/// `4d96480e`). This file holds data and deterministic placement math only —
/// no RealityKit, no SwiftUI, no randomness APIs.

// MARK: - Theme primitives

/// Renderer-neutral light/dark theme selector for venue palettes.
enum ReplayEnvironmentTheme: String, CaseIterable, Sendable {
    case light
    case dark
}

/// One art-directed color with an explicit hex value per theme.
struct ReplayThemedColor: Equatable, Sendable {
    let light: UInt32
    let dark: UInt32

    init(_ light: UInt32, _ dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    func hex(for theme: ReplayEnvironmentTheme) -> UInt32 {
        theme == .dark ? dark : light
    }
}

// MARK: - Geometry primitives

/// One authored land-use arc on the course circle.
///
/// Angles use the web convention: +Z is zero and angle increases with travel.
struct ReplayEnvironmentSector: Equatable, Sendable {
    let startDegrees: Double
    let spanDegrees: Double
    /// Relative placement density inside this sector.
    let weight: Double

    init(startDegrees: Double, spanDegrees: Double, weight: Double = 1) {
        self.startDegrees = startDegrees
        self.spanDegrees = spanDegrees
        self.weight = weight
    }

    var startRadians: Double { ReplayEnvironmentPlan.radians(startDegrees) }
    var spanRadians: Double { ReplayEnvironmentPlan.radians(spanDegrees) }
}

/// One named landmark placement on the venue ring.
struct ReplayEnvironmentPlacement: Equatable, Sendable {
    let name: String
    let angleDegrees: Double
    let radius: Double
    let scale: SIMD3<Double>

    init(name: String, angleDegrees: Double, radius: Double, scale: SIMD3<Double> = SIMD3(1, 1, 1)) {
        self.name = name
        self.angleDegrees = angleDegrees
        self.radius = radius
        self.scale = scale
    }

    var angleRadians: Double { ReplayEnvironmentPlan.radians(angleDegrees) }
}

/// Feature count per environment detail level 0...3 (Low/Medium/High/Ultra).
struct ReplayTierCounts: Equatable, Sendable {
    let values: [Int]

    init(_ low: Int, _ medium: Int, _ high: Int, _ ultra: Int) {
        values = [low, medium, high, ultra]
    }

    subscript(detail: Int) -> Int {
        values[max(0, min(values.count - 1, detail))]
    }
}

/// Scalar multiplier per environment detail level 0...3.
struct ReplayTierScales: Equatable, Sendable {
    let values: [Double]

    init(_ low: Double, _ medium: Double, _ high: Double, _ ultra: Double) {
        values = [low, medium, high, ultra]
    }

    subscript(detail: Int) -> Double {
        values[max(0, min(values.count - 1, detail))]
    }
}

// MARK: - Lighting and sky

/// The full ENVIRONMENTS palette for one sport, plus the art-directed key
/// light world offset (SUN_OFFSETS) and the athlete shadow envelope depth
/// (SHADOW_FRAMES `far`) used to bound native shadow projection.
struct ReplayEnvironmentLightingStyle: Equatable, Sendable {
    let skyZenith: ReplayThemedColor
    let skyHorizon: ReplayThemedColor
    let skyNadir: ReplayThemedColor
    let fog: ReplayThemedColor
    let fogNear: Double
    let fogFar: Double
    let hemisphereSky: ReplayThemedColor
    let hemisphereGround: ReplayThemedColor
    let hemisphereIntensity: Double
    let sun: ReplayThemedColor
    let sunIntensity: Double
    let fill: ReplayThemedColor
    let fillIntensity: Double
    let exposure: Double
    let farSilhouette: ReplayThemedColor
    let midSilhouette: ReplayThemedColor
    let venueStructure: ReplayThemedColor
    let venueAccent: ReplayThemedColor
    let infield: ReplayThemedColor
    let apron: ReplayThemedColor
    let environmentIntensity: Double
    let hemisphereIntensityIbl: Double
    /// Art-directed key light world direction offset (web SUN_OFFSETS).
    let sunOffset: SIMD3<Double>
    /// Depth of the athlete-following shadow envelope (web SHADOW_FRAMES.far).
    let shadowMaximumDistance: Double
}

/// SPORT_PROFILES course surface styling shared by lane band and line grammar.
struct ReplayCourseSurfaceStyle: Equatable, Sendable {
    let groundColor: ReplayThemedColor
    let surface: ReplayThemedColor
    let edge: ReplayThemedColor
    let laneLine: ReplayThemedColor
    let detail: ReplayThemedColor
    let secondary: ReplayThemedColor
    let surfaceOpacity: Double
    let roughness: Double
    let metalness: Double
}

// MARK: - Horizon

/// One raised lobe in the authored horizon envelope.
struct ReplayHorizonLobe: Equatable, Sendable {
    let centerDegrees: Double
    let halfSpanDegrees: Double
    let height: Double
}

/// Authored horizon massing for one sport (web HORIZON_COMPOSITIONS).
struct ReplayHorizonComposition: Equatable, Sendable {
    let offsetX: Double
    let offsetZ: Double
    let floor: Double
    let lobes: [ReplayHorizonLobe]
}

/// The two silhouette rings that close an outdoor venue. Bike has none —
/// the velodrome is enclosed by its own roof and wall.
struct ReplayHorizonRingSpec: Equatable, Sendable {
    /// The mid ring is present at every tier.
    let midRadius: Double
    let midBaseY: Double
    let midAverageHeight: Double
    let midVariation: Double
    let midSegments: Int
    /// The far ring appears at Medium detail and above.
    let farRadius: Double
    let farBaseY: Double
    let farAverageHeight: Double
    let farVariation: Double
    let farSegments: Int
    let composition: ReplayHorizonComposition
}

// MARK: - Course geometry

/// Web course ring radii. The lane band spans `innerRadius...outerRadius`
/// around the live (`loopRadius`) and ghost (`ghostRadius`) lanes; the web
/// derives inner = ghost - 4 and outer = loop + 4.
///
/// These deliberately mirror the *web* loop (radius 30), not the native
/// `ReplayCourseLayout.standard` radii: every authored venue distance in this
/// plan (island 15.5, stands 44.5...60.2, roof 72, horizon 84/116) is scaled
/// to this ring, so the integration step scales or re-lays the course rather
/// than this plan re-deriving hundreds of authored constants.
struct ReplayVenueCourseGeometry: Equatable, Sendable {
    let loopRadius: Double
    let ghostRadius: Double
    let innerRadius: Double
    let outerRadius: Double

    static let web = ReplayVenueCourseGeometry(
        loopRadius: 30,
        ghostRadius: 26,
        innerRadius: 22,
        outerRadius: 34
    )
}

// MARK: - Per-sport venue payloads

/// Regatta basin land uses, landmarks, and tier tables.
struct ReplayRowerVenuePlan: Equatable, Sendable {
    // Authored land-use sectors.
    let campusSector: ReplayEnvironmentSector
    let woodlandSectors: [ReplayEnvironmentSector]
    let vistaSector: ReplayEnvironmentSector

    // Landmarks. The pavilion skyline itself grows by tier.
    let landmarks: [ReplayEnvironmentPlacement]
    let landmarkCounts: ReplayTierCounts
    let finishTowerAngleDegrees: Double
    let finishTowerRadius: Double

    // Island park at the lagoon centre.
    let islandRadius: Double
    let islandTreeCounts: ReplayTierCounts
    let islandShrubCounts: ReplayTierCounts

    // Bank woodland between the shoreline and the valley.
    let woodlandTreeCounts: ReplayTierCounts
    let woodlandRadiusMin: Double
    let woodlandRadiusMax: Double
    let broadleafShare: Double

    // Shore dressing.
    let reedCounts: ReplayTierCounts
    let rippleCounts: ReplayTierCounts
    let valleyRidgeCounts: ReplayTierCounts
    let distancePostCounts: ReplayTierCounts

    // Buoy necklace: two rings with a gap at the finish line.
    let buoyRingRadii: [Double]
    let buoyFinishGapDegrees: Double

    // Course-crossing judges' footbridge (High and Ultra).
    let bridgeAngleDegrees: Double
}

/// Nordic stadium land uses, landmarks, and tier tables.
struct ReplaySkiVenuePlan: Equatable, Sendable {
    let lodgeSector: ReplayEnvironmentSector
    let forestSectors: [ReplayEnvironmentSector]
    let alpineSectors: [ReplayEnvironmentSector]
    let bermSectors: [ReplayEnvironmentSector]
    let openSector: ReplayEnvironmentSector

    let landmarks: [ReplayEnvironmentPlacement]
    let landmarkCounts: ReplayTierCounts
    let alpineShelter: ReplayEnvironmentPlacement
    let floodlights: [ReplayEnvironmentPlacement]

    let stadiumFieldRadius: Double
    let startPadRadius: Double
    let groomLineCounts: ReplayTierCounts
    let snowFenceCounts: ReplayTierCounts
    let coursePanelCounts: ReplayTierCounts
    let pistePoleCounts: ReplayTierCounts

    let forestTreeCounts: ReplayTierCounts
    let forestRadiusMin: Double
    let forestRadiusMax: Double
    let broadleafShare: Double

    let floodlightMastCounts: ReplayTierCounts
    let floodlightPoolCounts: ReplayTierCounts
    let floodlightPoolColor: ReplayThemedColor
    let floodlightPoolOpacity: Double
    /// Painted light pools sit on the live lane centre (web `outerR - 4`).
    let floodlightPoolRadius: Double

    let snowBermCounts: ReplayTierCounts
    let snowBermTierScales: ReplayTierScales
    let foothillCounts: ReplayTierCounts
    let foothillRadius: Double

    let alpinePeakCounts: ReplayTierCounts
    let alpinePeakTierScales: ReplayTierScales
    let alpinePeakRadiusMin: Double
    let alpinePeakRadiusSpread: Double

    /// Exposed rock shoulder appears at High (3 outcrops) and Ultra (5).
    let rockOutcropCountHigh: Int
    let rockOutcropCountUltra: Int
    let timingArchAngleDegrees: Double
}

/// One authored velodrome seating tier: annulus radii and deck height.
struct ReplayBikeStandTier: Equatable, Sendable {
    let innerRadius: Double
    let outerRadius: Double
    let y: Double
}

/// Indoor velodrome composition, line grammar, and tier tables.
struct ReplayBikeVenuePlan: Equatable, Sendable {
    let standSectors: [ReplayEnvironmentSector]
    let serviceSector: ReplayEnvironmentSector
    /// Blank arena-wall bay behind the back straight (web `{164°, 42°}`).
    let backWallSector: ReplayEnvironmentSector

    let scoreboard: ReplayEnvironmentPlacement
    let serviceBuilding: ReplayEnvironmentPlacement
    let teamPitAngleDegrees: Double
    let teamPitRadius: Double
    let hospitalityAngleDegrees: Double
    let hospitalityRadius: Double

    /// Five authored seating tiers; `2 + environmentDetail` of them build.
    let standTiers: [ReplayBikeStandTier]

    let roofRadius: Double
    let roofY: Double
    let trussCounts: ReplayTierCounts
    let skylightCounts: ReplayTierCounts
    let hangarLightCounts: ReplayTierCounts
    let railPostCounts: ReplayTierCounts
    let pursuitDashCounts: ReplayTierCounts

    let arenaWallRadius: Double
    let arenaWallHeight: Double
    let infieldFloorRadius: Double

    // Continuous black/red/blue paint grammar on the timber.
    let coteDAzurInnerRadius: Double
    let coteDAzurOuterRadius: Double
    let coteDAzurColor: ReplayThemedColor
    let measurementLineRadius: Double
    let pursuitLineRadius: Double
    let sprinterLineRadius: Double
    let sprintMarkerRadius: Double
    let finishGantryAngleDegrees: Double
}

// MARK: - Plan

/// The complete authored venue plan for one sport.
struct ReplayEnvironmentPlan: Equatable, Sendable {
    let sport: Sport
    let lighting: ReplayEnvironmentLightingStyle
    let courseStyle: ReplayCourseSurfaceStyle
    let course: ReplayVenueCourseGeometry
    /// Nil for the enclosed velodrome.
    let horizon: ReplayHorizonRingSpec?
    let rower: ReplayRowerVenuePlan?
    let skierg: ReplaySkiVenuePlan?
    let bike: ReplayBikeVenuePlan?

    static func plan(for sport: Sport) -> ReplayEnvironmentPlan {
        switch sport {
        case .rower: .rower
        case .skierg: .skierg
        case .bike: .bike
        }
    }

    // MARK: Angle helpers

    static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    /// Shortest angular distance between two angles in radians.
    static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let fullCircle = Double.pi * 2
        let wrapped = (((a - b + .pi).truncatingRemainder(dividingBy: fullCircle)) + fullCircle)
            .truncatingRemainder(dividingBy: fullCircle)
        return abs(wrapped - .pi)
    }

    // MARK: Deterministic placement math

    /// Weighted sector distribution — exact port of the web `sectorSample`.
    /// Index `i` of `count` lands inside the authored sectors proportionally
    /// to `span * weight`, with no randomness.
    static func sectorSample(
        index: Int,
        count: Int,
        sectors: [ReplayEnvironmentSector]
    ) -> (angleRadians: Double, sector: Int, local: Double) {
        let total = sectors.reduce(0) { $0 + $1.spanRadians * $1.weight }
        var cursor = ((Double(index) + 0.5) / Double(max(1, count))) * total
        for (sectorIndex, sector) in sectors.enumerated() {
            let weightedSpan = sector.spanRadians * sector.weight
            if cursor <= weightedSpan || sectorIndex == sectors.count - 1 {
                let local = min(1, max(0, cursor / weightedSpan))
                return (sector.startRadians + sector.spanRadians * local, sectorIndex, local)
            }
            cursor -= weightedSpan
        }
        return (sectors.first?.startRadians ?? 0, 0, 0)
    }

    /// The web's fract-of-scaled-sin hash: deterministic pseudo-random in
    /// [0, 1) from an index-derived seed. Raw `sin(i * seed)` aliases badly at
    /// venue counts, which is why the web multiplies into the fract pattern.
    static func hashFraction(_ n: Double) -> Double {
        let value = sin(n) * 43758.5453
        return value - value.rounded(.down)
    }

    /// Deterministic, angle-periodic fractal ridge noise in roughly [-1, 1].
    ///
    /// Simplification vs. web: the reference uses 2D/3D simplex fBm
    /// (`SimplexNoise` from three/addons). This substitute sums integer-
    /// frequency sine octaves with hash-derived phases, so it is seamless
    /// around the circle, needs no noise table, and stays deterministic with
    /// fixed seeds.
    static func ridgeNoise(angle: Double, seed: Double, octaves: Int) -> Double {
        var value = 0.0
        var amplitude = 1.0
        var frequency = 2.0
        var total = 0.0
        for octave in 0..<max(1, octaves) {
            let phase = hashFraction(seed + Double(octave) * 12.9898) * .pi * 2
            value += amplitude * sin(angle * frequency + phase)
            total += amplitude
            amplitude *= 0.48
            frequency += Double(2 + octave)
        }
        return value / max(0.001, total)
    }

    // MARK: - Rower plan

    static let rower = ReplayEnvironmentPlan(
        sport: .rower,
        lighting: ReplayEnvironmentLightingStyle(
            skyZenith: ReplayThemedColor(0x4B91BD, 0x0B2639),
            skyHorizon: ReplayThemedColor(0xDCEEF1, 0x557C8C),
            skyNadir: ReplayThemedColor(0x5F8F8E, 0x12333C),
            fog: ReplayThemedColor(0xBFD4CA, 0x2E5059),
            fogNear: 62,
            fogFar: 178,
            hemisphereSky: ReplayThemedColor(0xF2FBFF, 0x7EABB9),
            hemisphereGround: ReplayThemedColor(0x426C5B, 0x173535),
            hemisphereIntensity: 1.3,
            sun: ReplayThemedColor(0xFFEDC1, 0xFFCE82),
            sunIntensity: 2.55,
            fill: ReplayThemedColor(0xBFE9F1, 0x568B9A),
            fillIntensity: 0.7,
            exposure: 1.06,
            farSilhouette: ReplayThemedColor(0x78947B, 0x23454A),
            midSilhouette: ReplayThemedColor(0x3F6D50, 0x1C493D),
            venueStructure: ReplayThemedColor(0xE8E4D8, 0x7F9093),
            venueAccent: ReplayThemedColor(0xA65E3B, 0xD9A066),
            infield: ReplayThemedColor(0x2F8198, 0x124F62),
            apron: ReplayThemedColor(0x3C91A3, 0x175A69),
            environmentIntensity: 0,
            hemisphereIntensityIbl: 1.22,
            sunOffset: SIMD3(-22, 18, 14),
            shadowMaximumDistance: 48
        ),
        courseStyle: ReplayCourseSurfaceStyle(
            groundColor: ReplayThemedColor(0x2F879C, 0x104D60),
            surface: ReplayThemedColor(0x378DA0, 0x155568),
            edge: ReplayThemedColor(0xD9EEF2, 0x8ED5E1),
            laneLine: ReplayThemedColor(0xC9E5EA, 0x68BED0),
            detail: ReplayThemedColor(0xF59E0B, 0xF6C453),
            secondary: ReplayThemedColor(0xFFFFFF, 0xE8FBFF),
            surfaceOpacity: 0.035,
            roughness: 0.18,
            metalness: 0.06
        ),
        course: .web,
        horizon: ReplayHorizonRingSpec(
            midRadius: 84,
            midBaseY: -1.4,
            midAverageHeight: 8.4,
            midVariation: 3.6,
            midSegments: 64,
            farRadius: 116,
            farBaseY: -2.5,
            farAverageHeight: 12.5,
            farVariation: 5.2,
            farSegments: 72,
            composition: ReplayHorizonComposition(
                offsetX: -14,
                offsetZ: 9,
                floor: 0.28,
                lobes: [
                    ReplayHorizonLobe(centerDegrees: 18, halfSpanDegrees: 78, height: 0.78),
                    ReplayHorizonLobe(centerDegrees: 92, halfSpanDegrees: 36, height: 0.42),
                    ReplayHorizonLobe(centerDegrees: 210, halfSpanDegrees: 68, height: 0.7),
                    ReplayHorizonLobe(centerDegrees: 300, halfSpanDegrees: 34, height: 0.38),
                ]
            )
        ),
        rower: ReplayRowerVenuePlan(
            campusSector: ReplayEnvironmentSector(startDegrees: 8, spanDegrees: 48),
            woodlandSectors: [
                ReplayEnvironmentSector(startDegrees: -48, spanDegrees: 52, weight: 1.1),
                ReplayEnvironmentSector(startDegrees: 62, spanDegrees: 100, weight: 1.35),
                ReplayEnvironmentSector(startDegrees: 188, spanDegrees: 110, weight: 1.2),
            ],
            vistaSector: ReplayEnvironmentSector(startDegrees: 300, spanDegrees: 58),
            landmarks: [
                ReplayEnvironmentPlacement(
                    name: "environment:rower:regatta-pavilion",
                    angleDegrees: 17,
                    radius: 72,
                    scale: SIMD3(0.9, 0.88, 0.86)
                ),
                ReplayEnvironmentPlacement(
                    name: "environment:rower:boathouse",
                    angleDegrees: 32,
                    radius: 75,
                    scale: SIMD3(0.72, 0.74, 0.76)
                ),
                ReplayEnvironmentPlacement(
                    name: "environment:rower:timing-tower",
                    angleDegrees: 43,
                    radius: 70,
                    scale: SIMD3(0.5, 1.26, 0.56)
                ),
            ],
            landmarkCounts: ReplayTierCounts(1, 2, 3, 3),
            finishTowerAngleDegrees: 52,
            finishTowerRadius: 37.4,
            islandRadius: 15.5,
            islandTreeCounts: ReplayTierCounts(4, 7, 10, 13),
            islandShrubCounts: ReplayTierCounts(0, 6, 10, 14),
            woodlandTreeCounts: ReplayTierCounts(14, 32, 72, 104),
            woodlandRadiusMin: 43,
            woodlandRadiusMax: 65,
            broadleafShare: 0.45,
            reedCounts: ReplayTierCounts(8, 16, 26, 36),
            rippleCounts: ReplayTierCounts(0, 6, 10, 14),
            valleyRidgeCounts: ReplayTierCounts(0, 4, 6, 8),
            distancePostCounts: ReplayTierCounts(0, 0, 4, 6),
            buoyRingRadii: [23.8, 32.4],
            buoyFinishGapDegrees: 14,
            bridgeAngleDegrees: 148
        ),
        skierg: nil,
        bike: nil
    )

    // MARK: - SkiErg plan

    static let skierg = ReplayEnvironmentPlan(
        sport: .skierg,
        lighting: ReplayEnvironmentLightingStyle(
            skyZenith: ReplayThemedColor(0x1F3C58, 0x102B45),
            skyHorizon: ReplayThemedColor(0xA2B4C4, 0x6F8D9F),
            skyNadir: ReplayThemedColor(0x7E97A9, 0x385669),
            fog: ReplayThemedColor(0x64798C, 0x718D9B),
            fogNear: 74,
            fogFar: 205,
            hemisphereSky: ReplayThemedColor(0xB9CFE2, 0xA0BFD0),
            hemisphereGround: ReplayThemedColor(0x5D7789, 0x405C6D),
            hemisphereIntensity: 0.9,
            sun: ReplayThemedColor(0xFFE8C0, 0xEAF6FF),
            sunIntensity: 2.7,
            fill: ReplayThemedColor(0x7FA3C4, 0x719BB5),
            fillIntensity: 0.62,
            exposure: 1.02,
            farSilhouette: ReplayThemedColor(0x9A8B96, 0x506F82),
            midSilhouette: ReplayThemedColor(0x435D72, 0x315267),
            venueStructure: ReplayThemedColor(0x25394A, 0x192F3D),
            venueAccent: ReplayThemedColor(0xE04852, 0xFF6670),
            infield: ReplayThemedColor(0xCFDFE9, 0x9FB7C5),
            apron: ReplayThemedColor(0xDFEAF1, 0xC7D7DF),
            environmentIntensity: 0.62,
            hemisphereIntensityIbl: 0.36,
            sunOffset: SIMD3(16, 28, 10),
            shadowMaximumDistance: 46
        ),
        courseStyle: ReplayCourseSurfaceStyle(
            groundColor: ReplayThemedColor(0xAABFD0, 0x8FA5B3),
            surface: ReplayThemedColor(0xC7D6E2, 0x849DAA),
            edge: ReplayThemedColor(0xB6CCD8, 0x7893A2),
            laneLine: ReplayThemedColor(0x8EAFBD, 0x607F8E),
            detail: ReplayThemedColor(0x6D5EF5, 0x7C6CF0),
            secondary: ReplayThemedColor(0x7898A7, 0x556E7B),
            surfaceOpacity: 1,
            roughness: 0.94,
            metalness: 0.01
        ),
        course: .web,
        horizon: ReplayHorizonRingSpec(
            midRadius: 84,
            midBaseY: -1.4,
            midAverageHeight: 12,
            midVariation: 6,
            midSegments: 64,
            farRadius: 116,
            farBaseY: -2.5,
            farAverageHeight: 22,
            farVariation: 9,
            farSegments: 72,
            composition: ReplayHorizonComposition(
                offsetX: 10,
                offsetZ: -15,
                floor: 0.2,
                lobes: [
                    ReplayHorizonLobe(centerDegrees: -118, halfSpanDegrees: 52, height: 0.92),
                    ReplayHorizonLobe(centerDegrees: 65, halfSpanDegrees: 49, height: 0.86),
                ]
            )
        ),
        rower: nil,
        skierg: ReplaySkiVenuePlan(
            lodgeSector: ReplayEnvironmentSector(startDegrees: -12, spanDegrees: 40),
            forestSectors: [
                ReplayEnvironmentSector(startDegrees: -170, spanDegrees: 55, weight: 0.95),
                ReplayEnvironmentSector(startDegrees: 105, spanDegrees: 65, weight: 1.1),
                ReplayEnvironmentSector(startDegrees: 40, spanDegrees: 28, weight: 0.75),
                ReplayEnvironmentSector(startDegrees: 205, spanDegrees: 52, weight: 0.9),
            ],
            alpineSectors: [
                ReplayEnvironmentSector(startDegrees: -150, spanDegrees: 65, weight: 1.1),
                ReplayEnvironmentSector(startDegrees: 35, spanDegrees: 60),
            ],
            bermSectors: [
                ReplayEnvironmentSector(startDegrees: 38, spanDegrees: 112),
                ReplayEnvironmentSector(startDegrees: 195, spanDegrees: 125, weight: 1.05),
            ],
            openSector: ReplayEnvironmentSector(startDegrees: 250, spanDegrees: 55),
            landmarks: [
                // Lodge campus placements are authored relative to the lodge
                // sector: start + span * 0.45 and start + span * 0.78.
                ReplayEnvironmentPlacement(
                    name: "environment:skierg:timing-lodge",
                    angleDegrees: 6,
                    radius: 59,
                    scale: SIMD3(1.05, 1.12, 1)
                ),
                ReplayEnvironmentPlacement(
                    name: "environment:skierg:wax-hut",
                    angleDegrees: 19.2,
                    radius: 61,
                    scale: SIMD3(0.68, 0.76, 0.74)
                ),
            ],
            landmarkCounts: ReplayTierCounts(1, 1, 2, 2),
            alpineShelter: ReplayEnvironmentPlacement(
                name: "environment:skierg:mountain-rescue-shelter",
                angleDegrees: 216,
                radius: 78,
                scale: SIMD3(0.72, 0.72, 0.74)
            ),
            floodlights: [-8.0, 2, 12, 22, 32, -16, 38, 18].enumerated().map { index, angle in
                ReplayEnvironmentPlacement(
                    name: "environment:skierg:floodlight-\(index + 1)",
                    angleDegrees: angle,
                    radius: index < 4 ? 53 : 55.5
                )
            },
            stadiumFieldRadius: 33,
            startPadRadius: 8.5,
            groomLineCounts: ReplayTierCounts(2, 4, 6, 8),
            snowFenceCounts: ReplayTierCounts(0, 6, 10, 14),
            coursePanelCounts: ReplayTierCounts(0, 6, 10, 14),
            pistePoleCounts: ReplayTierCounts(0, 6, 8, 10),
            forestTreeCounts: ReplayTierCounts(10, 36, 88, 132),
            forestRadiusMin: 56,
            forestRadiusMax: 92,
            broadleafShare: 0.16,
            floodlightMastCounts: ReplayTierCounts(0, 4, 6, 8),
            floodlightPoolCounts: ReplayTierCounts(0, 5, 8, 8),
            floodlightPoolColor: ReplayThemedColor(0xFFC97E, 0xFFC27A),
            floodlightPoolOpacity: 0.38,
            floodlightPoolRadius: 30,
            snowBermCounts: ReplayTierCounts(6, 16, 28, 40),
            snowBermTierScales: ReplayTierScales(0.58, 0.76, 0.9, 1),
            foothillCounts: ReplayTierCounts(0, 8, 14, 20),
            foothillRadius: 85,
            alpinePeakCounts: ReplayTierCounts(3, 8, 14, 22),
            alpinePeakTierScales: ReplayTierScales(0.82, 0.95, 1.08, 1.2),
            alpinePeakRadiusMin: 130,
            alpinePeakRadiusSpread: 28,
            rockOutcropCountHigh: 3,
            rockOutcropCountUltra: 5,
            timingArchAngleDegrees: -8
        ),
        bike: nil
    )

    // MARK: - BikeErg plan

    static let bike = ReplayEnvironmentPlan(
        sport: .bike,
        lighting: ReplayEnvironmentLightingStyle(
            skyZenith: ReplayThemedColor(0x2E3540, 0x1C2A38),
            skyHorizon: ReplayThemedColor(0x4A4E54, 0x344252),
            skyNadir: ReplayThemedColor(0x33383F, 0x202D36),
            fog: ReplayThemedColor(0x3D4249, 0x2B3944),
            fogNear: 72,
            fogFar: 165,
            hemisphereSky: ReplayThemedColor(0x8A8F96, 0x707F8E),
            hemisphereGround: ReplayThemedColor(0x6B5844, 0x312D28),
            hemisphereIntensity: 1.15,
            sun: ReplayThemedColor(0xFFE2B0, 0xFFD49A),
            sunIntensity: 3.5,
            fill: ReplayThemedColor(0x7D94A8, 0x6D8BA0),
            fillIntensity: 0.62,
            exposure: 1.16,
            farSilhouette: ReplayThemedColor(0x525C63, 0x263442),
            midSilhouette: ReplayThemedColor(0x454F58, 0x314352),
            venueStructure: ReplayThemedColor(0x5A646C, 0x344452),
            venueAccent: ReplayThemedColor(0xD79A50, 0xF0B667),
            infield: ReplayThemedColor(0x6D7A74, 0x405149),
            apron: ReplayThemedColor(0x847D70, 0x3C3C3A),
            environmentIntensity: 0.72,
            hemisphereIntensityIbl: 0.34,
            sunOffset: SIMD3(12, 20, -10),
            shadowMaximumDistance: 40
        ),
        courseStyle: ReplayCourseSurfaceStyle(
            // Near-white timber tint: at High/Ultra the wood-floor diffuse map
            // multiplies this color, so the tint only warms the boards.
            groundColor: ReplayThemedColor(0x98A09D, 0x303A40),
            surface: ReplayThemedColor(0xDBC09A, 0xE6CFA8),
            edge: ReplayThemedColor(0xF4F2EB, 0xDFE7E8),
            laneLine: ReplayThemedColor(0x2F7298, 0x5FA4C4),
            detail: ReplayThemedColor(0xC63F38, 0xE9685E),
            secondary: ReplayThemedColor(0x725F4D, 0x51463E),
            surfaceOpacity: 1,
            roughness: 0.82,
            metalness: 0.025
        ),
        course: .web,
        horizon: nil,
        rower: nil,
        skierg: nil,
        bike: ReplayBikeVenuePlan(
            standSectors: [
                ReplayEnvironmentSector(startDegrees: 55, spanDegrees: 85, weight: 1.2),
                ReplayEnvironmentSector(startDegrees: 220, spanDegrees: 60, weight: 0.85),
            ],
            serviceSector: ReplayEnvironmentSector(startDegrees: 228, spanDegrees: 42),
            backWallSector: ReplayEnvironmentSector(startDegrees: 164, spanDegrees: 42),
            // 55 + 85 * 0.48 along the main stand.
            scoreboard: ReplayEnvironmentPlacement(
                name: "environment:bike:scoreboard",
                angleDegrees: 95.8,
                radius: 58
            ),
            // 228 + 42 * 0.55 inside the service sector.
            serviceBuilding: ReplayEnvironmentPlacement(
                name: "environment:bike:service-building",
                angleDegrees: 251.1,
                radius: 60,
                scale: SIMD3(0.82, 0.82, 1.05)
            ),
            // 228 + 42 * 0.48; radius outerR - 8.5.
            teamPitAngleDegrees: 248.16,
            teamPitRadius: 25.5,
            // 55 + 85 * 0.52 over the main straight.
            hospitalityAngleDegrees: 99.2,
            hospitalityRadius: 58.2,
            standTiers: [
                ReplayBikeStandTier(innerRadius: 44.5, outerRadius: 47.6, y: 0.42),
                ReplayBikeStandTier(innerRadius: 47.8, outerRadius: 51.2, y: 0.92),
                ReplayBikeStandTier(innerRadius: 50.8, outerRadius: 54.1, y: 1.62),
                ReplayBikeStandTier(innerRadius: 53.7, outerRadius: 57.2, y: 2.46),
                ReplayBikeStandTier(innerRadius: 56.8, outerRadius: 60.2, y: 3.35),
            ],
            roofRadius: 72,
            roofY: 13.7,
            trussCounts: ReplayTierCounts(2, 3, 5, 7),
            skylightCounts: ReplayTierCounts(0, 2, 3, 4),
            hangarLightCounts: ReplayTierCounts(0, 6, 10, 14),
            railPostCounts: ReplayTierCounts(8, 12, 16, 20),
            pursuitDashCounts: ReplayTierCounts(18, 24, 30, 36),
            arenaWallRadius: 61.5,
            arenaWallHeight: 6.2,
            infieldFloorRadius: 33.1,
            coteDAzurInnerRadius: 22.06,
            coteDAzurOuterRadius: 22.58,
            coteDAzurColor: ReplayThemedColor(0x7DB6CC, 0x2C5A6E),
            measurementLineRadius: 22.72,
            pursuitLineRadius: 28,
            sprinterLineRadius: 33.2,
            sprintMarkerRadius: 32.65,
            finishGantryAngleDegrees: 2
        )
    )
}
