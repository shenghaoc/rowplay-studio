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

    let landmarks: [ReplayEnvironmentPlacement]
    let landmarkCounts: ReplayQualityValues<Int>

    let forestTreeCounts: ReplayQualityValues<Int>
    let forestRadius: Double
    let forestTree: ReplayEnvironmentMarkerPlan
    let forestColor: ReplayThemedColor

    let floodlights: [ReplayEnvironmentPlacement]
    let floodlightCounts: ReplayQualityValues<Int>
    let floodlightColor: ReplayThemedColor
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
    let wall: ReplayEnvironmentMarkerPlan
    let wallColor: ReplayThemedColor

    let landmarks: [ReplayEnvironmentPlacement]
    let accentColor: ReplayThemedColor

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
                    size: SIMD3(0.9, 0.88, 0.86)
                ),
                ReplayEnvironmentPlacement(
                    name: "boathouse",
                    angleDegrees: 32,
                    radius: 75,
                    size: SIMD3(0.72, 0.74, 0.76)
                ),
                ReplayEnvironmentPlacement(
                    name: "timing-tower",
                    angleDegrees: 43,
                    radius: 70,
                    size: SIMD3(0.5, 1.26, 0.56)
                ),
            ],
            landmarkCounts: ReplayQualityValues(1, 2, 3, 3),
            islandTreeCounts: ReplayQualityValues(4, 7, 10, 13),
            islandTreeRadius: 11.16,
            islandTree: ReplayEnvironmentMarkerPlan(
                centerY: 0.65,
                size: SIMD3(0.35, 1.25, 0.35)
            ),
            foliageColor: ReplayThemedColor(0x3F6D50, 0x1C493D),
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
            landmarks: [
                ReplayEnvironmentPlacement(
                    name: "timing-lodge",
                    angleDegrees: 6,
                    radius: 59,
                    size: SIMD3(1.05, 1.12, 1)
                ),
                ReplayEnvironmentPlacement(
                    name: "wax-hut",
                    angleDegrees: 19.2,
                    radius: 61,
                    size: SIMD3(0.68, 0.76, 0.74)
                ),
            ],
            landmarkCounts: ReplayQualityValues(1, 1, 2, 2),
            forestTreeCounts: ReplayQualityValues(10, 36, 88, 132),
            forestRadius: 74,
            forestTree: ReplayEnvironmentMarkerPlan(
                centerY: 1.1,
                size: SIMD3(0.45, 2.2, 0.45)
            ),
            forestColor: ReplayThemedColor(0x435D72, 0x315267),
            floodlights: [-8.0, 2, 12, 22, 32, -16, 38, 18].enumerated().map { index, angle in
                ReplayEnvironmentPlacement(
                    name: "floodlight-\(index + 1)",
                    angleDegrees: angle,
                    radius: index < 4 ? 53 : 55.5,
                    size: SIMD3(0.18, 5.5, 0.18)
                )
            },
            floodlightCounts: ReplayQualityValues(0, 4, 6, 8),
            floodlightColor: ReplayThemedColor(0xFFC97E, 0xFFC27A)
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
            wall: ReplayEnvironmentMarkerPlan(
                centerY: 3.1,
                size: SIMD3(5.5, 6.2, 0.4)
            ),
            wallColor: ReplayThemedColor(0x5A646C, 0x344452),
            landmarks: [
                ReplayEnvironmentPlacement(
                    name: "scoreboard",
                    angleDegrees: 95.8,
                    radius: 58,
                    size: SIMD3(1.8, 1.1, 0.3)
                ),
                ReplayEnvironmentPlacement(
                    name: "service-building",
                    angleDegrees: 251.1,
                    radius: 60,
                    size: SIMD3(0.82, 0.82, 1.05)
                ),
            ],
            accentColor: ReplayThemedColor(0xD79A50, 0xF0B667),
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
