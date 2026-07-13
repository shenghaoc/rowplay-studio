import XCTest
@testable import RowPlayCore

final class ReplayEffectsTests: XCTestCase {
    func testSportProfilesUseFixedPhaseLimits() {
        let rower = ReplayEffectProfile.forSport(.rower)
        let skierg = ReplayEffectProfile.forSport(.skierg)
        let bike = ReplayEffectProfile.forSport(.bike)

        XCTAssertTrue(rower.wakeEnabled)
        XCTAssertTrue(rower.sprayEnabled)
        XCTAssertEqual(rower.sprayOffset, 2.2)
        XCTAssertTrue(skierg.wakeEnabled)
        XCTAssertTrue(skierg.sprayEnabled)
        XCTAssertEqual(skierg.sprayOffset, 0.4)
        XCTAssertFalse(bike.wakeEnabled)
        XCTAssertFalse(bike.sprayEnabled)
        XCTAssertNil(bike.sprayOffset)

        for profile in [rower, skierg, bike] {
            XCTAssertEqual(profile.wakeCapacity, 24)
            XCTAssertEqual(profile.sprayCapacity, 48)
            XCTAssertEqual(profile.sprayPerCatchPerSide, 4)
        }
    }

    func testParticlePoolNeverExceedsCapacityAndDropsAdditionalSpawns() {
        var pool = ReplayParticlePool(capacity: 2)
        XCTAssertTrue(pool.spawn(particle(x: 1)))
        XCTAssertTrue(pool.spawn(particle(x: 2)))
        XCTAssertFalse(pool.spawn(particle(x: 3)))
        XCTAssertEqual(pool.aliveCount, 2)
        XCTAssertEqual(pool.particle(at: 0)?.position.x, 1)
        XCTAssertEqual(pool.particle(at: 1)?.position.x, 2)
    }

    func testEffectStorageClampsRequestedCapacityToPhaseBudget() {
        XCTAssertEqual(ReplayParticlePool(capacity: .max).capacity, ReplayEffectProfile.sprayCapacity)
        XCTAssertEqual(ReplayWakeHistory(capacity: .max).capacity, ReplayEffectProfile.wakeCapacity)
    }

    func testParticlePoolRejectsParticleMutatedToNonFiniteState() {
        var invalid = particle(x: 1)
        invalid.velocity.x = .nan
        var pool = ReplayParticlePool(capacity: 1)

        XCTAssertFalse(pool.spawn(invalid))
        XCTAssertEqual(pool.aliveCount, 0)
    }

    func testParticleIntegrationAppliesGravityVelocityAndFade() {
        var pool = ReplayParticlePool(capacity: 1)
        pool.spawn(ReplayParticle(
            position: ReplayEffectPoint(x: 0, y: 0, z: 0),
            velocity: ReplayEffectPoint(x: 2, y: 1, z: -2),
            life: 1,
            size: 1
        ))

        pool.update(dt: 0.5, gravity: ReplayEffectPoint(x: 0, y: -2, z: 0))

        let updated = try! XCTUnwrap(pool.particle(at: 0))
        XCTAssertEqual(updated.position.x, 1, accuracy: 1e-12)
        XCTAssertEqual(updated.position.y, 0, accuracy: 1e-12)
        XCTAssertEqual(updated.position.z, -1, accuracy: 1e-12)
        XCTAssertEqual(updated.velocity.y, 0, accuracy: 1e-12)
        XCTAssertEqual(updated.lifeRemaining, 0.5, accuracy: 1e-12)
        XCTAssertEqual(pool.fade(at: 0), 0.5, accuracy: 1e-12)
    }

    func testParticleExpiryUsesSwapRemoval() {
        var pool = ReplayParticlePool(capacity: 3)
        pool.spawn(particle(x: 1, life: 0.1))
        pool.spawn(particle(x: 2, life: 1))
        pool.spawn(particle(x: 3, life: 1))

        pool.update(dt: 0.2, gravity: ReplayEffectPoint(x: 0, y: 0, z: 0))

        XCTAssertEqual(pool.aliveCount, 2)
        XCTAssertEqual(pool.particle(at: 0)?.position.x, 3)
        XCTAssertEqual(pool.particle(at: 1)?.position.x, 2)
    }

    func testParticleIntegrationSanitizesMutatedGravity() {
        var pool = ReplayParticlePool(capacity: 1)
        pool.spawn(particle(x: 1))
        var gravity = ReplayEffectPoint(x: 0, y: 0, z: 0)
        gravity.y = .infinity

        pool.update(dt: 0.25, gravity: gravity)

        let updated = try! XCTUnwrap(pool.particle(at: 0))
        XCTAssertEqual(updated.velocity.y, 0)
        XCTAssertEqual(updated.position.y, 0)
    }

    func testParticleIntegrationDropsStateThatWouldOverflow() {
        var pool = ReplayParticlePool(capacity: 1)
        pool.spawn(ReplayParticle(
            position: ReplayEffectPoint(x: Double.greatestFiniteMagnitude, y: 0, z: 0),
            velocity: ReplayEffectPoint(x: Double.greatestFiniteMagnitude, y: 0, z: 0),
            life: Double.greatestFiniteMagnitude,
            size: 1
        ))

        pool.update(dt: 2, gravity: ReplayEffectPoint(x: 0, y: 0, z: 0))

        XCTAssertEqual(pool.aliveCount, 0)
    }

    func testParticleClearRemovesEveryLiveEntry() {
        var pool = ReplayParticlePool(capacity: 2)
        pool.spawn(particle(x: 1))
        pool.spawn(particle(x: 2))
        pool.clear()

        XCTAssertEqual(pool.aliveCount, 0)
        XCTAssertNil(pool.particle(at: 0))
        XCTAssertEqual(pool, ReplayParticlePool(capacity: 2))
    }

    func testParticlePoolEqualityIgnoresInactiveStorageAfterRepopulation() {
        var reused = ReplayParticlePool(capacity: 2)
        reused.spawn(particle(x: 99))
        reused.clear()
        reused.spawn(particle(x: 1))

        var fresh = ReplayParticlePool(capacity: 2)
        fresh.spawn(particle(x: 1))

        XCTAssertEqual(reused, fresh)
    }

    func testSprayGenerationIsDeterministic() {
        let profile = ReplayEffectProfile.forSport(.rower)
        var first = ReplayParticlePool()
        var second = ReplayParticlePool()

        let firstCount = spawnCatch(into: &first, profile: profile, ordinal: 7)
        let secondCount = spawnCatch(into: &second, profile: profile, ordinal: 7)

        XCTAssertEqual(firstCount, 8)
        XCTAssertEqual(secondCount, 8)
        XCTAssertEqual(first, second)
    }

    func testDifferentCatchOrdinalsProduceDifferentVariation() {
        let profile = ReplayEffectProfile.forSport(.skierg)
        var first = ReplayParticlePool()
        var second = ReplayParticlePool()
        spawnCatch(into: &first, profile: profile, ordinal: 1)
        spawnCatch(into: &second, profile: profile, ordinal: 2)

        XCTAssertNotEqual(first.particle(at: 0), second.particle(at: 0))
    }

    func testBikeErgNeverSpawnsSpray() {
        var pool = ReplayParticlePool()
        let count = spawnCatch(
            into: &pool,
            profile: ReplayEffectProfile.forSport(.bike),
            ordinal: 1
        )
        XCTAssertEqual(count, 0)
        XCTAssertEqual(pool.aliveCount, 0)
    }

    func testSprayValuesStayWithinWebDerivedRanges() {
        var pool = ReplayParticlePool()
        spawnCatch(
            into: &pool,
            profile: ReplayEffectProfile.forSport(.rower),
            ordinal: 9
        )

        XCTAssertEqual(pool.aliveCount, 8)
        for index in 0..<pool.aliveCount {
            let droplet = try! XCTUnwrap(pool.particle(at: index))
            XCTAssertGreaterThanOrEqual(droplet.velocity.y, 1.1)
            XCTAssertLessThanOrEqual(droplet.velocity.y, 2.3)
            XCTAssertGreaterThanOrEqual(droplet.initialLife, 0.4)
            XCTAssertLessThanOrEqual(droplet.initialLife, 0.7)
            XCTAssertGreaterThanOrEqual(droplet.size, 0.5)
            XCTAssertLessThanOrEqual(droplet.size, 1.5)
        }
    }

    func testWakeCapacityRemainsFixedAndKeepsNewestEntries() {
        var history = ReplayWakeHistory(capacity: 3)
        for index in 1...5 {
            history.update(
                position: ReplayEffectPoint(x: Double(index), y: 0, z: 0),
                distanceDelta: 1
            )
        }

        XCTAssertEqual(history.capacity, 3)
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.entry(at: 0)?.position.x, 5)
        XCTAssertEqual(history.entry(at: 1)?.position.x, 4)
        XCTAssertEqual(history.entry(at: 2)?.position.x, 3)
    }

    func testPausedMovementPreservesWake() {
        var history = ReplayWakeHistory()
        history.update(position: ReplayEffectPoint(x: 1, y: 0, z: 0), distanceDelta: 1)
        let before = history

        let result = history.update(
            position: ReplayEffectPoint(x: 99, y: 0, z: 0),
            distanceDelta: 0
        )

        XCTAssertEqual(result, .preserved)
        XCTAssertEqual(history, before)
    }

    func testWakeEqualityIgnoresInactiveStorageAfterClearAndRepopulation() {
        var reused = ReplayWakeHistory(capacity: 2)
        reused.update(position: ReplayEffectPoint(x: 99, y: 0, z: 0), distanceDelta: 1)
        reused.clear()
        XCTAssertEqual(reused, ReplayWakeHistory(capacity: 2))
        reused.update(position: ReplayEffectPoint(x: 1, y: 0, z: 0), distanceDelta: 1)

        var fresh = ReplayWakeHistory(capacity: 2)
        fresh.update(position: ReplayEffectPoint(x: 1, y: 0, z: 0), distanceDelta: 1)

        XCTAssertEqual(reused, fresh)
    }

    func testWakeEntrySanitizesMutatedPositionAndStoresNormalizedTangent() {
        var position = ReplayEffectPoint(x: 1, y: 2, z: 3)
        position.x = .nan
        var tangent = ReplayEffectPoint(x: 0, y: 4, z: 2)
        tangent.y = .infinity
        var history = ReplayWakeHistory(capacity: 1)

        history.update(position: position, tangent: tangent, distanceDelta: 1)

        let entry = try! XCTUnwrap(history.entry(at: 0))
        XCTAssertEqual(entry.position, ReplayEffectPoint(x: 0, y: 2, z: 3))
        XCTAssertEqual(entry.tangent, ReplayEffectPoint(x: 0, y: 0, z: 1))
    }

    func testBackwardSeekAndLargeJumpResetWake() {
        var history = populatedWake()
        XCTAssertEqual(
            history.update(position: ReplayEffectPoint(x: 0, y: 0, z: 0), distanceDelta: -0.1),
            .cleared
        )
        XCTAssertEqual(history.count, 0)

        history = populatedWake()
        XCTAssertEqual(
            history.update(position: ReplayEffectPoint(x: 0, y: 0, z: 0), distanceDelta: 30.01),
            .cleared
        )
        XCTAssertEqual(history.count, 0)

        history = populatedWake()
        XCTAssertEqual(
            history.update(position: ReplayEffectPoint(x: 0, y: 0, z: 0), distanceDelta: .nan),
            .cleared
        )
        XCTAssertEqual(history.count, 0)
    }

    func testReducedMotionClearsWakeAndParticles() {
        var history = populatedWake()
        var pool = ReplayParticlePool()
        pool.spawn(particle(x: 1))

        XCTAssertEqual(
            history.update(
                position: ReplayEffectPoint(x: 2, y: 0, z: 0),
                distanceDelta: 1,
                reduceMotion: true
            ),
            .cleared
        )
        pool.update(
            dt: 1.0 / 60.0,
            gravity: ReplayEffectPoint(x: 0, y: -5.5, z: 0),
            reduceMotion: true
        )

        XCTAssertEqual(history.count, 0)
        XCTAssertEqual(pool.aliveCount, 0)
    }

    func testReducedMotionSuppressesNewSpray() {
        var pool = ReplayParticlePool()
        let count = ReplaySprayGenerator.spawnCatch(
            into: &pool,
            profile: ReplayEffectProfile.forSport(.rower),
            origin: ReplayEffectPoint(x: 0, y: 0, z: 0),
            tangent: ReplayEffectPoint(x: 1, y: 0, z: 0),
            radial: ReplayEffectPoint(x: 0, y: 0, z: 1),
            catchOrdinal: 1,
            reduceMotion: true
        )

        XCTAssertEqual(count, 0)
        XCTAssertEqual(pool.aliveCount, 0)
    }

    func testWakeOpacityFadesAndScaleGrowsTowardTail() {
        var history = ReplayWakeHistory(capacity: 4)
        for index in 0..<4 {
            history.update(
                position: ReplayEffectPoint(x: Double(index), y: 0, z: 0),
                distanceDelta: 1
            )
        }

        XCTAssertGreaterThan(history.opacity(at: 0), history.opacity(at: 3))
        XCTAssertLessThan(history.scale(at: 0), history.scale(at: 3))
    }

    private func particle(x: Double, life: Double = 1) -> ReplayParticle {
        ReplayParticle(
            position: ReplayEffectPoint(x: x, y: 0, z: 0),
            velocity: ReplayEffectPoint(x: 0, y: 0, z: 0),
            life: life,
            size: 1
        )
    }

    @discardableResult
    private func spawnCatch(
        into pool: inout ReplayParticlePool,
        profile: ReplayEffectProfile,
        ordinal: Int
    ) -> Int {
        ReplaySprayGenerator.spawnCatch(
            into: &pool,
            profile: profile,
            origin: ReplayEffectPoint(x: 10, y: 0, z: 20),
            tangent: ReplayEffectPoint(x: 1, y: 0, z: 0),
            radial: ReplayEffectPoint(x: 0, y: 0, z: 1),
            catchOrdinal: ordinal
        )
    }

    private func populatedWake() -> ReplayWakeHistory {
        var history = ReplayWakeHistory()
        history.update(position: ReplayEffectPoint(x: 1, y: 0, z: 1), distanceDelta: 1)
        return history
    }
}
