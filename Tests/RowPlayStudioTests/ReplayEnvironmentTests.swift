import Foundation
import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayEnvironmentTests: XCTestCase {
    func testEverySportAndQualityBuildsANamedVenueWithMonotonicDressing() {
        for sport in Sport.allCases {
            var previousDressingCount = -1
            for quality in ReplayRenderQuality.allCases {
                let venue = ReplayEnvironmentInstaller.install(
                    sport: sport,
                    quality: quality,
                    colorScheme: .dark
                )
                XCTAssertEqual(venue.name, "premium-environment-\(sport.rawValue)-\(quality.rawValue)")
                XCTAssertNotNil(venue.findEntity(named: "venue-ground"))

                let dressing = venue.findEntity(named: "venue-dressing-\(quality.rawValue)")
                XCTAssertNotNil(dressing)
                let count = dressing?.children.count ?? 0
                XCTAssertGreaterThan(count, previousDressingCount)
                previousDressingCount = count
            }
        }
    }

    func testSportsExposeTheirDefiningVenueLandmarks() {
        let rower = ReplayEnvironmentInstaller.install(sport: .rower, quality: .high, colorScheme: .light)
        XCTAssertNotNil(rower.findEntity(named: "regatta-basin"))
        XCTAssertNotNil(rower.findEntity(named: "island-park"))
        XCTAssertNotNil(rower.findEntity(named: "buoy-0-0"))
        XCTAssertNotNil(rower.findEntity(named: "regatta-pavilion"))

        let ski = ReplayEnvironmentInstaller.install(sport: .skierg, quality: .high, colorScheme: .light)
        XCTAssertNotNil(ski.findEntity(named: "nordic-stadium-field"))
        XCTAssertNotNil(ski.findEntity(named: "nordic-pine-0"))
        XCTAssertNotNil(ski.findEntity(named: "timing-lodge"))

        let bike = ReplayEnvironmentInstaller.install(sport: .bike, quality: .high, colorScheme: .light)
        XCTAssertNotNil(bike.findEntity(named: "velodrome-track"))
        XCTAssertNotNil(bike.findEntity(named: "velodrome-infield"))
        XCTAssertNotNil(bike.findEntity(named: "scoreboard"))
    }

    func testEnvironmentQualityUsesCoreBudgetsAndNamedPbrTiers() {
        XCTAssertEqual(
            ReplayRenderQuality.allCases.map { $0.configuration.buoysPerRing },
            [12, 18, 22, 28]
        )
        XCTAssertEqual(
            ReplayRenderQuality.allCases.map(ReplayEnvironmentMaterialLibrary.usesSurfaceMaps),
            [false, false, true, true]
        )
        XCTAssertEqual(
            ReplayRenderQuality.allCases.map(ReplayEnvironmentMaterialLibrary.usesNormalMap),
            [false, false, false, true]
        )
    }

    func testEveryProvenanceRecordedTextureTripletLoads() {
        let library = ReplayEnvironmentMaterialLibrary.shared
        for family in ReplayEnvironmentTextureFamily.allCases {
            for slot in [ReplayEnvironmentTextureSlot.diffuse, .roughness, .normal] {
                XCTAssertNotNil(library.texture(family: family, slot: slot), "Missing \(family.rawValue) \(slot.rawValue)")
            }
        }
    }

    func testTextureFailureIsReportedOnlyOncePerAppKey() {
        var reports: [(String, ReplayEnvironmentTextureFailure)] = []
        let library = ReplayEnvironmentMaterialLibrary(
            resourceResolver: { _, _ in nil },
            textureLoader: { _, _ in throw TestTextureError.unexpectedLoad },
            failureReporter: { key, failure in reports.append((key, failure)) }
        )

        XCTAssertNil(library.texture(family: .snow02, slot: .diffuse))
        XCTAssertNil(library.texture(family: .snow02, slot: .diffuse))
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.0, "snow-02/diffuse")
        XCTAssertEqual(reports.first?.1, .missingResource)
    }

    func testTextureDecodeFailureIsReportedOnlyOncePerAppKey() {
        var reports: [(String, ReplayEnvironmentTextureFailure)] = []
        let library = ReplayEnvironmentMaterialLibrary(
            resourceResolver: { _, _ in URL(fileURLWithPath: "/private/tmp/invalid-texture.jpg") },
            textureLoader: { _, _ in throw TestTextureError.unexpectedLoad },
            failureReporter: { key, failure in reports.append((key, failure)) }
        )

        XCTAssertNil(library.texture(family: .woodFloor, slot: .normal))
        XCTAssertNil(library.texture(family: .woodFloor, slot: .normal))
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.0, "wood-floor/normal")
        XCTAssertEqual(reports.first?.1, .loadFailed)
    }

    func testPrimaryVenueSurfacesUseTieredPBRMaterials() throws {
        let texturedRoles: [(Sport, String)] = [
            (.rower, "island-park"),
            (.skierg, "nordic-stadium-field"),
            (.bike, "velodrome-track"),
            (.bike, "velodrome-infield"),
        ]
        for quality in [ReplayRenderQuality.low, .medium] {
            for (sport, name) in texturedRoles {
                let venue = ReplayEnvironmentInstaller.install(
                    sport: sport,
                    quality: quality,
                    colorScheme: .dark
                )
                let material = try primaryMaterial(named: name, in: venue)
                XCTAssertNil(material.baseColor.texture, "\(quality) must keep \(name) scalar")
                XCTAssertNil(material.roughness.texture, "\(quality) must keep \(name) scalar")
                XCTAssertNil(material.normal.texture, "\(quality) must keep \(name) scalar")
            }
        }
        for quality in [ReplayRenderQuality.high, .ultra] {
            for (sport, name) in texturedRoles {
                let venue = ReplayEnvironmentInstaller.install(
                    sport: sport,
                    quality: quality,
                    colorScheme: .dark
                )
                let material = try primaryMaterial(named: name, in: venue)
                XCTAssertNotNil(material.baseColor.texture, "Missing \(name) diffuse")
                XCTAssertNotNil(material.roughness.texture, "Missing \(name) roughness")
                if quality == .ultra {
                    XCTAssertNotNil(material.normal.texture, "Missing \(name) normal")
                } else {
                    XCTAssertNil(material.normal.texture, "High must not bind \(name) normal")
                }
            }
        }

        let rower = ReplayEnvironmentInstaller.install(
            sport: .rower,
            quality: .ultra,
            colorScheme: .dark
        )
        let water = try primaryMaterial(named: "regatta-basin", in: rower)
        XCTAssertNil(water.baseColor.texture, "Water intentionally uses scalar PBR")
    }

    func testDefiningSportSurfaceBracketsLiveCourseAfterInstallation() throws {
        let definingSurface: [Sport: String] = [
            .rower: "regatta-basin",
            .skierg: "nordic-stadium-field",
            .bike: "velodrome-track",
        ]
        let authoredSurfaceRadius: [Sport: Double] = [
            .rower: 38,
            .skierg: 33,
            .bike: 34,
        ]
        for sport in Sport.allCases {
            let scene = Replay3DSceneBuilder.buildScene(
                sport: sport,
                colorScheme: .dark,
                configuration: ReplayRenderQuality.high.configuration,
                effectiveQuality: .high,
                bundledAssetSet: nil
            )
            let environment = scene.bundledEnvironment
            XCTAssertEqual(environment.scale, SIMD3(repeating: 1))

            let name = try XCTUnwrap(definingSurface[sport])
            let surface = try XCTUnwrap(environment.findEntity(named: name))
            let bounds = surface.visualBounds(relativeTo: scene.root)
            let installedRadius = ReplayEnvironmentPlanarMapping(layout: scene.layout).radius(
                try XCTUnwrap(authoredSurfaceRadius[sport])
            )
            for distance in stride(from: 0.0, through: ReplayCourseLayout.loopMeters, by: 50) {
                let point = scene.layout.position(at: distance)
                XCTAssertLessThanOrEqual(
                    Float(hypot(point.x, point.z)),
                    installedRadius + 0.01
                )
                XCTAssertGreaterThanOrEqual(Float(point.x), bounds.min.x - 0.01)
                XCTAssertLessThanOrEqual(Float(point.x), bounds.max.x + 0.01)
                XCTAssertGreaterThanOrEqual(Float(point.z), bounds.min.z - 0.01)
                XCTAssertLessThanOrEqual(Float(point.z), bounds.max.z + 0.01)
            }
        }
    }

    func testSceneBuilderKeepsEnvironmentIndependentFromAthleteSource() {
        let scene = Replay3DSceneBuilder.buildScene(
            sport: .rower,
            colorScheme: .dark,
            configuration: ReplayRenderQuality.low.configuration,
            effectiveQuality: .low,
            bundledAssetSet: nil
        )
        XCTAssertEqual(scene.visualSource, .procedural)
        XCTAssertEqual(scene.bundledEnvironment.scale, SIMD3(repeating: 1))
        XCTAssertFalse(scene.groundEntity.isEnabled)
    }

    func testPlanarMappingMapsRadiiPositionsAndLargeExtentsButNotHeight() {
        let layout = ReplayCourseLayout.standard
        let mapping = ReplayEnvironmentPlanarMapping(layout: layout)

        XCTAssertEqual(
            mapping.scale,
            layout.loopRadius / ReplayEnvironmentPlan.authoredLoopRadius,
            accuracy: 1e-12
        )
        XCTAssertEqual(mapping.radius(ReplayEnvironmentPlan.authoredLoopRadius), Float(layout.loopRadius))
        XCTAssertEqual(mapping.extent(10), Float(10 * mapping.scale), accuracy: 1e-6)

        let position = mapping.position(
            angleRadians: .pi / 2,
            authoredRadius: ReplayEnvironmentPlan.authoredLoopRadius,
            y: 2.2
        )
        XCTAssertEqual(position.x, Float(layout.loopRadius), accuracy: 1e-5)
        XCTAssertEqual(position.y, 2.2, accuracy: 1e-6)
        XCTAssertEqual(position.z, 0, accuracy: 1e-5)
    }

    func testEnvironmentRootScaleIsIdentityForEverySportAndQuality() {
        for sport in Sport.allCases {
            for quality in ReplayRenderQuality.allCases {
                let environment = ReplayEnvironmentInstaller.install(
                    sport: sport,
                    quality: quality,
                    colorScheme: .dark
                )
                XCTAssertEqual(environment.scale, SIMD3(repeating: 1), "\(sport) \(quality)")
            }
        }
    }

    func testPlanarPlacementPreservesMetreScaleWallTreeAndLandmarkGeometry() throws {
        let layout = ReplayCourseLayout.standard
        let mapping = ReplayEnvironmentPlanarMapping(layout: layout)

        let bike = ReplayEnvironmentInstaller.install(
            sport: .bike,
            quality: .high,
            colorScheme: .dark,
            layout: layout
        )
        let wall = try XCTUnwrap(bike.findEntity(named: "arena-wall-0"))
        assertLocalSize(wall, equals: SIMD3(5.5, 6.2, 0.4))
        XCTAssertEqual(wall.position.y, 3.1, accuracy: 1e-6)
        XCTAssertEqual(horizontalRadius(wall.position), mapping.radius(61.5), accuracy: 1e-4)

        let ski = ReplayEnvironmentInstaller.install(
            sport: .skierg,
            quality: .high,
            colorScheme: .dark,
            layout: layout
        )
        let tree = try XCTUnwrap(ski.findEntity(named: "nordic-pine-0"))
        assertLocalSize(tree, equals: SIMD3(0.45, 2.2, 0.45))
        XCTAssertEqual(tree.position.y, 1.1, accuracy: 1e-6)
        XCTAssertEqual(horizontalRadius(tree.position), mapping.radius(74), accuracy: 1e-4)

        let rower = ReplayEnvironmentInstaller.install(
            sport: .rower,
            quality: .high,
            colorScheme: .dark,
            layout: layout
        )
        let tower = try XCTUnwrap(rower.findEntity(named: "timing-tower"))
        assertLocalSize(tower, equals: SIMD3(0.5, 1.26, 0.56))
        XCTAssertEqual(tower.position.y, 0.63, accuracy: 1e-6)
        XCTAssertEqual(horizontalRadius(tower.position), mapping.radius(70), accuracy: 1e-4)
    }

    func testRuntimeUsesExactCoreBuoyWallAndLineBudgets() throws {
        let wallCounts = ReplayQualityValues(16, 24, 32, 40)
        for quality in ReplayRenderQuality.allCases {
            let rower = ReplayEnvironmentInstaller.install(
                sport: .rower,
                quality: quality,
                colorScheme: .light
            )
            for ring in 0..<2 {
                let buoyCount = descendants(in: rower) {
                    $0.name.hasPrefix("buoy-\(ring)-")
                }.count
                XCTAssertEqual(buoyCount, quality.configuration.buoysPerRing, "\(quality)")
            }

            let bike = ReplayEnvironmentInstaller.install(
                sport: .bike,
                quality: quality,
                colorScheme: .light
            )
            let track = try XCTUnwrap(bike.findEntity(named: "velodrome-track"))
            XCTAssertEqual(
                track.children.count,
                quality.configuration.courseRingSegmentCount,
                "\(quality) timber annulus"
            )
            XCTAssertEqual(
                descendants(in: bike) { $0.name.hasPrefix("arena-wall-") }.count,
                wallCounts[quality],
                "\(quality)"
            )
            for line in ["cote-d-azur", "measurement-black", "pursuit-blue", "sprinter-red"] {
                let ring = try XCTUnwrap(bike.findEntity(named: "bike-line-\(line)"))
                XCTAssertEqual(
                    ring.children.count,
                    quality.configuration.courseRingSegmentCount,
                    "\(quality) \(line)"
                )
            }
            let sprintMarkers = try XCTUnwrap(bike.findEntity(named: "bike-sprint-markers"))
            XCTAssertEqual(sprintMarkers.children.count, 8)
            XCTAssertNil(bike.findEntity(named: "bike-line-sprint-marker-red"))
        }
    }

    func testBikeLineGrammarUsesAuthoredMappedRadiiWidthsAndColors() throws {
        let plan = ReplayEnvironmentPlan.plan(for: .bike)
        guard case let .bike(venue) = plan.venue else {
            return XCTFail("Bike plan has the wrong venue payload")
        }
        XCTAssertEqual(
            venue.lines.map(\.name),
            [
                "cote-d-azur",
                "measurement-black",
                "pursuit-blue",
                "sprinter-red",
            ]
        )
        XCTAssertEqual(venue.lines.map(\.radius), [22.32, 22.72, 28, 33.2])
        XCTAssertEqual(venue.lines.map(\.radialWidth), [0.52, 0.052, 0.056, 0.052])
        XCTAssertEqual(venue.lines.map(\.centerY), [0.052, 0.063, 0.064, 0.063])
        XCTAssertEqual(
            venue.lines.map { $0.color.hex(for: .light) },
            [0x7DB6CC, 0x725F4D, 0x2F7298, 0xC63F38]
        )
        XCTAssertEqual(venue.sprintMarkers.anglesDegrees, [-6, -2, 2, 6, 174, 178, 182, 186])

        let mapping = ReplayEnvironmentPlanarMapping(layout: .standard)
        let environment = ReplayEnvironmentInstaller.install(
            sport: .bike,
            quality: .high,
            colorScheme: .light
        )
        for line in venue.lines {
            let group = try XCTUnwrap(environment.findEntity(named: "bike-line-\(line.name)"))
            let first = try XCTUnwrap(group.children.first)
            XCTAssertEqual(
                horizontalRadius(first.position),
                mapping.radius(line.radius),
                accuracy: 1e-4,
                line.name
            )
            let bounds = first.visualBounds(relativeTo: first)
            XCTAssertEqual(
                bounds.max.z - bounds.min.z,
                mapping.extent(line.radialWidth),
                accuracy: 1e-4,
                line.name
            )
            XCTAssertEqual(bounds.max.y - bounds.min.y, Float(line.height), accuracy: 1e-4)
            XCTAssertEqual(first.position.y, Float(line.centerY), accuracy: 1e-6)
        }

        let markerGroup = try XCTUnwrap(environment.findEntity(named: "bike-sprint-markers"))
        XCTAssertEqual(markerGroup.children.count, venue.sprintMarkers.anglesDegrees.count)
        for (index, angleDegrees) in venue.sprintMarkers.anglesDegrees.enumerated() {
            let marker = try XCTUnwrap(
                environment.findEntity(named: "sprint-marker-red-\(index)")
            )
            let expected = mapping.position(
                angleRadians: angleDegrees * .pi / 180,
                authoredRadius: venue.sprintMarkers.radius,
                y: venue.sprintMarkers.centerY
            )
            XCTAssertEqual(marker.position.x, expected.x, accuracy: 1e-4)
            XCTAssertEqual(marker.position.y, expected.y, accuracy: 1e-6)
            XCTAssertEqual(marker.position.z, expected.z, accuracy: 1e-4)
        }
    }

    func testBikeAnnulusKeepsInfieldBelowTrackCourseAndPaintGrammar() throws {
        let scene = Replay3DSceneBuilder.buildScene(
            sport: .bike,
            colorScheme: .light,
            configuration: ReplayRenderQuality.high.configuration,
            effectiveQuality: .high,
            bundledAssetSet: nil
        )
        let environment = scene.bundledEnvironment
        let mapping = ReplayEnvironmentPlanarMapping(layout: scene.layout)
        let plan = ReplayEnvironmentPlan.plan(for: .bike)
        guard case let .bike(venue) = plan.venue else {
            return XCTFail("Bike plan has the wrong venue payload")
        }

        let trackSegment = try XCTUnwrap(
            environment.findEntity(named: "velodrome-track-segment-0")
        )
        let trackLocalBounds = trackSegment.visualBounds(relativeTo: trackSegment)
        let trackCenterRadius = horizontalRadius(trackSegment.position)
        let trackHalfWidth = (trackLocalBounds.max.z - trackLocalBounds.min.z) / 2
        let trackInnerRadius = trackCenterRadius - trackHalfWidth
        let trackOuterRadius = trackCenterRadius + trackHalfWidth
        XCTAssertEqual(trackInnerRadius, mapping.radius(venue.trackInnerRadius), accuracy: 1e-4)
        XCTAssertEqual(trackOuterRadius, mapping.radius(venue.trackOuterRadius), accuracy: 1e-4)

        let courseSegment = try XCTUnwrap(scene.course.findEntity(named: "lane-ring-segment-0"))
        let courseLocalBounds = courseSegment.visualBounds(relativeTo: courseSegment)
        let courseHalfWidth = (courseLocalBounds.max.z - courseLocalBounds.min.z) / 2
        let courseRadius = horizontalRadius(courseSegment.position)
        XCTAssertGreaterThan(courseRadius - courseHalfWidth, trackInnerRadius)
        XCTAssertLessThan(courseRadius + courseHalfWidth, trackOuterRadius)

        let infield = try XCTUnwrap(environment.findEntity(named: "velodrome-infield"))
        let infieldLocalBounds = infield.visualBounds(relativeTo: infield)
        XCTAssertEqual(
            (infieldLocalBounds.max.x - infieldLocalBounds.min.x) / 2,
            mapping.radius(venue.infieldRadius),
            accuracy: 1e-4
        )
        XCTAssertGreaterThan(mapping.radius(venue.infieldRadius), courseRadius + courseHalfWidth)

        let startCell = try XCTUnwrap(scene.course.findEntity(named: "start-finish-marker")?.children.first)
        let coteSegment = try XCTUnwrap(
            environment.findEntity(named: "bike-line-cote-d-azur")?.children.first
        )
        let infieldTop = infield.visualBounds(relativeTo: scene.root).max.y
        let trackBottom = trackSegment.visualBounds(relativeTo: scene.root).min.y
        let trackTop = trackSegment.visualBounds(relativeTo: scene.root).max.y
        let courseTop = courseSegment.visualBounds(relativeTo: scene.root).max.y
        let startTop = startCell.visualBounds(relativeTo: scene.root).max.y
        let coteBottom = coteSegment.visualBounds(relativeTo: scene.root).min.y
        XCTAssertEqual(infieldTop, -0.015, accuracy: 1e-5)
        XCTAssertLessThan(infieldTop, trackBottom)
        XCTAssertLessThan(trackTop, courseTop)
        XCTAssertLessThan(trackTop, startTop)
        XCTAssertLessThan(trackTop, coteBottom)
    }

    func testSportAndThemePlansDriveSceneSunAndFill() {
        var sunIntensities: Set<Float> = []
        var sunOffsets: Set<SIMD3<Float>> = []
        for sport in Sport.allCases {
            let plan = ReplayEnvironmentPlan.plan(for: sport)
            sunIntensities.insert(plan.lighting.sunIntensity)
            sunOffsets.insert(plan.lighting.sunOffset)
            for (scheme, theme) in [
                (ColorScheme.light, ReplayEnvironmentTheme.light),
                (.dark, .dark),
            ] {
                let scene = Replay3DSceneBuilder.buildScene(
                    sport: sport,
                    colorScheme: scheme,
                    configuration: ReplayRenderQuality.high.configuration,
                    effectiveQuality: .high,
                    bundledAssetSet: nil
                )
                assertColor(
                    scene.light.light.color,
                    equals: plan.lighting.sunColor.resolvedColor(for: theme)
                )
                XCTAssertEqual(scene.light.light.intensity, plan.lighting.sunIntensity)
                XCTAssertEqual(scene.light.position, plan.lighting.sunOffset)
                assertColor(
                    scene.fillLight.light.color,
                    equals: plan.lighting.fillColor.resolvedColor(for: theme)
                )
                XCTAssertEqual(scene.fillLight.light.intensity, plan.lighting.fillIntensity)
                XCTAssertEqual(scene.fillLight.position, plan.lighting.fillOffset)
            }
        }
        XCTAssertEqual(sunIntensities.count, Sport.allCases.count)
        XCTAssertEqual(sunOffsets.count, Sport.allCases.count)
    }

    func testTextureInventoryAndPrimaryRuntimeConsumersAreAccuratelyScoped() throws {
        XCTAssertEqual(ReplayEnvironmentTextureFamily.allCases.count, 13)
        XCTAssertEqual(
            ReplayEnvironmentPlan.primaryRuntimeTextureFamilies.map(\.rawValue),
            ["aerial-grass-rock", "snow-02", "brushed-concrete-2", "wood-floor"]
        )
        XCTAssertNil(ReplayEnvironmentPlan.plan(for: .rower).ground.family)
        XCTAssertEqual(
            ReplayEnvironmentPlan.plan(for: .skierg).ground.family,
            .snow02
        )
        XCTAssertEqual(
            ReplayEnvironmentPlan.plan(for: .bike).ground.family,
            .brushedConcrete2
        )

        let rower = ReplayEnvironmentInstaller.install(
            sport: .rower,
            quality: .ultra,
            colorScheme: .light
        )
        XCTAssertNil(try primaryMaterial(named: "venue-ground", in: rower).baseColor.texture)
        let bike = ReplayEnvironmentInstaller.install(
            sport: .bike,
            quality: .ultra,
            colorScheme: .light
        )
        XCTAssertNotNil(try primaryMaterial(named: "venue-ground", in: bike).baseColor.texture)
    }

    func testTextureTransformChangesOnlyWhenAtLeastOneMapBinds() {
        let missing = ReplayEnvironmentMaterialLibrary(
            resourceResolver: { _, _ in nil },
            textureLoader: { _, _ in throw TestTextureError.unexpectedLoad },
            failureReporter: { _, _ in }
        )
        let failed = missing.material(
            family: .snow02,
            baseColor: .white,
            roughness: 0.8,
            quality: .high,
            textureRepeat: SIMD2(7, 9)
        )
        XCTAssertEqual(failed.textureCoordinateTransform.scale, SIMD2(1, 1))

        let mapped = ReplayEnvironmentMaterialLibrary.shared.material(
            family: .snow02,
            baseColor: .white,
            roughness: 0.8,
            quality: .high,
            textureRepeat: SIMD2(7, 9)
        )
        XCTAssertEqual(mapped.textureCoordinateTransform.scale, SIMD2(7, 9))
    }

    private func primaryMaterial(
        named name: String,
        in venue: Entity
    ) throws -> PhysicallyBasedMaterial {
        let entity = try XCTUnwrap(venue.findEntity(named: name))
        let receiver = try XCTUnwrap(descendants(in: entity) {
            $0.components[ModelComponent.self] != nil
        }.first)
        let model = try XCTUnwrap(receiver.components[ModelComponent.self])
        return try XCTUnwrap(model.materials.first as? PhysicallyBasedMaterial)
    }

    private func assertLocalSize(
        _ entity: Entity,
        equals expected: SIMD3<Float>,
        accuracy: Float = 1e-4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bounds = entity.visualBounds(relativeTo: entity)
        let actual = bounds.max - bounds.min
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: accuracy, file: file, line: line)
    }

    private func horizontalRadius(_ position: SIMD3<Float>) -> Float {
        hypot(position.x, position.z)
    }

    private func assertColor(
        _ actual: NSColor,
        equals expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualRGB = actual.usingColorSpace(.deviceRGB) ?? actual
        let expectedRGB = expected.usingColorSpace(.deviceRGB) ?? expected
        XCTAssertEqual(actualRGB.redComponent, expectedRGB.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualRGB.greenComponent, expectedRGB.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualRGB.blueComponent, expectedRGB.blueComponent, accuracy: 0.001, file: file, line: line)
    }

    private func descendants(
        in root: Entity,
        matching predicate: (Entity) -> Bool
    ) -> [Entity] {
        var result = predicate(root) ? [root] : []
        for child in root.children {
            result.append(contentsOf: descendants(in: child, matching: predicate))
        }
        return result
    }
}

private enum TestTextureError: Error {
    case unexpectedLoad
}
