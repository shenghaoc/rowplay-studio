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
        XCTAssertEqual(profiles.map(\.laneSegments), [48, 80, 112, 160])
        XCTAssertEqual(profiles.map(\.shadowsEnabled), [false, false, true, true])
        XCTAssertEqual(profiles.map(\.wakeSegments), [0, 20, 32, 52])
        XCTAssertEqual(profiles.map(\.sprayParticles), [0, 64, 80, 112])
    }

    func testEveryProvenanceRecordedTextureTripletLoads() {
        let library = ReplayEnvironmentMaterialLibrary()
        for family in ReplayEnvironmentTextureFamily.allCases {
            for slot in [ReplayEnvironmentTextureSlot.diffuse, .roughness, .normal] {
                XCTAssertNotNil(library.texture(family: family, slot: slot), "Missing \(family.rawValue) \(slot.rawValue)")
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
}

private extension ReplayRenderQuality {
    var environmentDetail: Int {
        ReplayQualitySceneProfile.profile(for: self).environmentDetail
    }
}
