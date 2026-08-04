import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// Deterministically builds one complete native venue. Geometry construction
/// is non-failable; individual missing texture maps degrade to scalar PBR in
/// `ReplayEnvironmentMaterialLibrary`.
@MainActor
enum ReplayEnvironmentInstaller {
    static func install(
        sport: Sport,
        quality: ReplayRenderQuality,
        colorScheme: ColorScheme,
        layout: ReplayCourseLayout = .standard
    ) -> Entity {
        let plan = ReplayEnvironmentPlan.plan(for: sport)
        let mapping = ReplayEnvironmentPlanarMapping(layout: layout)
        let theme: ReplayEnvironmentTheme = colorScheme == .dark ? .dark : .light
        let materials = ReplayEnvironmentMaterialLibrary.shared
        let root = Entity()
        root.name = "premium-environment-\(sport.rawValue)-\(quality.rawValue)"

        let ground = ModelEntity(
            mesh: .generatePlane(
                width: mapping.extent(plan.ground.halfExtent * 2),
                depth: mapping.extent(plan.ground.halfExtent * 2)
            ),
            materials: [materials.material(
                family: plan.ground.family,
                baseColor: plan.ground.color.resolvedColor(for: theme),
                roughness: plan.ground.roughness,
                quality: quality,
                textureRepeat: plan.ground.textureRepeat,
                metallic: plan.ground.metallic
            )]
        )
        ground.name = "venue-ground"
        ground.position.y = -0.04
        root.addChild(ground)

        let dressing = Entity()
        dressing.name = "venue-dressing-\(quality.rawValue)"
        root.addChild(dressing)

        switch plan.venue {
        case let .rower(venue):
            buildRower(
                venue,
                plan: plan,
                quality: quality,
                theme: theme,
                mapping: mapping,
                materials: materials,
                into: dressing
            )
        case let .skierg(venue):
            buildSki(
                venue,
                plan: plan,
                quality: quality,
                theme: theme,
                mapping: mapping,
                materials: materials,
                into: dressing
            )
        case let .bike(venue):
            buildBike(
                venue,
                plan: plan,
                quality: quality,
                theme: theme,
                mapping: mapping,
                materials: materials,
                into: dressing
            )
        }
        return root
    }

    private static func buildRower(
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
        addDisk(
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
        addDisk(
            name: "island-park",
            authoredRadius: venue.islandRadius,
            height: venue.islandHeight,
            centerY: venue.islandCenterY,
            material: island,
            mapping: mapping,
            to: root
        )

        let structure = simple(plan.structureColor, theme: theme)
        for placement in venue.landmarks.prefix(venue.landmarkCounts[quality]) {
            addLandmark(placement, material: structure, mapping: mapping, to: root)
        }

        let foliage = simple(venue.foliageColor, theme: theme, roughness: 1)
        addRingMarkers(
            count: venue.islandTreeCounts[quality],
            authoredRadius: venue.islandTreeRadius,
            marker: venue.islandTree,
            prefix: "island-tree",
            material: foliage,
            mapping: mapping,
            to: root
        )

        let buoy = simple(venue.buoyColor, theme: theme, roughness: 0.45)
        for (ringIndex, radius) in venue.buoyRingRadii.enumerated() {
            addRingMarkers(
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

    private static func buildSki(
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
        addDisk(
            name: "nordic-stadium-field",
            authoredRadius: venue.fieldRadius,
            height: venue.fieldHeight,
            centerY: venue.fieldCenterY,
            material: snow,
            mapping: mapping,
            to: root
        )

        let structure = simple(plan.structureColor, theme: theme)
        for placement in venue.landmarks.prefix(venue.landmarkCounts[quality]) {
            addLandmark(placement, material: structure, mapping: mapping, to: root)
        }

        let pine = simple(venue.forestColor, theme: theme, roughness: 1)
        addRingMarkers(
            count: venue.forestTreeCounts[quality],
            authoredRadius: venue.forestRadius,
            marker: venue.forestTree,
            prefix: "nordic-pine",
            material: pine,
            mapping: mapping,
            to: root
        )

        let floodlight = simple(venue.floodlightColor, theme: theme, roughness: 0.3)
        for placement in venue.floodlights.prefix(venue.floodlightCounts[quality]) {
            addLandmark(placement, material: floodlight, mapping: mapping, to: root)
        }
    }

    private static func buildBike(
        _ venue: ReplayBikeVenuePlan,
        plan: ReplayEnvironmentPlan,
        quality: ReplayRenderQuality,
        theme: ReplayEnvironmentTheme,
        mapping: ReplayEnvironmentPlanarMapping,
        materials: ReplayEnvironmentMaterialLibrary,
        into root: Entity
    ) {
        let timber = materials.material(
            family: .woodFloor,
            baseColor: venue.trackColor.resolvedColor(for: theme),
            roughness: venue.trackRoughness,
            quality: quality,
            textureRepeat: SIMD2(18, 3)
        )
        addBikeTrackAnnulus(
            name: "velodrome-track",
            authoredInnerRadius: venue.trackInnerRadius,
            authoredOuterRadius: venue.trackOuterRadius,
            height: venue.trackHeight,
            centerY: venue.trackCenterY,
            segmentCount: quality.configuration.courseRingSegmentCount,
            material: timber,
            mapping: mapping,
            to: root
        )

        let infield = materials.material(
            family: .brushedConcrete2,
            baseColor: venue.infieldColor.resolvedColor(for: theme),
            roughness: 0.8,
            quality: quality,
            textureRepeat: SIMD2(10, 10)
        )
        addDisk(
            name: "velodrome-infield",
            authoredRadius: venue.infieldRadius,
            height: venue.infieldHeight,
            centerY: venue.infieldCenterY,
            material: infield,
            mapping: mapping,
            to: root
        )

        let wall = simple(venue.wallColor, theme: theme, roughness: 0.72)
        addRingMarkers(
            count: venue.wallSegments[quality],
            authoredRadius: venue.wallRadius,
            marker: venue.wall,
            prefix: "arena-wall",
            material: wall,
            mapping: mapping,
            to: root
        )

        let accent = simple(venue.accentColor, theme: theme, roughness: 0.42)
        for placement in venue.landmarks {
            addLandmark(
                placement,
                material: placement.name == "scoreboard" ? accent : wall,
                mapping: mapping,
                to: root
            )
        }

        let lineSegmentCount = quality.configuration.courseRingSegmentCount
        for line in venue.lines {
            addBikeLine(
                line,
                segmentCount: lineSegmentCount,
                material: simple(line.color, theme: theme, roughness: 0.56),
                mapping: mapping,
                to: root
            )
        }
        addBikeSprintMarkers(
            venue.sprintMarkers,
            material: simple(venue.sprintMarkers.color, theme: theme, roughness: 0.48),
            mapping: mapping,
            to: root
        )
    }

    private static func addLandmark(
        _ placement: ReplayEnvironmentPlacement,
        material: SimpleMaterial,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        let size = SIMD3(
            Float(placement.size.x),
            Float(placement.size.y),
            Float(placement.size.z)
        )
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        entity.name = placement.name
        entity.position = mapping.position(
            angleRadians: placement.angleRadians,
            authoredRadius: placement.radius,
            y: placement.size.y / 2
        )
        entity.orientation = simd_quatf(
            angle: Float(placement.angleRadians),
            axis: SIMD3(0, 1, 0)
        )
        root.addChild(entity)
    }

    private static func addRingMarkers(
        count: Int,
        authoredRadius: Double,
        marker: ReplayEnvironmentMarkerPlan,
        prefix: String,
        material: SimpleMaterial,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        guard count > 0 else { return }
        let size = SIMD3(
            Float(marker.size.x),
            Float(marker.size.y),
            Float(marker.size.z)
        )
        let mesh = MeshResource.generateBox(size: size)
        for index in 0..<count {
            let angle = Double(index) / Double(count) * .pi * 2
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "\(prefix)-\(index)"
            entity.position = mapping.position(
                angleRadians: angle,
                authoredRadius: authoredRadius,
                y: marker.centerY
            )
            entity.orientation = simd_quatf(angle: Float(angle), axis: SIMD3(0, 1, 0))
            root.addChild(entity)
        }
    }

    private static func addBikeLine(
        _ line: ReplayBikeLinePlan,
        segmentCount: Int,
        material: SimpleMaterial,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        guard segmentCount > 0 else { return }
        let group = Entity()
        group.name = "bike-line-\(line.name)"
        let radius = mapping.radius(line.radius)
        let width = mapping.extent(line.radialWidth)
        let segmentLength = (2 * Float.pi * radius / Float(segmentCount)) * 1.02
        let mesh = MeshResource.generateBox(
            size: SIMD3(segmentLength, Float(line.height), width)
        )
        for index in 0..<segmentCount {
            let angle = Float(index) / Float(segmentCount) * .pi * 2
            let segment = ModelEntity(mesh: mesh, materials: [material])
            segment.name = "\(line.name)-\(index)"
            segment.position = SIMD3(
                radius * sin(angle),
                Float(line.centerY),
                radius * cos(angle)
            )
            segment.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
            group.addChild(segment)
        }
        root.addChild(group)
    }

    /// Builds the pinned web lane as an annulus instead of two overlapping
    /// disks. The slight tangential overlap closes seams at every quality tier
    /// while preserving the authored inner and outer radial edges.
    private static func addBikeTrackAnnulus(
        name: String,
        authoredInnerRadius: Double,
        authoredOuterRadius: Double,
        height: Double,
        centerY: Double,
        segmentCount: Int,
        material: PhysicallyBasedMaterial,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        guard segmentCount > 0, authoredOuterRadius > authoredInnerRadius else { return }
        let group = Entity()
        group.name = name

        let centerRadius = mapping.radius((authoredInnerRadius + authoredOuterRadius) / 2)
        let outerRadius = mapping.radius(authoredOuterRadius)
        let radialWidth = mapping.extent(authoredOuterRadius - authoredInnerRadius)
        let segmentLength = (2 * Float.pi * outerRadius / Float(segmentCount)) * 1.02
        let mesh = MeshResource.generateBox(
            size: SIMD3(segmentLength, Float(height), radialWidth)
        )
        for index in 0..<segmentCount {
            let angle = Float(index) / Float(segmentCount) * .pi * 2
            let segment = ModelEntity(mesh: mesh, materials: [material])
            segment.name = "\(name)-segment-\(index)"
            segment.position = SIMD3(
                centerRadius * sin(angle),
                Float(centerY),
                centerRadius * cos(angle)
            )
            segment.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
            group.addChild(segment)
        }
        root.addChild(group)
    }

    private static func addBikeSprintMarkers(
        _ plan: ReplayBikeSprintMarkerPlan,
        material: SimpleMaterial,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        let group = Entity()
        group.name = "bike-sprint-markers"
        let mesh = MeshResource.generateBox(size: SIMD3(
            mapping.extent(plan.tangentialLength),
            Float(plan.height),
            mapping.extent(plan.radialWidth)
        ))
        for (index, angleDegrees) in plan.anglesDegrees.enumerated() {
            let angle = angleDegrees * .pi / 180
            let marker = ModelEntity(mesh: mesh, materials: [material])
            marker.name = "\(plan.name)-\(index)"
            marker.position = mapping.position(
                angleRadians: angle,
                authoredRadius: plan.radius,
                y: plan.centerY
            )
            marker.orientation = simd_quatf(angle: Float(angle), axis: SIMD3(0, 1, 0))
            group.addChild(marker)
        }
        root.addChild(group)
    }

    private static func addDisk(
        name: String,
        authoredRadius: Double,
        height: Double,
        centerY: Double,
        material: PhysicallyBasedMaterial,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        let disk = ModelEntity(
            mesh: .generateCylinder(
                height: Float(height),
                radius: mapping.radius(authoredRadius)
            ),
            materials: [material]
        )
        disk.name = name
        disk.position.y = Float(centerY)
        root.addChild(disk)
    }

    private static func simple(
        _ themed: ReplayThemedColor,
        theme: ReplayEnvironmentTheme,
        roughness: Float = 0.75
    ) -> SimpleMaterial {
        SimpleMaterial(
            color: themed.resolvedColor(for: theme),
            roughness: .init(floatLiteral: roughness),
            isMetallic: false
        )
    }
}
