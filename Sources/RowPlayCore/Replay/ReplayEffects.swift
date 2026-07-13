import Foundation

/// Renderer-neutral point or vector used by replay effects.
public struct ReplayEffectPoint: Equatable, Sendable {
    public internal(set) var x: Double
    public internal(set) var y: Double
    public internal(set) var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x.isFinite ? x : 0
        self.y = y.isFinite ? y : 0
        self.z = z.isFinite ? z : 0
    }

    fileprivate var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

/// Fixed Phase 8C effect budget and sport behavior.
public struct ReplayEffectProfile: Equatable, Sendable {
    public static let wakeCapacity = 24
    public static let sprayCapacity = 48
    public static let sprayPerCatchPerSide = 4

    public let sport: Sport
    public let wakeEnabled: Bool
    public let sprayEnabled: Bool
    public let sprayOffset: Double?
    public let wakeCapacity: Int
    public let sprayCapacity: Int
    public let sprayPerCatchPerSide: Int

    public static func forSport(_ sport: Sport) -> ReplayEffectProfile {
        switch sport {
        case .rower:
            ReplayEffectProfile(sport: sport, wakeEnabled: true, sprayEnabled: true, sprayOffset: 2.2)
        case .skierg:
            ReplayEffectProfile(sport: sport, wakeEnabled: true, sprayEnabled: true, sprayOffset: 0.4)
        case .bike:
            ReplayEffectProfile(sport: sport, wakeEnabled: false, sprayEnabled: false, sprayOffset: nil)
        }
    }

    private init(sport: Sport, wakeEnabled: Bool, sprayEnabled: Bool, sprayOffset: Double?) {
        self.sport = sport
        self.wakeEnabled = wakeEnabled
        self.sprayEnabled = sprayEnabled
        self.sprayOffset = sprayOffset
        wakeCapacity = Self.wakeCapacity
        sprayCapacity = Self.sprayCapacity
        sprayPerCatchPerSide = Self.sprayPerCatchPerSide
    }
}

/// One droplet in a fixed-capacity particle pool.
public struct ReplayParticle: Equatable, Sendable {
    public internal(set) var position: ReplayEffectPoint
    public internal(set) var velocity: ReplayEffectPoint
    public internal(set) var lifeRemaining: Double
    public internal(set) var initialLife: Double
    public internal(set) var size: Double

    public init(
        position: ReplayEffectPoint,
        velocity: ReplayEffectPoint,
        life: Double,
        size: Double
    ) {
        self.position = position
        self.velocity = velocity
        let safeLife = life.isFinite ? max(0, life) : 0
        lifeRemaining = safeLife
        initialLife = safeLife
        self.size = size.isFinite ? max(0, size) : 0
    }

    fileprivate static let inactive = ReplayParticle(
        position: ReplayEffectPoint(x: 0, y: 0, z: 0),
        velocity: ReplayEffectPoint(x: 0, y: 0, z: 0),
        life: 0,
        size: 0
    )

    fileprivate var isValid: Bool {
        position.isFinite
            && velocity.isFinite
            && lifeRemaining.isFinite
            && lifeRemaining > 0
            && initialLife.isFinite
            && initialLife > 0
            && size.isFinite
            && size > 0
    }
}

/// Fixed-capacity particle storage. The backing array never grows after init.
public struct ReplayParticlePool: Equatable, Sendable {
    public let capacity: Int
    public private(set) var aliveCount: Int
    private var storage: [ReplayParticle]

    public init(capacity: Int = ReplayEffectProfile.sprayCapacity) {
        let safeCapacity = min(ReplayEffectProfile.sprayCapacity, max(0, capacity))
        self.capacity = safeCapacity
        aliveCount = 0
        storage = Array(repeating: .inactive, count: safeCapacity)
    }

    public static func == (lhs: ReplayParticlePool, rhs: ReplayParticlePool) -> Bool {
        guard lhs.capacity == rhs.capacity, lhs.aliveCount == rhs.aliveCount else {
            return false
        }
        for index in 0..<lhs.aliveCount where lhs.storage[index] != rhs.storage[index] {
            return false
        }
        return true
    }

    @discardableResult
    public mutating func spawn(_ particle: ReplayParticle) -> Bool {
        guard particle.isValid, aliveCount < capacity else {
            return false
        }
        storage[aliveCount] = particle
        aliveCount += 1
        return true
    }

    public func particle(at index: Int) -> ReplayParticle? {
        guard index >= 0, index < aliveCount else { return nil }
        return storage[index]
    }

    public func fade(at index: Int) -> Double {
        guard let particle = particle(at: index), particle.isValid else { return 0 }
        let fade = particle.lifeRemaining / particle.initialLife
        guard fade.isFinite else { return 0 }
        return min(1, max(0, fade))
    }

    public mutating func update(
        dt: Double,
        gravity: ReplayEffectPoint,
        reduceMotion: Bool = false
    ) {
        if reduceMotion {
            clear()
            return
        }
        guard dt.isFinite, dt > 0 else { return }
        let safeGravity = ReplayEffectPoint(x: gravity.x, y: gravity.y, z: gravity.z)
        var index = 0
        while index < aliveCount {
            guard storage[index].isValid else {
                removeParticle(at: index)
                continue
            }

            let lifeRemaining = storage[index].lifeRemaining - dt
            guard lifeRemaining.isFinite, lifeRemaining > 0 else {
                removeParticle(at: index)
                continue
            }

            let velocityX = storage[index].velocity.x + safeGravity.x * dt
            let velocityY = storage[index].velocity.y + safeGravity.y * dt
            let velocityZ = storage[index].velocity.z + safeGravity.z * dt
            let positionX = storage[index].position.x + velocityX * dt
            let positionY = storage[index].position.y + velocityY * dt
            let positionZ = storage[index].position.z + velocityZ * dt
            guard velocityX.isFinite,
                  velocityY.isFinite,
                  velocityZ.isFinite,
                  positionX.isFinite,
                  positionY.isFinite,
                  positionZ.isFinite else {
                removeParticle(at: index)
                continue
            }

            storage[index].lifeRemaining = lifeRemaining
            storage[index].velocity = ReplayEffectPoint(x: velocityX, y: velocityY, z: velocityZ)
            storage[index].position = ReplayEffectPoint(x: positionX, y: positionY, z: positionZ)
            index += 1
        }
    }

    public mutating func clear() {
        aliveCount = 0
    }

    private mutating func removeParticle(at index: Int) {
        aliveCount -= 1
        if index != aliveCount {
            storage[index] = storage[aliveCount]
        }
        storage[aliveCount] = .inactive
    }
}

/// Stable catch-spray generator that writes directly into a preallocated pool.
public enum ReplaySprayGenerator: Sendable {
    public static let defaultSeed: UInt64 = 0x524F_5750_4C41_5938

    @discardableResult
    public static func spawnCatch(
        into pool: inout ReplayParticlePool,
        profile: ReplayEffectProfile,
        origin: ReplayEffectPoint,
        tangent: ReplayEffectPoint,
        radial: ReplayEffectPoint,
        catchOrdinal: Int,
        reduceMotion: Bool = false,
        seed: UInt64 = defaultSeed
    ) -> Int {
        guard !reduceMotion,
              profile.sprayEnabled,
              let offset = profile.sprayOffset,
              offset.isFinite else {
            return 0
        }
        let safeOrigin = ReplayEffectPoint(x: origin.x, y: origin.y, z: origin.z)
        let direction = normalizedHorizontal(tangent, fallback: ReplayEffectPoint(x: 1, y: 0, z: 0))
        let outward = normalizedHorizontal(
            radial,
            fallback: ReplayEffectPoint(x: -direction.z, y: 0, z: direction.x)
        )
        var spawned = 0

        for sideIndex in 0..<2 {
            let side = sideIndex == 0 ? -1.0 : 1.0
            for droplet in 0..<profile.sprayPerCatchPerSide {
                let jitterX = (randomUnit(seed: seed, catchOrdinal: catchOrdinal, side: sideIndex, droplet: droplet, lane: 0) - 0.5) * 0.3
                let jitterZ = (randomUnit(seed: seed, catchOrdinal: catchOrdinal, side: sideIndex, droplet: droplet, lane: 1) - 0.5) * 0.3
                let outwardSpeed = 0.3 + randomUnit(seed: seed, catchOrdinal: catchOrdinal, side: sideIndex, droplet: droplet, lane: 2) * 0.5
                let trailingSpeed = 0.3 + randomUnit(seed: seed, catchOrdinal: catchOrdinal, side: sideIndex, droplet: droplet, lane: 3) * 0.5
                let verticalSpeed = 1.1 + randomUnit(seed: seed, catchOrdinal: catchOrdinal, side: sideIndex, droplet: droplet, lane: 4) * 1.2
                let life = 0.4 + randomUnit(seed: seed, catchOrdinal: catchOrdinal, side: sideIndex, droplet: droplet, lane: 5) * 0.3
                let size = 0.5 + randomUnit(seed: seed, catchOrdinal: catchOrdinal, side: sideIndex, droplet: droplet, lane: 6)

                let particle = ReplayParticle(
                    position: ReplayEffectPoint(
                        x: safeOrigin.x + outward.x * offset * side + jitterX,
                        y: safeOrigin.y + 0.12,
                        z: safeOrigin.z + outward.z * offset * side + jitterZ
                    ),
                    velocity: ReplayEffectPoint(
                        x: outward.x * side * outwardSpeed - direction.x * trailingSpeed,
                        y: verticalSpeed,
                        z: outward.z * side * outwardSpeed - direction.z * trailingSpeed
                    ),
                    life: life,
                    size: size
                )
                if pool.spawn(particle) {
                    spawned += 1
                }
            }
        }
        return spawned
    }

    private static func normalizedHorizontal(
        _ point: ReplayEffectPoint,
        fallback: ReplayEffectPoint
    ) -> ReplayEffectPoint {
        let length = hypot(point.x, point.z)
        guard length.isFinite, length > 0.000_001 else { return fallback }
        return ReplayEffectPoint(x: point.x / length, y: 0, z: point.z / length)
    }

    private static func randomUnit(
        seed: UInt64,
        catchOrdinal: Int,
        side: Int,
        droplet: Int,
        lane: Int
    ) -> Double {
        var value = seed
        value ^= UInt64(bitPattern: Int64(catchOrdinal)) &* 0x9E37_79B9_7F4A_7C15
        value ^= UInt64(side + 1) &* 0xBF58_476D_1CE4_E5B9
        value ^= UInt64(droplet + 1) &* 0x94D0_49BB_1331_11EB
        value ^= UInt64(lane + 1) &* 0xD6E8_FEB8_6659_FD93
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992.0
    }
}

public struct ReplayWakeEntry: Equatable, Sendable {
    public let position: ReplayEffectPoint
    public let tangent: ReplayEffectPoint

    public init(
        position: ReplayEffectPoint,
        tangent: ReplayEffectPoint = ReplayEffectPoint(x: 1, y: 0, z: 0)
    ) {
        self.position = ReplayEffectPoint(x: position.x, y: position.y, z: position.z)
        self.tangent = Self.normalizedHorizontal(tangent)
    }

    fileprivate static let inactive = ReplayWakeEntry(
        position: ReplayEffectPoint(x: 0, y: 0.02, z: 0)
    )

    private static func normalizedHorizontal(_ point: ReplayEffectPoint) -> ReplayEffectPoint {
        let safePoint = ReplayEffectPoint(x: point.x, y: 0, z: point.z)
        let length = hypot(safePoint.x, safePoint.z)
        guard length.isFinite, length > 0.000_001 else {
            return ReplayEffectPoint(x: 1, y: 0, z: 0)
        }
        return ReplayEffectPoint(x: safePoint.x / length, y: 0, z: safePoint.z / length)
    }
}

public enum ReplayWakeUpdateResult: Equatable, Sendable {
    case appended
    case preserved
    case cleared
}

/// Fixed-capacity recent-path history for foam and snow wake entities.
public struct ReplayWakeHistory: Equatable, Sendable {
    public let capacity: Int
    public private(set) var count: Int
    private var storage: [ReplayWakeEntry]

    public init(capacity: Int = ReplayEffectProfile.wakeCapacity) {
        let safeCapacity = min(ReplayEffectProfile.wakeCapacity, max(0, capacity))
        self.capacity = safeCapacity
        count = 0
        storage = Array(repeating: .inactive, count: safeCapacity)
    }

    public static func == (lhs: ReplayWakeHistory, rhs: ReplayWakeHistory) -> Bool {
        guard lhs.capacity == rhs.capacity, lhs.count == rhs.count else {
            return false
        }
        for index in 0..<lhs.count where lhs.storage[index] != rhs.storage[index] {
            return false
        }
        return true
    }

    public func entry(at index: Int) -> ReplayWakeEntry? {
        guard index >= 0, index < count else { return nil }
        return storage[index]
    }

    @discardableResult
    public mutating func update(
        position: ReplayEffectPoint,
        tangent: ReplayEffectPoint = ReplayEffectPoint(x: 1, y: 0, z: 0),
        distanceDelta: Double,
        reduceMotion: Bool = false
    ) -> ReplayWakeUpdateResult {
        if reduceMotion || !distanceDelta.isFinite || distanceDelta < 0 || distanceDelta > 30 {
            clear()
            return .cleared
        }
        guard distanceDelta > 0 else { return .preserved }
        guard capacity > 0 else { return .preserved }

        let lastIndex = min(count, capacity - 1)
        if lastIndex > 0 {
            for index in stride(from: lastIndex, through: 1, by: -1) {
                storage[index] = storage[index - 1]
            }
        }
        storage[0] = ReplayWakeEntry(position: position, tangent: tangent)
        if count < capacity {
            count += 1
        }
        return .appended
    }

    public func opacity(at index: Int) -> Double {
        guard index >= 0, index < count, capacity > 0 else { return 0 }
        let fraction = max(0, 1 - Double(index) / Double(capacity))
        return sqrt(fraction) * fraction * 0.45
    }

    public func scale(at index: Int) -> Double {
        guard index >= 0, index < count, capacity > 0 else { return 0 }
        let fraction = max(0, 1 - Double(index) / Double(capacity))
        return 0.55 + (1 - fraction) * 1.2
    }

    public mutating func clear() {
        count = 0
    }
}
