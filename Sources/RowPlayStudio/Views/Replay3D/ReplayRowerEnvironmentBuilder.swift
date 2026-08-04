import RealityKit
import RowPlayCore

/// Builds the morning-glass regatta basin and its authored land-use sectors.
@MainActor
enum ReplayRowerEnvironmentBuilder {
    static func build(
        _ venue: ReplayRowerVenuePlan,
        plan: ReplayEnvironmentPlan,
        quality: ReplayRenderQuality,
        theme: ReplayEnvironmentTheme,
        mapping: ReplayEnvironmentPlanarMapping,
        materials: ReplayEnvironmentMaterialLibrary,
        into root: Entity
    ) {
        let water = materials.material(
            family: nil,
            baseColor: venue.basinColor.resolvedColor(for: theme),
            roughness: venue.basinRoughness,
            quality: quality,
            metallic: venue.basinMetallic
        )
        ReplayEnvironmentGeometry.addDisk(
            name: "regatta-basin",
            authoredRadius: venue.basinRadius,
            height: venue.basinHeight,
            centerY: venue.basinCenterY,
            material: water,
            mapping: mapping,
            to: root
        )

        let island = materials.material(
            family: .aerialGrassRock,
            baseColor: venue.islandColor.resolvedColor(for: theme),
            roughness: 0.9,
            quality: quality,
            textureRepeat: SIMD2(8, 8)
        )
        ReplayEnvironmentGeometry.addDisk(
            name: "island-park",
            authoredRadius: venue.islandRadius,
            height: venue.islandHeight,
            centerY: venue.islandCenterY,
            material: island,
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

        let foliage = ReplayEnvironmentGeometry.simple(
            venue.foliageColor,
            theme: theme,
            roughness: 1
        )
        ReplayEnvironmentGeometry.addSectorMarkers(
            count: venue.islandTreeCounts[quality],
            authoredInnerRadius: venue.islandTreeRadius * 0.3,
            authoredOuterRadius: venue.islandTreeRadius,
            marker: venue.islandTree,
            prefix: "island-tree",
            material: foliage,
            sectors: [
                ReplayEnvironmentSector(startDegrees: 14, spanDegrees: 34),
                ReplayEnvironmentSector(startDegrees: 101, spanDegrees: 28),
                ReplayEnvironmentSector(startDegrees: 202, spanDegrees: 32),
                ReplayEnvironmentSector(startDegrees: 309, spanDegrees: 26),
            ],
            mapping: mapping,
            to: root
        )

        let shoreline = ReplayEnvironmentGeometry.simple(
            venue.shorelineColor,
            theme: theme,
            roughness: 0.96
        )
        ReplayEnvironmentGeometry.addSectorBands(
            name: "regatta-shoreline",
            authoredInnerRadius: venue.shorelineInnerRadius,
            authoredOuterRadius: venue.shorelineOuterRadius,
            centerY: 0.03,
            height: 0.14,
            sectors: venue.shorelineSectors,
            segmentBudget: max(18, quality.configuration.courseRingSegmentCount / 2),
            material: shoreline,
            mapping: mapping,
            to: root
        )
        ReplayEnvironmentGeometry.addSectorMarkers(
            count: venue.woodlandTreeCounts[quality],
            authoredInnerRadius: venue.woodlandInnerRadius,
            authoredOuterRadius: venue.woodlandOuterRadius,
            marker: venue.woodlandTree,
            prefix: "bank-tree",
            material: foliage,
            sectors: venue.shorelineSectors,
            mapping: mapping,
            to: root
        )

        if quality == .ultra {
            ReplayEnvironmentGeometry.addLandmark(
                venue.ultraBoardwalk,
                material: ReplayEnvironmentGeometry.simple(
                    ReplayThemedColor(0x8D7558, 0x3F3428),
                    theme: theme
                ),
                mapping: mapping,
                to: root
            )
        }

        let buoy = ReplayEnvironmentGeometry.simple(
            venue.buoyColor,
            theme: theme,
            roughness: 0.45
        )
        for (ringIndex, radius) in venue.buoyRingRadii.enumerated() {
            ReplayEnvironmentGeometry.addRingMarkers(
                count: quality.configuration.buoysPerRing,
                authoredRadius: radius,
                marker: venue.buoy,
                prefix: "buoy-\(ringIndex)",
                material: buoy,
                mapping: mapping,
                to: root
            )
        }
    }
}
