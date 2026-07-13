import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// Bounded RealityKit adapter for renderer-neutral wake and spray simulation.
/// Every entity, mesh, and material is created in `init`; updates mutate only
/// the fixed Core pools and existing entity components/transforms.
@MainActor
final class ReplayEffectRenderer {
    static let liveWakeCapacity = ReplayEffectProfile.wakeCapacity
    static let ghostWakeCapacity = ReplayEffectProfile.wakeCapacity
    static let sprayCapacity = ReplayEffectProfile.sprayCapacity

    let root = Entity()
    let liveWakeEntities: [ModelEntity]
    let ghostWakeEntities: [ModelEntity]
    let sprayEntities: [ModelEntity]

    private let profile: ReplayEffectProfile
    private var liveWake = ReplayWakeHistory(capacity: ReplayEffectProfile.wakeCapacity)
    private var ghostWake = ReplayWakeHistory(capacity: ReplayEffectProfile.wakeCapacity)
    private var spray = ReplayParticlePool(capacity: ReplayEffectProfile.sprayCapacity)
    private var previousLiveDistance: Double?
    private var previousGhostDistance: Double?
    private var previousLivePhase: Double?
    private var appliedResetGeneration: Int?
    private var appliedPlaybackTickGeneration: UInt64?

    private static let gravity = ReplayEffectPoint(x: 0, y: -5.5, z: 0)

    init(sport: Sport, parent: Entity) {
        profile = ReplayEffectProfile.forSport(sport)
        root.name = "replay-effects"

        let wakeMesh = MeshResource.generateSphere(radius: 0.18)
        let wakeColor: NSColor = switch sport {
        case .rower:
            NSColor(calibratedWhite: 0.98, alpha: 1)
        case .skierg:
            NSColor(calibratedWhite: 1.0, alpha: 1)
        case .bike:
            NSColor(calibratedWhite: 0.9, alpha: 1)
        }
        let liveWakeMaterial = SimpleMaterial(
            color: wakeColor,
            roughness: 0.82,
            isMetallic: false
        )
        let ghostWakeMaterial = SimpleMaterial(
            color: NSColor(calibratedWhite: 0.94, alpha: 1),
            roughness: 0.86,
            isMetallic: false
        )
        let sprayMesh = MeshResource.generateSphere(radius: 0.045)
        let sprayMaterial = SimpleMaterial(
            color: NSColor(calibratedWhite: 1.0, alpha: 1),
            roughness: 0.72,
            isMetallic: false
        )

        liveWakeEntities = Self.makeEntities(
            count: Self.liveWakeCapacity,
            prefix: "live-wake",
            mesh: wakeMesh,
            material: liveWakeMaterial
        )
        ghostWakeEntities = Self.makeEntities(
            count: Self.ghostWakeCapacity,
            prefix: "ghost-wake",
            mesh: wakeMesh,
            material: ghostWakeMaterial
        )
        sprayEntities = Self.makeEntities(
            count: Self.sprayCapacity,
            prefix: "live-spray",
            mesh: sprayMesh,
            material: sprayMaterial
        )

        for entity in liveWakeEntities {
            root.addChild(entity)
        }
        for entity in ghostWakeEntities {
            root.addChild(entity)
        }
        for entity in sprayEntities {
            root.addChild(entity)
        }
        parent.addChild(root)
    }

    func update(
        layout: ReplayCourseLayout,
        liveDistance: Double,
        livePhase: Double,
        liveCatchOrdinal: Int,
        ghostDistance: Double,
        ghostVisible: Bool,
        deltaTime: TimeInterval,
        playbackTickGeneration: UInt64,
        isPlaying: Bool,
        reduceMotion: Bool,
        resetGeneration: Int
    ) {
        let safeLiveDistance = liveDistance.isFinite ? liveDistance : 0
        let safeGhostDistance = ghostDistance.isFinite ? ghostDistance : 0
        let rawDeltaTime = deltaTime.isFinite && deltaTime > 0 ? deltaTime : 0
        let hasNewPlaybackTick = appliedPlaybackTickGeneration.map {
            $0 != playbackTickGeneration
        } ?? isPlaying
        let safeDeltaTime = hasNewPlaybackTick ? rawDeltaTime : 0
        let liveDelta = previousLiveDistance.map { safeLiveDistance - $0 } ?? 0
        let ghostDelta = previousGhostDistance.map { safeGhostDistance - $0 } ?? 0
        let resetChanged = appliedResetGeneration.map { $0 != resetGeneration } ?? false
        let liveMovedWhilePaused = !isPlaying
            && !hasNewPlaybackTick
            && previousLiveDistance != nil
            && liveDelta != 0
        let ghostMovedWhilePaused = !isPlaying
            && !hasNewPlaybackTick
            && ghostVisible
            && previousGhostDistance != nil
            && ghostDelta != 0
        let liveDiscontinuity = liveMovedWhilePaused
            || !liveDistance.isFinite
            || !liveDelta.isFinite
            || liveDelta < 0
            || liveDelta > 30
        let ghostDiscontinuity = ghostVisible && (
            ghostMovedWhilePaused
                || !ghostDistance.isFinite
                || !ghostDelta.isFinite
                || ghostDelta < 0
                || ghostDelta > 30
        )

        if reduceMotion || !profile.wakeEnabled || resetChanged {
            clearSimulation()
            seedPreviousValues(
                liveDistance: safeLiveDistance,
                ghostDistance: safeGhostDistance,
                livePhase: livePhase,
                playbackTickGeneration: playbackTickGeneration,
                resetGeneration: resetGeneration,
                ghostVisible: ghostVisible
            )
            renderDisabled()
            return
        }

        let livePosition = layout.position(at: safeLiveDistance)
        let liveTangent = layout.tangent(at: safeLiveDistance)
        if liveDiscontinuity {
            clearLiveSimulation()
        } else {
            let livePoint = ReplayEffectPoint(
                x: livePosition.x - liveTangent.x * 1.6,
                y: effectHeight,
                z: livePosition.z - liveTangent.z * 1.6
            )
            _ = liveWake.update(
                position: livePoint,
                tangent: ReplayEffectPoint(
                    x: liveTangent.x,
                    y: liveTangent.y,
                    z: liveTangent.z
                ),
                distanceDelta: liveDelta,
                reduceMotion: false
            )
        }

        if ghostVisible {
            let ghostPosition = layout.ghostPosition(at: safeGhostDistance)
            let ghostTangent = layout.tangent(at: safeGhostDistance)
            if ghostDiscontinuity {
                ghostWake.clear()
            } else {
                let ghostPoint = ReplayEffectPoint(
                    x: ghostPosition.x - ghostTangent.x * 1.6,
                    y: effectHeight,
                    z: ghostPosition.z - ghostTangent.z * 1.6
                )
                _ = ghostWake.update(
                    position: ghostPoint,
                    tangent: ReplayEffectPoint(
                        x: ghostTangent.x,
                        y: ghostTangent.y,
                        z: ghostTangent.z
                    ),
                    distanceDelta: ghostDelta,
                    reduceMotion: false
                )
            }
        } else {
            ghostWake.clear()
            previousGhostDistance = nil
        }

        spray.update(dt: safeDeltaTime, gravity: Self.gravity)
        let canSpawnCatch = profile.sprayEnabled
            && hasNewPlaybackTick
            && safeDeltaTime > 0
            && liveDelta > 0
            && liveDelta <= 30
            && !liveDiscontinuity
            && livePhase.isFinite
        if canSpawnCatch, let previousLivePhase, previousLivePhase.isFinite {
            let catchCount = ReplayMotion.catchEvents(prev: previousLivePhase, next: livePhase)
            if catchCount > 0 {
                let tangent = ReplayEffectPoint(
                    x: liveTangent.x,
                    y: liveTangent.y,
                    z: liveTangent.z
                )
                let radial = ReplayEffectPoint(
                    x: livePosition.x,
                    y: 0,
                    z: livePosition.z
                )
                let lastOrdinal = max(0, liveCatchOrdinal)
                let firstOrdinal = max(0, lastOrdinal - (catchCount - 1))
                for offset in 0..<catchCount {
                    _ = ReplaySprayGenerator.spawnCatch(
                        into: &spray,
                        profile: profile,
                        origin: ReplayEffectPoint(
                            x: livePosition.x,
                            y: effectHeight,
                            z: livePosition.z
                        ),
                        tangent: tangent,
                        radial: radial,
                        catchOrdinal: firstOrdinal + offset
                    )
                }
            }
        }

        previousLiveDistance = safeLiveDistance
        if ghostVisible {
            previousGhostDistance = safeGhostDistance
        }
        previousLivePhase = livePhase.isFinite ? livePhase : nil
        appliedResetGeneration = resetGeneration
        appliedPlaybackTickGeneration = playbackTickGeneration
        renderWake(liveWake, into: liveWakeEntities, opacityMultiplier: 1)
        renderWake(ghostWake, into: ghostWakeEntities, opacityMultiplier: 0.42)
        renderSpray()
    }

    func reset() {
        clearSimulation()
        previousLiveDistance = nil
        previousGhostDistance = nil
        previousLivePhase = nil
        appliedResetGeneration = nil
        appliedPlaybackTickGeneration = nil
        renderDisabled()
    }

    var liveWakeCount: Int { liveWake.count }
    var ghostWakeCount: Int { ghostWake.count }
    var sprayCount: Int { spray.aliveCount }
    func sprayParticle(at index: Int) -> ReplayParticle? { spray.particle(at: index) }
    var fixedEntityCount: Int {
        liveWakeEntities.count + ghostWakeEntities.count + sprayEntities.count
    }

    private var effectHeight: Double {
        switch profile.sport {
        case .rower: 0.05
        case .skierg: 0.07
        case .bike: 0.05
        }
    }

    private func seedPreviousValues(
        liveDistance: Double,
        ghostDistance: Double,
        livePhase: Double,
        playbackTickGeneration: UInt64,
        resetGeneration: Int,
        ghostVisible: Bool
    ) {
        previousLiveDistance = liveDistance
        previousGhostDistance = ghostVisible ? ghostDistance : nil
        previousLivePhase = livePhase.isFinite ? livePhase : nil
        appliedResetGeneration = resetGeneration
        appliedPlaybackTickGeneration = playbackTickGeneration
    }

    private func clearSimulation() {
        liveWake.clear()
        ghostWake.clear()
        spray.clear()
    }

    private func clearLiveSimulation() {
        liveWake.clear()
        spray.clear()
    }

    private func renderWake(
        _ history: ReplayWakeHistory,
        into entities: [ModelEntity],
        opacityMultiplier: Double
    ) {
        for index in entities.indices {
            guard let entry = history.entry(at: index) else {
                disable(entities[index])
                continue
            }
            let entity = entities[index]
            let scale = history.scale(at: index)
            entity.position = SIMD3(
                finiteFloat(entry.position.x),
                finiteFloat(entry.position.y),
                finiteFloat(entry.position.z)
            )
            let heading = atan2(entry.tangent.x, entry.tangent.z)
            entity.orientation = simd_quatf(
                angle: finiteFloat(heading),
                axis: SIMD3(0, 1, 0)
            )
            entity.scale = wakeScale(ageScale: scale)
            setOpacity(
                finiteFloat(history.opacity(at: index) * opacityMultiplier),
                on: entity
            )
            entity.isEnabled = true
        }
    }

    private func renderSpray() {
        for index in sprayEntities.indices {
            guard let particle = spray.particle(at: index) else {
                disable(sprayEntities[index])
                continue
            }
            let entity = sprayEntities[index]
            entity.position = SIMD3(
                finiteFloat(particle.position.x),
                finiteFloat(particle.position.y),
                finiteFloat(particle.position.z)
            )
            let fade = spray.fade(at: index)
            let scale = finiteFloat(
                particle.size * (0.4 + 0.6 * fade),
                fallback: 1
            )
            entity.scale = SIMD3(repeating: max(0.05, scale))
            setOpacity(finiteFloat(fade), on: entity)
            entity.isEnabled = true
        }
    }

    private func wakeScale(ageScale: Double) -> SIMD3<Float> {
        let scale = max(0.05, finiteFloat(ageScale, fallback: 1))
        switch profile.sport {
        case .rower:
            return SIMD3(scale * 0.72, scale * 0.14, scale * 1.8)
        case .skierg:
            return SIMD3(scale * 0.62, scale * 0.18, scale * 1.15)
        case .bike:
            return SIMD3(repeating: scale)
        }
    }

    private func renderDisabled() {
        for entity in liveWakeEntities {
            disable(entity)
        }
        for entity in ghostWakeEntities {
            disable(entity)
        }
        for entity in sprayEntities {
            disable(entity)
        }
    }

    private func disable(_ entity: ModelEntity) {
        entity.isEnabled = false
        setOpacity(0, on: entity)
    }

    private func setOpacity(_ opacity: Float, on entity: ModelEntity) {
        entity.components.set(OpacityComponent(opacity: min(1, max(0, opacity))))
    }

    private func finiteFloat(_ value: Double, fallback: Float = 0) -> Float {
        guard value.isFinite, value >= -Double(Float.greatestFiniteMagnitude),
              value <= Double(Float.greatestFiniteMagnitude) else {
            return fallback
        }
        return Float(value)
    }

    private static func makeEntities(
        count: Int,
        prefix: String,
        mesh: MeshResource,
        material: SimpleMaterial
    ) -> [ModelEntity] {
        (0..<count).map { index in
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "\(prefix)-\(index)"
            entity.isEnabled = false
            entity.components.set(OpacityComponent(opacity: 0))
            return entity
        }
    }
}
