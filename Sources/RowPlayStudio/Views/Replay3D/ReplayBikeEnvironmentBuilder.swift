import RealityKit
import RowPlayCore

/// Builds the enclosed evening velodrome, including timber track, regulation
/// line grammar, seating sectors, roof programme, and additive quality layers.
@MainActor
enum ReplayBikeEnvironmentBuilder {
    static func build(
        _ venue: ReplayBikeVenuePlan,
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
        addTrackAnnulus(
            venue,
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
        ReplayEnvironmentGeometry.addDisk(
            name: "velodrome-infield",
            authoredRadius: venue.infieldRadius,
            height: venue.infieldHeight,
            centerY: venue.infieldCenterY,
            material: infield,
            mapping: mapping,
            to: root
        )

        let wall = ReplayEnvironmentGeometry.simple(
            venue.wallColor,
            theme: theme,
            roughness: 0.72
        )
        ReplayEnvironmentGeometry.addSectorMarkers(
            count: venue.wallSegments[quality],
            authoredInnerRadius: venue.wallRadius,
            authoredOuterRadius: venue.wallRadius,
            marker: venue.wall,
            prefix: "arena-wall",
            material: wall,
            sectors: venue.wallSectors,
            mapping: mapping,
            to: root
        )

        addSeating(
            venue,
            quality: quality,
            material: ReplayEnvironmentGeometry.simple(
                venue.standColor,
                theme: theme,
                roughness: 0.88
            ),
            mapping: mapping,
            to: root
        )
        addRoof(venue, quality: quality, theme: theme, mapping: mapping, to: root)
        addInfieldMarkings(venue, quality: quality, theme: theme, mapping: mapping, to: root)

        let accent = ReplayEnvironmentGeometry.simple(
            venue.accentColor,
            theme: theme,
            roughness: 0.42
        )
        if quality == .high || quality == .ultra {
            for placement in venue.landmarks {
                ReplayEnvironmentGeometry.addLandmark(
                    placement,
                    material: placement.name == "scoreboard" ? accent : wall,
                    mapping: mapping,
                    to: root
                )
            }
            addTeamPit(venue, theme: theme, mapping: mapping, to: root)
        }
        if quality == .ultra {
            ReplayEnvironmentGeometry.addLandmark(
                venue.hospitalityDeck,
                material: accent,
                mapping: mapping,
                to: root
            )
        }

        let lineSegmentCount = quality.configuration.courseRingSegmentCount
        for line in venue.lines {
            addLine(
                line,
                segmentCount: lineSegmentCount,
                material: ReplayEnvironmentGeometry.simple(
                    line.color,
                    theme: theme,
                    roughness: 0.56
                ),
                mapping: mapping,
                to: root
            )
        }
        addSprintMarkers(
            venue.sprintMarkers,
            material: ReplayEnvironmentGeometry.simple(
                venue.sprintMarkers.color,
                theme: theme,
                roughness: 0.48
            ),
            mapping: mapping,
            to: root
        )
    }

    private static func addSeating(
        _ venue: ReplayBikeVenuePlan,
        quality: ReplayRenderQuality,
        material: SimpleMaterial,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        let stands = Entity()
        stands.name = "velodrome-stands"
        for (tierIndex, tier) in venue.standTiers
            .prefix(venue.standTierCounts[quality])
            .enumerated() {
            ReplayEnvironmentGeometry.addSectorBands(
                name: "velodrome-stands-tier-\(tierIndex + 1)",
                authoredInnerRadius: tier.innerRadius,
                authoredOuterRadius: tier.outerRadius,
                centerY: tier.centerY,
                height: 0.26,
                sectors: venue.standSectors,
                segmentBudget: max(16, quality.configuration.courseRingSegmentCount / 3),
                material: material,
                mapping: mapping,
                to: stands
            )
        }
        root.addChild(stands)
    }

    private static func addRoof(
        _ venue: ReplayBikeVenuePlan,
        quality: ReplayRenderQuality,
        theme: ReplayEnvironmentTheme,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        let roof = Entity()
        roof.name = "velodrome-roof-canopy"
        let roofMaterial = ReplayEnvironmentGeometry.simple(
            venue.roofColor,
            theme: theme,
            roughness: 0.86
        )
        let shell = ModelEntity(
            mesh: .generateBox(size: SIMD3(
                mapping.extent(venue.roofHalfExtent * 2),
                Float(venue.roofThickness),
                mapping.extent(venue.roofHalfExtent * 2)
            )),
            materials: [roofMaterial]
        )
        shell.name = "velodrome-roof-shell"
        shell.position.y = Float(venue.roofCenterY)
        roof.addChild(shell)

        let beamMaterial = ReplayEnvironmentGeometry.simple(
            ReplayThemedColor(0x73828A, 0x2A3946),
            theme: theme,
            roughness: 0.54
        )
        let beamCount = venue.roofBeamCounts[quality]
        let beamMesh = MeshResource.generateBox(size: SIMD3(mapping.extent(118), 0.28, 0.42))
        for index in 0..<beamCount {
            let beam = ModelEntity(mesh: beamMesh, materials: [beamMaterial])
            beam.name = "velodrome-roof-truss-\(index + 1)"
            let fraction = Double(index) / Double(max(1, beamCount - 1))
            beam.position = SIMD3(0, 12.45, mapping.extent(-30 + fraction * 60))
            roof.addChild(beam)
        }

        let skylightCount = venue.skylightCounts[quality]
        if skylightCount > 0 {
            let skylightMaterial = ReplayEnvironmentGeometry.simple(
                ReplayThemedColor(0xF4FBFF, 0x9FC7DA),
                theme: theme,
                roughness: 0.18
            )
            let skylightMesh = MeshResource.generateBox(size: SIMD3(
                mapping.extent(4.6),
                0.08,
                mapping.extent(54)
            ))
            for index in 0..<skylightCount {
                let strip = ModelEntity(mesh: skylightMesh, materials: [skylightMaterial])
                strip.name = "velodrome-skylight-\(index + 1)"
                let fraction = Double(index) / Double(max(1, skylightCount - 1))
                strip.position = SIMD3(mapping.extent(-24 + fraction * 48), 13.42, 0)
                roof.addChild(strip)
            }
        }

        let lightCount = venue.hangarLightCounts[quality]
        if lightCount > 0 {
            let lightMaterial = ReplayEnvironmentGeometry.simple(
                ReplayThemedColor(0xFFF4D9, 0xFFD49A),
                theme: theme,
                roughness: 0.24
            )
            let lightMesh = MeshResource.generateBox(size: SIMD3(1.8, 0.25, 0.55))
            for index in 0..<lightCount {
                let row = index % 2
                let column = index / 2
                let columns = Int(ceil(Double(lightCount) / 2))
                let light = ModelEntity(mesh: lightMesh, materials: [lightMaterial])
                light.name = "velodrome-hangar-light-\(index + 1)"
                light.position = SIMD3(
                    mapping.extent(row == 0 ? -17 : 17),
                    10.6,
                    mapping.extent(
                        -27 + Double(column) / Double(max(1, columns - 1)) * 54
                    )
                )
                roof.addChild(light)
            }
        }
        root.addChild(roof)
    }

    private static func addInfieldMarkings(
        _ venue: ReplayBikeVenuePlan,
        quality: ReplayRenderQuality,
        theme: ReplayEnvironmentTheme,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        let markings = Entity()
        markings.name = "velodrome-infield-markings"
        let lineMaterial = ReplayEnvironmentGeometry.simple(
            ReplayThemedColor(0xE6E2D8, 0x7F918E),
            theme: theme,
            roughness: 0.8
        )
        let halfCourt = ModelEntity(
            mesh: .generateBox(size: SIMD3(
                0.12,
                0.025,
                mapping.extent(venue.infieldRadius * 1.4)
            )),
            materials: [lineMaterial]
        )
        halfCourt.name = "velodrome-infield-half-court"
        halfCourt.position.y = 0.006
        markings.addChild(halfCourt)

        if quality != .low {
            let stagingMaterial = ReplayEnvironmentGeometry.simple(
                ReplayThemedColor(0x77847F, 0x35423E),
                theme: theme,
                roughness: 0.8
            )
            let serviceAngle = 249 * Double.pi / 180
            for (index, offset) in [-3.2, 0, 3.2].enumerated() {
                let pad = ModelEntity(
                    mesh: .generateBox(size: SIMD3(2.4, 0.04, 3.6)),
                    materials: [stagingMaterial]
                )
                pad.name = "velodrome-staging-pad-\(index + 1)"
                let radius = mapping.radius(venue.trackOuterRadius - 8)
                pad.position = SIMD3(
                    radius * Float(sin(serviceAngle)) + Float(cos(serviceAngle) * offset),
                    0.02,
                    radius * Float(cos(serviceAngle)) - Float(sin(serviceAngle) * offset)
                )
                pad.orientation = simd_quatf(
                    angle: Float(serviceAngle),
                    axis: SIMD3(0, 1, 0)
                )
                markings.addChild(pad)
            }
        }
        root.addChild(markings)
    }

    private static func addTeamPit(
        _ venue: ReplayBikeVenuePlan,
        theme: ReplayEnvironmentTheme,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        let pit = Entity()
        pit.name = "velodrome-team-pit"
        let angle = 248 * Double.pi / 180
        pit.position = mapping.position(angleRadians: angle, authoredRadius: 25.5, y: 0.02)
        pit.orientation = simd_quatf(angle: Float(angle), axis: SIMD3(0, 1, 0))
        let bayMaterial = ReplayEnvironmentGeometry.simple(
            venue.wallColor,
            theme: theme,
            roughness: 0.78
        )
        for (index, x) in [-4.2, 0, 4.2].enumerated() {
            let bay = ModelEntity(
                mesh: .generateBox(size: SIMD3(3.6, 1.15, 3.1)),
                materials: [bayMaterial]
            )
            bay.name = "velodrome-team-pit-bay-\(index + 1)"
            bay.position = SIMD3(Float(x), 0.58, 0)
            pit.addChild(bay)
        }
        let canopy = ModelEntity(
            mesh: .generateBox(size: SIMD3(13.4, 0.28, 4.2)),
            materials: [ReplayEnvironmentGeometry.simple(
                venue.accentColor,
                theme: theme,
                roughness: 0.55
            )]
        )
        canopy.name = "velodrome-team-pit-canopy"
        canopy.position.y = 2.05
        pit.addChild(canopy)
        root.addChild(pit)
    }

    private static func addLine(
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

    private static func addTrackAnnulus(
        _ venue: ReplayBikeVenuePlan,
        segmentCount: Int,
        material: PhysicallyBasedMaterial,
        mapping: ReplayEnvironmentPlanarMapping,
        to root: Entity
    ) {
        guard segmentCount > 0, venue.trackOuterRadius > venue.trackInnerRadius else {
            return
        }
        let group = Entity()
        group.name = "velodrome-track"
        let centerRadius = mapping.radius(
            (venue.trackInnerRadius + venue.trackOuterRadius) / 2
        )
        let outerRadius = mapping.radius(venue.trackOuterRadius)
        let radialWidth = mapping.extent(
            venue.trackOuterRadius - venue.trackInnerRadius
        )
        let segmentLength = (2 * Float.pi * outerRadius / Float(segmentCount)) * 1.02
        let mesh = MeshResource.generateBox(
            size: SIMD3(segmentLength, Float(venue.trackHeight), radialWidth)
        )
        for index in 0..<segmentCount {
            let angle = Float(index) / Float(segmentCount) * .pi * 2
            let segment = ModelEntity(mesh: mesh, materials: [material])
            segment.name = "velodrome-track-segment-\(index)"
            segment.position = SIMD3(
                centerRadius * sin(angle),
                Float(venue.trackCenterY),
                centerRadius * cos(angle)
            )
            segment.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
            group.addChild(segment)
        }
        root.addChild(group)
    }

    private static func addSprintMarkers(
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
}
