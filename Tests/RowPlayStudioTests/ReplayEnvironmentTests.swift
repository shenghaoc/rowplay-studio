import Foundation
import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayEnvironmentTests: XCTestCase {
    func testEverySportAndQualityBuildsAnAtomicNamedVenue() {
        for sport in Sport.allCases {
            var previousDressingCount = -1
            for quality in ReplayRenderQuality.allCases {
                let venue = ReplayEnvironmentInstaller.install(
                    sport: sport,
                    quality: quality,
                    colorScheme: .dark
                )
                XCTAssertNotNil(venue, "Missing \(sport) \(quality) venue")
                XCTAssertEqual(venue?.name, "premium-environment-\(sport.rawValue)-\(quality.rawValue)")
                XCTAssertNotNil(venue?.findEntity(named: "venue-ground"))

                let dressing = venue?.findEntity(named: "venue-dressing-level-\(quality.environmentDetail)")
                XCTAssertNotNil(dressing)
                let count = dressing?.children.count ?? 0
                XCTAssertGreaterThan(count, previousDressingCount)
                previousDressingCount = count
            }
        }
    }

    func testSportsExposeTheirDefiningVenueLandmarks() {
        let rower = ReplayEnvironmentInstaller.install(sport: .rower, quality: .high, colorScheme: .light)
        XCTAssertNotNil(rower?.findEntity(named: "regatta-basin"))
        XCTAssertNotNil(rower?.findEntity(named: "island-park"))
        XCTAssertNotNil(rower?.findEntity(named: "buoy-0-0"))

        let ski = ReplayEnvironmentInstaller.install(sport: .skierg, quality: .high, colorScheme: .light)
        XCTAssertNotNil(ski?.findEntity(named: "nordic-stadium-field"))
        XCTAssertNotNil(ski?.findEntity(named: "nordic-pine-0"))

        let bike = ReplayEnvironmentInstaller.install(sport: .bike, quality: .high, colorScheme: .light)
        XCTAssertNotNil(bike?.findEntity(named: "velodrome-track"))
        XCTAssertNotNil(bike?.findEntity(named: "velodrome-infield"))
        XCTAssertNotNil(bike?.findEntity(named: "velodrome-scoreboard"))
    }

    func testQualityProfilesRemainDistinctAndMonotonic() {
        let profiles = ReplayRenderQuality.allCases.map(ReplayQualitySceneProfile.profile)
        XCTAssertEqual(profiles.map(\.environmentDetail), [0, 1, 2, 3])
        XCTAssertEqual(profiles.map(\.buoysPerRing), [12, 18, 22, 28])
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
        for quality in [ReplayRenderQuality.high, .ultra] {
            for (sport, name) in texturedRoles {
                let venue = try XCTUnwrap(ReplayEnvironmentInstaller.install(
                    sport: sport,
                    quality: quality,
                    colorScheme: .dark
                ))
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

        let rower = try XCTUnwrap(ReplayEnvironmentInstaller.install(
            sport: .rower,
            quality: .ultra,
            colorScheme: .dark
        ))
        let water = try primaryMaterial(named: "regatta-basin", in: rower)
        XCTAssertNil(water.baseColor.texture, "Water intentionally uses scalar PBR")
    }

    func testDefiningSportSurfaceBracketsLiveCourseAfterInstallation() throws {
        let definingSurface: [Sport: String] = [
            .rower: "regatta-basin",
            .skierg: "nordic-stadium-field",
            .bike: "velodrome-track",
        ]
        for sport in Sport.allCases {
            let scene = Replay3DSceneBuilder.buildScene(
                sport: sport,
                colorScheme: .dark,
                configuration: ReplayRenderQuality.high.configuration,
                effectiveQuality: .high,
                bundledAssetSet: nil
            )
            let environment = try XCTUnwrap(scene.bundledEnvironment)
            let expectedScale = Float(
                scene.layout.loopRadius
                    / ReplayEnvironmentPlan.plan(for: sport).course.loopRadius
            )
            XCTAssertEqual(environment.scale.x, expectedScale, accuracy: 1e-6)
            XCTAssertEqual(environment.scale.y, expectedScale, accuracy: 1e-6)
            XCTAssertEqual(environment.scale.z, expectedScale, accuracy: 1e-6)

            let name = try XCTUnwrap(definingSurface[sport])
            let surface = try XCTUnwrap(environment.findEntity(named: name))
            let bounds = surface.visualBounds(relativeTo: scene.root)
            for distance in stride(from: 0.0, through: ReplayCourseLayout.loopMeters, by: 50) {
                let point = scene.layout.position(at: distance)
                XCTAssertGreaterThanOrEqual(Float(point.x), bounds.min.x - 0.01)
                XCTAssertLessThanOrEqual(Float(point.x), bounds.max.x + 0.01)
                XCTAssertGreaterThanOrEqual(Float(point.z), bounds.min.z - 0.01)
                XCTAssertLessThanOrEqual(Float(point.z), bounds.max.z + 0.01)
            }
        }
    }

    func testSceneBuilderKeepsEnvironmentIndependentFromAthleteFallback() {
        let scene = Replay3DSceneBuilder.buildScene(
            sport: .rower,
            colorScheme: .dark,
            configuration: ReplayRenderQuality.low.configuration,
            effectiveQuality: .low,
            bundledAssetSet: nil
        )
        XCTAssertEqual(scene.visualSource, .procedural)
        XCTAssertNotNil(scene.bundledEnvironment)
        XCTAssertFalse(scene.groundEntity.isEnabled)
    }

    private func primaryMaterial(
        named name: String,
        in venue: Entity
    ) throws -> PhysicallyBasedMaterial {
        let entity = try XCTUnwrap(venue.findEntity(named: name))
        let model = try XCTUnwrap(entity.components[ModelComponent.self])
        return try XCTUnwrap(model.materials.first as? PhysicallyBasedMaterial)
    }
}

private enum TestTextureError: Error {
    case unexpectedLoad
}

private extension ReplayRenderQuality {
    var environmentDetail: Int {
        ReplayQualitySceneProfile.profile(for: self).environmentDetail
    }
}
