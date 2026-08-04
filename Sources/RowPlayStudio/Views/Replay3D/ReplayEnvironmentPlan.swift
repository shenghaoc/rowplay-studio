import AppKit
import Foundation
import RowPlayCore
import simd

/// Live native venue data consumed by `ReplayEnvironmentInstaller` and the
/// scene lights. The pinned web venues use a 30-metre loop; only authored
/// planar radii, XZ positions, and large planar extents are mapped to the
/// native `ReplayCourseLayout`. Heights and prop dimensions remain metres.

enum ReplayEnvironmentTheme: String, CaseIterable, Sendable {
    case light
    case dark
}

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

    func resolvedColor(for theme: ReplayEnvironmentTheme) -> NSColor {
        let value = hex(for: theme)
        return NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}

struct ReplayQualityValues<Value: Equatable & Sendable>: Equatable, Sendable {
    let low: Value
    let medium: Value
    let high: Value
    let ultra: Value

    init(_ low: Value, _ medium: Value, _ high: Value, _ ultra: Value) {
        self.low = low
        self.medium = medium
        self.high = high
        self.ultra = ultra
    }

    subscript(quality: ReplayRenderQuality) -> Value {
        switch quality {
        case .low: low
        case .medium: medium
        case .high: high
        case .ultra: ultra
        }
    }
}

struct ReplayEnvironmentPlacement: Equatable, Sendable {
    let name: String
    let angleDegrees: Double
    let radius: Double
    /// Physical prop dimensions in metres. These are never course-scaled.
    let size: SIMD3<Double>

    init(
        name: String,
        angleDegrees: Double,
        radius: Double,
        size: SIMD3<Double> = SIMD3(1, 1, 1)
    ) {
        self.name = name
        self.angleDegrees = angleDegrees
        self.radius = radius
        self.size = size
    }

    var angleRadians: Double { angleDegrees * .pi / 180 }
}

/// An authored angular land-use sector from the pinned venue plan. Repeated
/// scenery is distributed inside these sectors so trees and wall bays form
/// deliberate stands with open sightlines instead of uniform full-radius rings.
struct ReplayEnvironmentSector: Equatable, Sendable {
    let startDegrees: Double
    let spanDegrees: Double
    let weight: Double

    init(startDegrees: Double, spanDegrees: Double, weight: Double = 1) {
        self.startDegrees = startDegrees
        self.spanDegrees = spanDegrees
        self.weight = weight
    }

    var startRadians: Double { startDegrees * .pi / 180 }
    var spanRadians: Double { spanDegrees * .pi / 180 }
}

struct ReplayEnvironmentLightingPlan: Equatable, Sendable {
    let sunColor: ReplayThemedColor
    /// RealityKit directional-light intensity adapted from the pinned web
    /// profile with one shared 4,000x native-unit conversion.
    let sunIntensity: Float
    let sunOffset: SIMD3<Float>
    let fillColor: ReplayThemedColor
    let fillIntensity: Float

    /// The native fill opposes each sport's authored sun direction while
    /// retaining half its height. This keeps the adapter deterministic without
    /// introducing a second set of unrelated art-direction constants.
    var fillOffset: SIMD3<Float> {
        SIMD3(-sunOffset.x * 0.55, max(8, sunOffset.y * 0.5), -sunOffset.z * 0.55)
    }
}

struct ReplayEnvironmentGroundPlan: Equatable, Sendable {
    let halfExtent: Double
    let family: ReplayEnvironmentTextureFamily?
    let color: ReplayThemedColor
    let roughness: Float
    let metallic: Float
    let textureRepeat: SIMD2<Float>
}

struct ReplayEnvironmentMarkerPlan: Equatable, Sendable {
    let centerY: Double
    let size: SIMD3<Double>
}

struct ReplayRowerVenuePlan: Equatable, Sendable {
    let basinRadius: Double
    let basinHeight: Double
    let basinCenterY: Double
    let basinColor: ReplayThemedColor
    let basinRoughness: Float
    let basinMetallic: Float

    let islandRadius: Double
    let islandHeight: Double
    let islandCenterY: Double
    let islandColor: ReplayThemedColor

    let landmarks: [ReplayEnvironmentPlacement]
    let landmarkCounts: ReplayQualityValues<Int>

    let islandTreeCounts: ReplayQualityValues<Int>
    let islandTreeRadius: Double
    let islandTree: ReplayEnvironmentMarkerPlan
    let foliageColor: ReplayThemedColor

    let shorelineSectors: [ReplayEnvironmentSector]
    let shorelineInnerRadius: Double
    let shorelineOuterRadius: Double
    let shorelineColor: ReplayThemedColor
    let woodlandTreeCounts: ReplayQualityValues<Int>
    let woodlandInnerRadius: Double
    let woodlandOuterRadius: Double
    let woodlandTree: ReplayEnvironmentMarkerPlan

    let ultraBoardwalk: ReplayEnvironmentPlacement

    let buoyRingRadii: [Double]
    let buoy: ReplayEnvironmentMarkerPlan
    let buoyColor: ReplayThemedColor
}

struct ReplaySkiVenuePlan: Equatable, Sendable {
    let fieldRadius: Double
    let fieldHeight: Double
    let fieldCenterY: Double
    let fieldColor: ReplayThemedColor
    let fieldRoughness: Float
    let groomLineCounts: ReplayQualityValues<Int>

    let landmarks: [ReplayEnvironmentPlacement]
    let landmarkCounts: ReplayQualityValues<Int>

    let forestTreeCounts: ReplayQualityValues<Int>
    let forestSectors: [ReplayEnvironmentSector]
    let forestInnerRadius: Double
    let forestOuterRadius: Double
    let forestTree: ReplayEnvironmentMarkerPlan
    let forestColor: ReplayThemedColor

    let alpineSectors: [ReplayEnvironmentSector]
    let alpineShoulderCounts: ReplayQualityValues<Int>
    let alpineInnerRadius: Double
    let alpineOuterRadius: Double
    let alpineShoulder: ReplayEnvironmentMarkerPlan
    let alpineColor: ReplayThemedColor

    let floodlights: [ReplayEnvironmentPlacement]
    let floodlightCounts: ReplayQualityValues<Int>
    let floodlightColor: ReplayThemedColor
    let ultraShelter: ReplayEnvironmentPlacement
}

struct ReplayBikeStandTierPlan: Equatable, Sendable {
    let innerRadius: Double
    let outerRadius: Double
    let centerY: Double
}

struct ReplayBikeLinePlan: Equatable, Sendable {
    let name: String
    let radius: Double
    /// Authored planar width, mapped with the course radius. Torus-based web
    /// lines store a tube radius, so this is their full radial diameter.
    let radialWidth: Double
    let centerY: Double
    let height: Double
    let color: ReplayThemedColor
}

struct ReplayBikeSprintMarkerPlan: Equatable, Sendable {
    let name: String
    let radius: Double
    let anglesDegrees: [Double]
    let radialWidth: Double
    let tangentialLength: Double
    let centerY: Double
    let height: Double
    let color: ReplayThemedColor
}

struct ReplayBikeVenuePlan: Equatable, Sendable {
    /// Pinned web lane annulus (`ghostRadius - 4 ... loopRadius + 4`).
    let trackInnerRadius: Double
    let trackOuterRadius: Double
    let trackHeight: Double
    let trackCenterY: Double
    let trackColor: ReplayThemedColor
    let trackRoughness: Float

    let infieldRadius: Double
    let infieldHeight: Double
    let infieldCenterY: Double
    let infieldColor: ReplayThemedColor

    let wallRadius: Double
    let wallSegments: ReplayQualityValues<Int>
    let wallSectors: [ReplayEnvironmentSector]
    let wall: ReplayEnvironmentMarkerPlan
    let wallColor: ReplayThemedColor

    let standSectors: [ReplayEnvironmentSector]
    let standTiers: [ReplayBikeStandTierPlan]
    let standTierCounts: ReplayQualityValues<Int>
    let standColor: ReplayThemedColor

    let roofHalfExtent: Double
    let roofCenterY: Double
    let roofThickness: Double
    let roofColor: ReplayThemedColor
    let roofBeamCounts: ReplayQualityValues<Int>
    let skylightCounts: ReplayQualityValues<Int>
    let hangarLightCounts: ReplayQualityValues<Int>

    let landmarks: [ReplayEnvironmentPlacement]
    let accentColor: ReplayThemedColor
    let hospitalityDeck: ReplayEnvironmentPlacement

    let lines: [ReplayBikeLinePlan]
    let sprintMarkers: ReplayBikeSprintMarkerPlan
}

enum ReplayEnvironmentVenuePlan: Equatable, Sendable {
    case rower(ReplayRowerVenuePlan)
    case skierg(ReplaySkiVenuePlan)
    case bike(ReplayBikeVenuePlan)
}

struct ReplayEnvironmentPlan: Equatable, Sendable {
    static let authoredLoopRadius = 30.0
    /// The four bundled families bound by primary runtime receivers. The
    /// remaining provenance-recorded families stay validated inventory.
    static let primaryRuntimeTextureFamilies: [ReplayEnvironmentTextureFamily] = [
        .aerialGrassRock,
        .snow02,
        .brushedConcrete2,
        .woodFloor,
    ]

    let sport: Sport
    let lighting: ReplayEnvironmentLightingPlan
    let skyColor: ReplayThemedColor
    let horizonColor: ReplayThemedColor
    let ground: ReplayEnvironmentGroundPlan
    let structureColor: ReplayThemedColor
    let venue: ReplayEnvironmentVenuePlan

    static func plan(for sport: Sport) -> ReplayEnvironmentPlan {
        switch sport {
        case .rower: rower
        case .skierg: skierg
        case .bike: bike
        }
    }

    static let rower = ReplayEnvironmentPlan(
        sport: .rower,
        lighting: ReplayEnvironmentLightingPlan(
            sunColor: ReplayThemedColor(0xFFEDC1, 0xFFCE82),
            sunIntensity: 10_200,
            sunOffset: SIMD3(-22, 18, 14),
            fillColor: ReplayThemedColor(0xBFE9F1, 0x568B9A),
            fillIntensity: 2_800
        ),
        skyColor: ReplayThemedColor(0x94C5D8, 0x173849),
        horizonColor: ReplayThemedColor(0x6F9381, 0x244B46),
        ground: ReplayEnvironmentGroundPlan(
            halfExtent: 85,
            family: nil,
            color: ReplayThemedColor(0x2F879C, 0x104D60),
            roughness: 0.18,
            metallic: 0.06,
            textureRepeat: SIMD2(1, 1)
        ),
        structureColor: ReplayThemedColor(0xE8E4D8, 0x7F9093),
        venue: .rower(ReplayRowerVenuePlan(
            basinRadius: 38,
            basinHeight: 0.025,
            basinCenterY: 0,
            basinColor: ReplayThemedColor(0x378DA0, 0x155568),
            basinRoughness: 0.18,
            basinMetallic: 0.06,
            islandRadius: 15.5,
            islandHeight: 0.18,
            islandCenterY: 0.08,
            islandColor: ReplayThemedColor(0x2F8198, 0x124F62),
            landmarks: [
                ReplayEnvironmentPlacement(
                    name: "regatta-pavilion",
                    angleDegrees: 17,
                    radius: 72,
                    // Pinned renderer scale [0.9, 0.88, 0.86] applied to the
                    // shared 10.7 x 4.075 x 5.56 m pavilion envelope.
                    size: SIMD3(9.63, 3.586, 4.782)
                ),
                ReplayEnvironmentPlacement(
                    name: "boathouse",
                    angleDegrees: 32,
                    radius: 75,
                    size: SIMD3(7.704, 3.016, 4.226)
                ),
                ReplayEnvironmentPlacement(
                    name: "timing-tower",
                    angleDegrees: 43,
                    radius: 70,
                    size: SIMD3(5.35, 5.135, 3.114)
                ),
            ],
            landmarkCounts: ReplayQualityValues(1, 2, 3, 3),
            islandTreeCounts: ReplayQualityValues(4, 7, 10, 13),
            islandTreeRadius: 11.16,
            islandTree: ReplayEnvironmentMarkerPlan(
                centerY: 1.65,
                size: SIMD3(1.7, 3.3, 1.7)
            ),
            foliageColor: ReplayThemedColor(0x3F6D50, 0x1C493D),
            shorelineSectors: [
                ReplayEnvironmentSector(startDegrees: -48, spanDegrees: 52, weight: 1.1),
                ReplayEnvironmentSector(startDegrees: 62, spanDegrees: 100, weight: 1.35),
                ReplayEnvironmentSector(startDegrees: 188, spanDegrees: 110, weight: 1.2),
            ],
            shorelineInnerRadius: 38.4,
            shorelineOuterRadius: 44,
            shorelineColor: ReplayThemedColor(0x697A58, 0x34483E),
            woodlandTreeCounts: ReplayQualityValues(14, 32, 72, 104),
            woodlandInnerRadius: 47,
            woodlandOuterRadius: 69,
            woodlandTree: ReplayEnvironmentMarkerPlan(
                centerY: 2.75,
                size: SIMD3(1.8, 5.5, 1.8)
            ),
            ultraBoardwalk: ReplayEnvironmentPlacement(
                name: "wetland-boardwalk",
                angleDegrees: 320,
                radius: 45.5,
                size: SIMD3(12, 0.22, 2.1)
            ),
            buoyRingRadii: [23.8, 32.4],
            buoy: ReplayEnvironmentMarkerPlan(
                centerY: 0.12,
                size: SIMD3(0.12, 0.22, 0.12)
            ),
            buoyColor: ReplayThemedColor(0xA65E3B, 0xD9A066)
        ))
    )

    static let skierg = ReplayEnvironmentPlan(
        sport: .skierg,
        lighting: ReplayEnvironmentLightingPlan(
            sunColor: ReplayThemedColor(0xFFE8C0, 0xEAF6FF),
            sunIntensity: 10_800,
            sunOffset: SIMD3(16, 28, 10),
            fillColor: ReplayThemedColor(0x7FA3C4, 0x719BB5),
            fillIntensity: 2_480
        ),
        skyColor: ReplayThemedColor(0x45647D, 0x142B42),
        horizonColor: ReplayThemedColor(0x617E8D, 0x2E4A5A),
        ground: ReplayEnvironmentGroundPlan(
            halfExtent: 85,
            family: .snow02,
            color: ReplayThemedColor(0xAABFD0, 0x8FA5B3),
            roughness: 0.94,
            metallic: 0.01,
            textureRepeat: SIMD2(14, 14)
        ),
        structureColor: ReplayThemedColor(0x25394A, 0x192F3D),
        venue: .skierg(ReplaySkiVenuePlan(
            fieldRadius: 33,
            fieldHeight: 0.04,
            fieldCenterY: 0,
            fieldColor: ReplayThemedColor(0xC7D6E2, 0x849DAA),
            fieldRoughness: 0.94,
            groomLineCounts: ReplayQualityValues(2, 4, 6, 8),
            landmarks: [
                ReplayEnvironmentPlacement(
                    name: "timing-lodge",
                    angleDegrees: 6,
                    radius: 59,
                    size: SIMD3(11.235, 4.564, 5.56)
                ),
                ReplayEnvironmentPlacement(
                    name: "wax-hut",
                    angleDegrees: 19.2,
                    radius: 61,
                    size: SIMD3(7.276, 3.097, 4.114)
                ),
            ],
            landmarkCounts: ReplayQualityValues(1, 1, 2, 2),
            forestTreeCounts: ReplayQualityValues(10, 36, 88, 132),
            forestSectors: [
                ReplayEnvironmentSector(startDegrees: -170, spanDegrees: 55, weight: 0.95),
                ReplayEnvironmentSector(startDegrees: 105, spanDegrees: 65, weight: 1.1),
                ReplayEnvironmentSector(startDegrees: 40, spanDegrees: 28, weight: 0.75),
                ReplayEnvironmentSector(startDegrees: 205, spanDegrees: 52, weight: 0.9),
            ],
            forestInnerRadius: 55,
            forestOuterRadius: 91,
            forestTree: ReplayEnvironmentMarkerPlan(
                centerY: 2.7,
                size: SIMD3(1.5, 5.4, 1.5)
            ),
            forestColor: ReplayThemedColor(0x435D72, 0x315267),
            alpineSectors: [
                ReplayEnvironmentSector(startDegrees: -150, spanDegrees: 65, weight: 1.1),
                ReplayEnvironmentSector(startDegrees: 35, spanDegrees: 60),
            ],
            alpineShoulderCounts: ReplayQualityValues(2, 3, 5, 7),
            alpineInnerRadius: 103,
            alpineOuterRadius: 126,
            alpineShoulder: ReplayEnvironmentMarkerPlan(
                centerY: 6,
                size: SIMD3(14, 12, 18)
            ),
            alpineColor: ReplayThemedColor(0x7897A8, 0x4F6A7A),
            floodlights: [-8.0, 2, 12, 22, 32, -16, 38, 18].enumerated().map { index, angle in
                ReplayEnvironmentPlacement(
                    name: "floodlight-\(index + 1)",
                    angleDegrees: angle,
                    radius: index < 4 ? 53 : 55.5,
                    size: SIMD3(0.18, 5.5, 0.18)
                )
            },
            floodlightCounts: ReplayQualityValues(0, 4, 6, 8),
            floodlightColor: ReplayThemedColor(0xFFC97E, 0xFFC27A),
            ultraShelter: ReplayEnvironmentPlacement(
                name: "mountain-rescue-shelter",
                angleDegrees: 216,
                radius: 78,
                size: SIMD3(7.704, 2.934, 4.114)
            )
        ))
    )

    static let bike = ReplayEnvironmentPlan(
        sport: .bike,
        lighting: ReplayEnvironmentLightingPlan(
            sunColor: ReplayThemedColor(0xFFE2B0, 0xFFD49A),
            sunIntensity: 14_000,
            sunOffset: SIMD3(12, 20, -10),
            fillColor: ReplayThemedColor(0x7D94A8, 0x6D8BA0),
            fillIntensity: 2_480
        ),
        skyColor: ReplayThemedColor(0xD2DCDE, 0x263642),
        horizonColor: ReplayThemedColor(0x5A646C, 0x344452),
        ground: ReplayEnvironmentGroundPlan(
            halfExtent: 85,
            family: .brushedConcrete2,
            color: ReplayThemedColor(0x847D70, 0x3C3C3A),
            roughness: 0.82,
            metallic: 0.025,
            textureRepeat: SIMD2(14, 14)
        ),
        structureColor: ReplayThemedColor(0x5A646C, 0x344452),
        venue: .bike(ReplayBikeVenuePlan(
            trackInnerRadius: 22,
            trackOuterRadius: 34,
            trackHeight: 0.02,
            trackCenterY: 0,
            trackColor: ReplayThemedColor(0xDBC09A, 0xE6CFA8),
            trackRoughness: 0.82,
            infieldRadius: 33.1,
            infieldHeight: 0.02,
            // Matches the pinned web receiver's visible top surface at -0.015
            // while the timber annulus remains above it.
            infieldCenterY: -0.025,
            infieldColor: ReplayThemedColor(0x6D7A74, 0x405149),
            wallRadius: 61.5,
            wallSegments: ReplayQualityValues(16, 24, 32, 40),
            wallSectors: [
                ReplayEnvironmentSector(startDegrees: 55, spanDegrees: 85, weight: 1.2),
                ReplayEnvironmentSector(startDegrees: 220, spanDegrees: 60, weight: 0.85),
                ReplayEnvironmentSector(startDegrees: 164, spanDegrees: 42),
                ReplayEnvironmentSector(startDegrees: 228, spanDegrees: 42),
            ],
            wall: ReplayEnvironmentMarkerPlan(
                centerY: 3.1,
                size: SIMD3(5.5, 6.2, 0.4)
            ),
            wallColor: ReplayThemedColor(0x5A646C, 0x344452),
            standSectors: [
                ReplayEnvironmentSector(startDegrees: 55, spanDegrees: 85, weight: 1.2),
                ReplayEnvironmentSector(startDegrees: 220, spanDegrees: 60, weight: 0.85),
            ],
            standTiers: [
                ReplayBikeStandTierPlan(innerRadius: 44.5, outerRadius: 47.6, centerY: 0.42),
                ReplayBikeStandTierPlan(innerRadius: 47.8, outerRadius: 51.2, centerY: 0.92),
                ReplayBikeStandTierPlan(innerRadius: 50.8, outerRadius: 54.1, centerY: 1.62),
                ReplayBikeStandTierPlan(innerRadius: 53.7, outerRadius: 57.2, centerY: 2.46),
                ReplayBikeStandTierPlan(innerRadius: 56.8, outerRadius: 60.2, centerY: 3.35),
            ],
            standTierCounts: ReplayQualityValues(2, 3, 4, 5),
            standColor: ReplayThemedColor(0x65727A, 0x26343E),
            roofHalfExtent: 72,
            roofCenterY: 13.7,
            roofThickness: 0.3,
            roofColor: ReplayThemedColor(0xD2DCDE, 0x263642),
            roofBeamCounts: ReplayQualityValues(2, 3, 5, 7),
            skylightCounts: ReplayQualityValues(0, 2, 3, 4),
            hangarLightCounts: ReplayQualityValues(0, 6, 10, 14),
            landmarks: [
                ReplayEnvironmentPlacement(
                    name: "scoreboard",
                    angleDegrees: 95.8,
                    radius: 58,
                    size: SIMD3(9.4, 6.5, 0.42)
                ),
                ReplayEnvironmentPlacement(
                    name: "service-building",
                    angleDegrees: 251.1,
                    radius: 60,
                    size: SIMD3(8.774, 3.342, 5.838)
                ),
            ],
            accentColor: ReplayThemedColor(0xD79A50, 0xF0B667),
            hospitalityDeck: ReplayEnvironmentPlacement(
                name: "hospitality-deck",
                angleDegrees: 99.2,
                radius: 58.2,
                size: SIMD3(13.5, 3.1, 4.6)
            ),
            lines: [
                ReplayBikeLinePlan(
                    name: "cote-d-azur",
                    radius: 22.32,
                    radialWidth: 0.52,
                    centerY: 0.052,
                    height: 0.006,
                    color: ReplayThemedColor(0x7DB6CC, 0x2C5A6E)
                ),
                ReplayBikeLinePlan(
                    name: "measurement-black",
                    radius: 22.72,
                    radialWidth: 0.052,
                    centerY: 0.063,
                    height: 0.052,
                    color: ReplayThemedColor(0x725F4D, 0x51463E)
                ),
                ReplayBikeLinePlan(
                    name: "pursuit-blue",
                    radius: 28,
                    radialWidth: 0.056,
                    centerY: 0.064,
                    height: 0.056,
                    color: ReplayThemedColor(0x2F7298, 0x5FA4C4)
                ),
                ReplayBikeLinePlan(
                    name: "sprinter-red",
                    radius: 33.2,
                    radialWidth: 0.052,
                    centerY: 0.063,
                    height: 0.052,
                    color: ReplayThemedColor(0xC63F38, 0xE9685E)
                ),
            ],
            sprintMarkers: ReplayBikeSprintMarkerPlan(
                name: "sprint-marker-red",
                radius: 32.65,
                anglesDegrees: [-6, -2, 2, 6, 174, 178, 182, 186],
                radialWidth: 0.11,
                tangentialLength: 0.9,
                centerY: 0.076,
                height: 0.035,
                color: ReplayThemedColor(0xC63F38, 0xE9685E)
            )
        ))
    )
}

/// Maps authored web-planar coordinates into one native course layout without
/// altering the environment root or any vertical/object dimensions.
struct ReplayEnvironmentPlanarMapping: Equatable, Sendable {
    let scale: Double

    init(layout: ReplayCourseLayout) {
        scale = layout.loopRadius / ReplayEnvironmentPlan.authoredLoopRadius
    }

    func radius(_ authoredRadius: Double) -> Float {
        Float(authoredRadius * scale)
    }

    func extent(_ authoredExtent: Double) -> Float {
        Float(authoredExtent * scale)
    }

    func position(
        angleRadians: Double,
        authoredRadius: Double,
        y: Double
    ) -> SIMD3<Float> {
        let nativeRadius = radius(authoredRadius)
        let angle = Float(angleRadians)
        return SIMD3(nativeRadius * sin(angle), Float(y), nativeRadius * cos(angle))
    }
}
