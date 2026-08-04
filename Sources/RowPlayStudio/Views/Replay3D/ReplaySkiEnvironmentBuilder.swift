import RealityKit
import RowPlayCore

/// Builds the blue-hour Nordic stadium, groomed centre, sectorized forest,
/// alpine shoulders, and tier-gated competition infrastructure.
@MainActor
enum ReplaySkiEnvironmentBuilder {
    static func build(
        _ venue: ReplaySkiVenuePlan,
        plan: ReplayEnvironmentPlan,
        quality: ReplayRenderQuality,
        theme: ReplayEnvironmentTheme,
        mapping: ReplayEnvironmentPlanarMapping,
        materials: ReplayEnvironmentMaterialLibrary,
        into root: Entity
    ) {
        let snow = materials.material(
            family: .snow02,
            baseColor: venue.fieldColor.resolvedColor(for: theme),
            roughness: venue.fieldRoughness,
            quality: quality,
            textureRepeat: SIMD2(12, 12)
        )
        ReplayEnvironmentGeometry.addDisk(
            name: "nordic-stadium-field",
            authoredRadius: venue.fieldRadius,
            height: venue.fieldHeight,
            centerY: venue.fieldCenterY,
            material: snow,
            mapping: mapping,
            to: root
        )

        let packedSnow = materials.material(
            family: .snow02,
            baseColor: ReplayThemedColor(0xD4E2EC, 0x9BB0C0).resolvedColor(for: theme),
            roughness: 0.9,
            quality: quality,
            textureRepeat: SIMD2(6, 6)
        )
        ReplayEnvironmentGeometry.addDisk(
            name: "nordic-start-pad",
            authoredRadius: 8.5,
            height: 0.025,
            centerY: 0.035,
            material: packedSnow,
            mapping: mapping,
            to: root
        )
        addGroomLines(
            count: venue.groomLineCounts[quality],
            theme: theme,
            mapping: mapping,
            to: root
        )

        let structure = ReplayEnvironmentGeometry.simple(plan.structureColor, theme: theme)
        for placement in venue.landmarks.prefix(venue.landmarkCounts[quality]) {
            ReplayEnvironmentGeometry.addLandmark(
                placement,
                material: structure,
                mapping: mapping,
                to: root
            )
        }

        let pine = ReplayEnvironmentGeometry.simple(
            venue.forestColor,
            theme: theme,
            roughness: 1
        )
        ReplayEnvironmentGeometry.addSectorMarkers(
            count: venue.forestTreeCounts[quality],
            authoredInnerRadius: venue.forestInnerRadius,
            authoredOuterRadius: venue.forestOuterRadius,
            marker: venue.forestTree,
            prefix: "nordic-pine",
            material: pine,
            sectors: venue.forestSectors,
            mapping: mapping,
            to: root
        )

        let alpine = ReplayEnvironmentGeometry.simple(
            venue.alpineColor,
            theme: theme,
            roughness: 0.96
        )
        ReplayEnvironmentGeometry.addSectorMarkers(
            count: venue.alpineShoulderCounts[quality],
            authoredInnerRadius: venue.alpineInnerRadius,
            authoredOuterRadius: venue.alpineOuterRadius,
            marker: venue.alpineShoulder,
            prefix: "alpine-shoulder",
            material: alpine,
            sectors: venue.alpineSectors,
            mapping: mapping,
            to: root
        )

        for placement in venue.floodlights.prefix(venue.floodlightCounts[quality]) {
            addFloodlight(
                placement,
                structure: ReplayEnvironmentGeometry.simple(
                    plan.structureColor,
                    theme: theme,
                    roughness: 0.48
                ),
                glow: ReplayEnvironmentGeometry.simple(
                    venue.floodlightColor,
                    theme: theme,
                    roughness: 0.3
                ),
                mapping: mapping,
                to: root
            )
        }

        if quality == .ultra {
            ReplayEnvironmentGeometry.addLandmark(
                venue.ultraShelter,
                material: structure,
                mapping: mapping,
                to: root
            )
        }
    }

    private static func addGroomLines(
        count: Int,
        theme: ReplayEnvironmentTheme,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        guard count > 0 else { return }
        let group = Entity()
        group.name = "nordic-groom-lines"
        let mesh = MeshResource.generateBox(size: SIMD3(
            mapping.extent(24),
            0.025,
            mapping.extent(0.18)
        ))
        let material = ReplayEnvironmentGeometry.simple(
            ReplayThemedColor(0xC0D2DE, 0x6E8796),
            theme: theme,
            roughness: 0.95
        )
        for index in 0..<count {
            let across = (Double(index) / Double(max(1, count - 1)) - 0.5) * 16
            let line = ModelEntity(mesh: mesh, materials: [material])
            line.name = "nordic-groom-line-\(index + 1)"
            line.position = SIMD3(
                mapping.extent(across * 0.12),
                0.052,
                mapping.extent(across * 0.04)
            )
            line.orientation = simd_quatf(
                angle: Float(6 * Double.pi / 180),
                axis: SIMD3(0, 1, 0)
            )
            group.addChild(line)
        }
        root.addChild(group)
    }

    private static func addFloodlight(
        _ placement: ReplayEnvironmentPlacement,
        structure: SimpleMaterial,
        glow: SimpleMaterial,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        let floodlight = Entity()
        floodlight.name = placement.name
        floodlight.position = mapping.position(
            angleRadians: placement.angleRadians,
            authoredRadius: placement.radius,
            y: 0
        )
        floodlight.orientation = simd_quatf(
            angle: Float(placement.angleRadians),
            axis: SIMD3(0, 1, 0)
        )

        let pole = ModelEntity(
            mesh: .generateCylinder(height: 8, radius: 0.13),
            materials: [structure]
        )
        pole.name = "\(placement.name)-pole"
        pole.position.y = 4
        floodlight.addChild(pole)

        let panel = ModelEntity(
            mesh: .generateBox(size: SIMD3(2.2, 0.7, 0.22)),
            materials: [glow]
        )
        panel.name = "\(placement.name)-panel"
        panel.position.y = 8.15
        floodlight.addChild(panel)
        root.addChild(floodlight)
    }
}
