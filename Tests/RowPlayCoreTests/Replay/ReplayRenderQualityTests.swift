import XCTest
@testable import RowPlayCore

final class ReplayRenderQualityTests: XCTestCase {
    func testAllTierConfigurationsMatchRequiredBudgets() {
        let expected: [(ReplayRenderQuality, [Int])] = [
            (.low, [48, 24, 0, 0, 0, 30]),
            (.medium, [72, 48, 16, 40, 4, 60]),
            (.high, [96, 64, 28, 48, 4, 60]),
            (.ultra, [144, 96, 44, 72, 6, 60]),
        ]

        for (quality, values) in expected {
            let configuration = quality.configuration
            XCTAssertEqual(configuration.courseRingSegmentCount, values[0], "\(quality)")
            XCTAssertEqual(configuration.laneMarkerCount, values[1], "\(quality)")
            XCTAssertEqual(
                configuration.wakeEntryCapacityPerParticipant,
                values[2],
                "\(quality)"
            )
            XCTAssertEqual(configuration.sprayParticleCapacity, values[3], "\(quality)")
            XCTAssertEqual(
                configuration.sprayDropletsPerSidePerCatch,
                values[4],
                "\(quality)"
            )
            XCTAssertEqual(configuration.targetFrameRate, values[5], "\(quality)")
        }
    }

    func testMediumIsDefaultQuality() {
        XCTAssertEqual(ReplayRenderQuality.defaultQuality, .medium)
    }

    func testTierDegradationIsOneWayAndBounded() {
        XCTAssertEqual(ReplayRenderQuality.ultra.nextLowerQuality, .high)
        XCTAssertEqual(ReplayRenderQuality.high.nextLowerQuality, .medium)
        XCTAssertEqual(ReplayRenderQuality.medium.nextLowerQuality, .low)
        XCTAssertEqual(ReplayRenderQuality.low.nextLowerQuality, .low)

        XCTAssertEqual(ReplayRenderQuality.ultra.degraded(by: 0), .ultra)
        XCTAssertEqual(ReplayRenderQuality.ultra.degraded(by: 1), .high)
        XCTAssertEqual(ReplayRenderQuality.ultra.degraded(by: 2), .medium)
        XCTAssertEqual(ReplayRenderQuality.ultra.degraded(by: 3), .low)
        XCTAssertEqual(ReplayRenderQuality.ultra.degraded(by: .max), .low)
        XCTAssertEqual(ReplayRenderQuality.high.degraded(by: 2), .low)
        XCTAssertEqual(ReplayRenderQuality.medium.degraded(by: 1), .low)
        XCTAssertEqual(ReplayRenderQuality.low.degraded(by: 100), .low)
        XCTAssertEqual(ReplayRenderQuality.medium.degraded(by: -1), .medium)
    }

    func testMaximumDegradationLevelsMatchAvailableLowerTiers() {
        XCTAssertEqual(ReplayRenderQuality.low.maximumDegradationLevel, 0)
        XCTAssertEqual(ReplayRenderQuality.medium.maximumDegradationLevel, 1)
        XCTAssertEqual(ReplayRenderQuality.high.maximumDegradationLevel, 2)
        XCTAssertEqual(ReplayRenderQuality.ultra.maximumDegradationLevel, 3)
    }

    func testEffectCapacitiesRejectNegativeAndUnboundedRequests() {
        XCTAssertEqual(ReplayParticlePool(capacity: -1).capacity, 0)
        XCTAssertEqual(ReplayWakeHistory(capacity: .min).capacity, 0)
        XCTAssertEqual(
            ReplayParticlePool(capacity: .max).capacity,
            ReplayRenderQuality.ultra.configuration.sprayParticleCapacity
        )
        XCTAssertEqual(
            ReplayWakeHistory(capacity: .max).capacity,
            ReplayRenderQuality.ultra.configuration.wakeEntryCapacityPerParticipant
        )
    }

    func testLowQualityUsesValidZeroCapacityEffectPools() {
        let profile = ReplayEffectProfile.forSport(
            .rower,
            configuration: ReplayRenderQuality.low.configuration
        )
        var particles = ReplayParticlePool(capacity: profile.sprayCapacity)
        var wake = ReplayWakeHistory(capacity: profile.wakeCapacity)

        XCTAssertFalse(profile.wakeEnabled)
        XCTAssertFalse(profile.sprayEnabled)
        XCTAssertEqual(particles.capacity, 0)
        XCTAssertEqual(wake.capacity, 0)
        XCTAssertFalse(particles.spawn(ReplayParticle(
            position: ReplayEffectPoint(x: 0, y: 0, z: 0),
            velocity: ReplayEffectPoint(x: 0, y: 1, z: 0),
            life: 1,
            size: 1
        )))
        particles.update(dt: 1.0 / 60.0, gravity: ReplayEffectPoint(x: 0, y: -5.5, z: 0))
        XCTAssertEqual(
            wake.update(
                position: ReplayEffectPoint(x: 1, y: 0, z: 0),
                distanceDelta: 1
            ),
            .preserved
        )
        XCTAssertEqual(particles.aliveCount, 0)
        XCTAssertEqual(wake.count, 0)
    }

    func testEffectCapableSportsUseEveryTierBudget() {
        for sport: Sport in [.rower, .skierg] {
            for quality in ReplayRenderQuality.allCases {
                let configuration = quality.configuration
                let profile = ReplayEffectProfile.forSport(
                    sport,
                    configuration: configuration
                )

                XCTAssertEqual(
                    profile.wakeCapacity,
                    configuration.wakeEntryCapacityPerParticipant,
                    "\(sport) \(quality)"
                )
                XCTAssertEqual(
                    profile.sprayCapacity,
                    configuration.sprayParticleCapacity,
                    "\(sport) \(quality)"
                )
                XCTAssertEqual(
                    profile.sprayPerCatchPerSide,
                    configuration.sprayDropletsPerSidePerCatch,
                    "\(sport) \(quality)"
                )
                XCTAssertEqual(profile.wakeEnabled, quality != .low, "\(sport) \(quality)")
                XCTAssertEqual(profile.sprayEnabled, quality != .low, "\(sport) \(quality)")
            }
        }
    }

    func testBikeErgDisablesEffectsAtEveryTierWhileRetainingTierCapacities() {
        for quality in ReplayRenderQuality.allCases {
            let configuration = quality.configuration
            let profile = ReplayEffectProfile.forSport(
                .bike,
                configuration: configuration
            )

            XCTAssertFalse(profile.wakeEnabled, "\(quality)")
            XCTAssertFalse(profile.sprayEnabled, "\(quality)")
            XCTAssertNil(profile.sprayOffset, "\(quality)")
            XCTAssertEqual(
                profile.wakeCapacity,
                configuration.wakeEntryCapacityPerParticipant,
                "\(quality)"
            )
            XCTAssertEqual(
                profile.sprayCapacity,
                configuration.sprayParticleCapacity,
                "\(quality)"
            )
            XCTAssertEqual(
                profile.sprayPerCatchPerSide,
                configuration.sprayDropletsPerSidePerCatch,
                "\(quality)"
            )
        }
    }
}
