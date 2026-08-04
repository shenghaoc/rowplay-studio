import Foundation
import RealityKit
import RowPlayCore

/// Shared deterministic geometry primitives for the three native replay
/// venues. Sport composition stays in focused builders; this type owns only
/// placement, planar mapping, and simple reusable shapes.
@MainActor
enum ReplayEnvironmentGeometry {
    static func addOutdoorAtmosphere(
        plan: ReplayEnvironmentPlan,
        theme: ReplayEnvironmentTheme,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        let atmosphere = Entity()
        atmosphere.name = "venue-atmosphere"

        let sky = ModelEntity(
            mesh: .generateBox(size: SIMD3(
                mapping.extent(plan.ground.halfExtent * 2),
                0.12,
                mapping.extent(plan.ground.halfExtent * 2)
            )),
            materials: [simple(plan.skyColor, theme: theme, roughness: 1)]
        )
        sky.name = "venue-sky"
        sky.position.y = 36
        atmosphere.addChild(sky)

        let horizonMaterial = simple(plan.horizonColor, theme: theme, roughness: 1)
        let count = 16
        let authoredRadius = plan.ground.halfExtent * 0.92
        let nativeRadius = mapping.radius(authoredRadius)
        let segmentLength = (2 * Float.pi * nativeRadius / Float(count)) * 1.03
        let mesh = MeshResource.generateBox(size: SIMD3(segmentLength, 26, 1.2))
        let horizon = Entity()
        horizon.name = "venue-horizon"
        for index in 0..<count {
            let angle = Float(index) / Float(count) * .pi * 2
            let panel = ModelEntity(mesh: mesh, materials: [horizonMaterial])
            panel.name = "venue-horizon-\(index)"
            panel.position = SIMD3(
                nativeRadius * sin(angle),
                13,
                nativeRadius * cos(angle)
            )
            panel.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
            horizon.addChild(panel)
        }
        atmosphere.addChild(horizon)
        root.addChild(atmosphere)
    }

    static func addLandmark(
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

    static func addSectorMarkers(
        count: Int,
        authoredInnerRadius: Double,
        authoredOuterRadius: Double,
        marker: ReplayEnvironmentMarkerPlan,
        prefix: String,
        material: SimpleMaterial,
        sectors: [ReplayEnvironmentSector],
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        guard count > 0, !sectors.isEmpty else { return }
        let size = SIMD3(
            Float(marker.size.x),
            Float(marker.size.y),
            Float(marker.size.z)
        )
        let mesh = MeshResource.generateBox(size: size)
        for index in 0..<count {
            let angle = sectorAngle(index: index, count: count, sectors: sectors)
            let depth = deterministicFraction(index: index, salt: 17.13)
            let authoredRadius = authoredInnerRadius
                + (authoredOuterRadius - authoredInnerRadius) * (0.1 + depth * 0.8)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "\(prefix)-\(index)"
            entity.position = mapping.position(
                angleRadians: angle,
                authoredRadius: authoredRadius,
                y: marker.centerY
            )
            entity.orientation = simd_quatf(
                angle: Float(angle + Double(index) * 0.17),
                axis: SIMD3(0, 1, 0)
            )
            root.addChild(entity)
        }
    }

    static func addSectorBands(
        name: String,
        authoredInnerRadius: Double,
        authoredOuterRadius: Double,
        centerY: Double,
        height: Double,
        sectors: [ReplayEnvironmentSector],
        segmentBudget: Int,
        material: SimpleMaterial,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        guard authoredOuterRadius > authoredInnerRadius,
              segmentBudget > 0,
              !sectors.isEmpty else { return }
        let group = Entity()
        group.name = name
        let totalSpan = sectors.reduce(0) { $0 + max(0, $1.spanRadians) }
        let centerRadius = mapping.radius((authoredInnerRadius + authoredOuterRadius) / 2)
        let radialWidth = mapping.extent(authoredOuterRadius - authoredInnerRadius)
        for (sectorIndex, sector) in sectors.enumerated() {
            let count = max(
                2,
                Int(round(Double(segmentBudget) * sector.spanRadians / max(0.001, totalSpan)))
            )
            let nativeArcLength = centerRadius * Float(sector.spanRadians)
            let segmentLength = nativeArcLength / Float(count) * 1.03
            let mesh = MeshResource.generateBox(size: SIMD3(
                segmentLength,
                Float(height),
                radialWidth
            ))
            for index in 0..<count {
                let angle = sector.startRadians
                    + (Double(index) + 0.5) / Double(count) * sector.spanRadians
                let segment = ModelEntity(mesh: mesh, materials: [material])
                segment.name = "\(name)-sector-\(sectorIndex + 1)-segment-\(index + 1)"
                segment.position = mapping.position(
                    angleRadians: angle,
                    authoredRadius: (authoredInnerRadius + authoredOuterRadius) / 2,
                    y: centerY
                )
                segment.orientation = simd_quatf(
                    angle: Float(angle),
                    axis: SIMD3(0, 1, 0)
                )
                group.addChild(segment)
            }
        }
        root.addChild(group)
    }

    static func addRingMarkers(
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

    static func addDisk(
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

    static func simple(
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

    private static func sectorAngle(
        index: Int,
        count: Int,
        sectors: [ReplayEnvironmentSector]
    ) -> Double {
        let totalWeight = sectors.reduce(0) {
            $0 + max(0, $1.spanRadians * $1.weight)
        }
        guard totalWeight > 0 else { return sectors[0].startRadians }
        var cursor = (Double(index) + 0.5) / Double(max(1, count)) * totalWeight
        for (sectorIndex, sector) in sectors.enumerated() {
            let weightedSpan = max(0, sector.spanRadians * sector.weight)
            if cursor <= weightedSpan || sectorIndex == sectors.count - 1 {
                let local = min(1, max(0, cursor / max(0.001, weightedSpan)))
                let jitter = (deterministicFraction(index: index, salt: 9.41) - 0.5)
                    * min(sector.spanRadians / Double(max(2, count)), 4 * .pi / 180)
                // Jitter breaks up the rank-and-file look inside a stand, but it
                // must never push scenery past the authored sector edge — that
                // is what keeps the sightlines between stands open.
                let jittered = sector.startRadians + sector.spanRadians * local + jitter
                return min(
                    max(jittered, sector.startRadians),
                    sector.startRadians + sector.spanRadians
                )
            }
            cursor -= weightedSpan
        }
        return sectors[0].startRadians
    }

    private static func deterministicFraction(index: Int, salt: Double) -> Double {
        let value = sin((Double(index) + 1) * salt) * 43_758.5453
        return value - floor(value)
    }
}
