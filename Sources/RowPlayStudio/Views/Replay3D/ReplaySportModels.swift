import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// Protocol for sport-specific avatar animation.
@MainActor
protocol SportAvatar {
    func animate(
        phase: Double,
        reduceMotion: Bool,
        pose: ReplayStrokePose,
        animPhase: Double
    )
}

/// Build a sport-specific avatar entity hierarchy into the parent.
/// Returns a `SportAvatar` that can animate the articulated parts.
@MainActor
func buildSportAvatar(
    sport: Sport,
    accent: Color,
    into parent: ModelEntity,
    opacity: Float = 1.0
) -> SportAvatar {
    switch sport {
    case .rower:
        return buildRowerAvatar(accent: accent, into: parent, opacity: opacity)
    case .skierg:
        return buildSkierAvatar(accent: accent, into: parent, opacity: opacity)
    case .bike:
        return buildBikeAvatar(accent: accent, into: parent, opacity: opacity)
    }
}

// MARK: - RowErg Avatar

@MainActor
private func buildRowerAvatar(
    accent: Color,
    into parent: ModelEntity,
    opacity: Float
) -> SportAvatar {
    let avatar = RowerAvatarParts()

    // Hull — narrow shell
    let hullMesh = MeshResource.generateBox(size: SIMD3(0.5, 0.2, 3.0))
    let hullMat = accentMaterial(accent, opacity: opacity)
    avatar.hull = ModelEntity(mesh: hullMesh, materials: [hullMat])
    avatar.hull.position = SIMD3(0, 0.15, 0)
    parent.addChild(avatar.hull)

    // Rail
    let railMesh = MeshResource.generateBox(size: SIMD3(0.06, 0.04, 2.8))
    let railMat = SimpleMaterial(color: .darkGray, roughness: 0.6, isMetallic: true)
    avatar.rail = ModelEntity(mesh: railMesh, materials: [railMat])
    avatar.rail.position = SIMD3(0, 0.26, 0)
    parent.addChild(avatar.rail)

    // Seat
    let seatMesh = MeshResource.generateBox(size: SIMD3(0.25, 0.06, 0.20))
    let seatMat = SimpleMaterial(color: .gray, roughness: 0.8, isMetallic: false)
    avatar.seat = ModelEntity(mesh: seatMesh, materials: [seatMat])
    avatar.seat.position = SIMD3(0, 0.30, -0.2)
    parent.addChild(avatar.seat)

    // Handle
    let handleMesh = MeshResource.generateCylinder(height: 0.5, radius: 0.015)
    let handleMat = SimpleMaterial(color: NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.15, alpha: 1), roughness: 0.5, isMetallic: false)
    avatar.handle = ModelEntity(mesh: handleMesh, materials: [handleMat])
    avatar.handle.position = SIMD3(0, 0.55, 0.6)
    avatar.handle.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3(0, 0, 1))
    parent.addChild(avatar.handle)

    // Oars
    for side: Float in [-1, 1] {
        let oar = Entity()
        oar.name = "oar-\(side > 0 ? "starboard" : "port")"
        let shaftMesh = MeshResource.generateCylinder(height: 2.4, radius: 0.02)
        let shaftMat = SimpleMaterial(color: NSColor(calibratedRed: 0.9, green: 0.93, blue: 0.94, alpha: 1), roughness: 0.5, isMetallic: false)
        let shaft = ModelEntity(mesh: shaftMesh, materials: [shaftMat])
        shaft.position = SIMD3(side * 1.2, 0, 0)
        shaft.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3(0, 0, 1))
        oar.addChild(shaft)

        let bladeMesh = MeshResource.generateBox(size: SIMD3(0.4, 0.02, 0.2))
        let bladeMat = accentMaterial(accent, opacity: opacity)
        let blade = ModelEntity(mesh: bladeMesh, materials: [bladeMat])
        blade.position = SIMD3(side * 2.4, -0.04, 0)
        oar.addChild(blade)

        oar.position = SIMD3(0, 0.28, 0)
        parent.addChild(oar)
        avatar.oars.append(oar)
    }

    // Athlete body
    buildAthleteBody(into: parent, seated: true, accent: accent, opacity: opacity, avatar: avatar)

    return avatar
}

// MARK: - SkiErg Avatar

@MainActor
private func buildSkierAvatar(
    accent: Color,
    into parent: ModelEntity,
    opacity: Float
) -> SportAvatar {
    let avatar = SkierAvatarParts()

    // Frame — upright posts
    let postMesh = MeshResource.generateBox(size: SIMD3(0.08, 1.8, 0.08))
    let postMat = SimpleMaterial(color: NSColor(calibratedRed: 0.3, green: 0.3, blue: 0.32, alpha: 1), roughness: 0.5, isMetallic: true)
    for x: Float in [-0.3, 0.3] {
        let post = ModelEntity(mesh: postMesh, materials: [postMat])
        post.position = SIMD3(x, 0.9, -0.5)
        parent.addChild(post)
    }

    // Top bar
    let topBarMesh = MeshResource.generateBox(size: SIMD3(0.7, 0.06, 0.06))
    let topBar = ModelEntity(mesh: topBarMesh, materials: [postMat])
    topBar.position = SIMD3(0, 1.8, -0.5)
    parent.addChild(topBar)

    // Cable/pulley
    let cableMesh = MeshResource.generateCylinder(height: 1.2, radius: 0.01)
    let cableMat = SimpleMaterial(color: .gray, roughness: 0.4, isMetallic: true)
    avatar.cable = ModelEntity(mesh: cableMesh, materials: [cableMat])
    avatar.cable.position = SIMD3(0, 1.2, -0.5)
    parent.addChild(avatar.cable)

    // Handles
    let handleMesh = MeshResource.generateBox(size: SIMD3(0.06, 0.06, 0.25))
    let handleMat = SimpleMaterial(color: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1), roughness: 0.6, isMetallic: false)
    avatar.leftHandle = ModelEntity(mesh: handleMesh, materials: [handleMat])
    avatar.leftHandle.position = SIMD3(-0.15, 0.8, 0.1)
    parent.addChild(avatar.leftHandle)

    avatar.rightHandle = ModelEntity(mesh: handleMesh, materials: [handleMat])
    avatar.rightHandle.position = SIMD3(0.15, 0.8, 0.1)
    parent.addChild(avatar.rightHandle)

    // Platform
    let platformMesh = MeshResource.generateBox(size: SIMD3(0.8, 0.06, 0.6))
    let platformMat = accentMaterial(accent, opacity: opacity)
    let platform = ModelEntity(mesh: platformMesh, materials: [platformMat])
    platform.position = SIMD3(0, 0.03, 0)
    parent.addChild(platform)

    // Poles
    for side: Float in [-1, 1] {
        let pole = Entity()
        pole.name = "pole-\(side > 0 ? "right" : "left")"
        let shaftMesh = MeshResource.generateCylinder(height: 1.2, radius: 0.015)
        let shaftMat = SimpleMaterial(color: NSColor(calibratedRed: 0.9, green: 0.93, blue: 0.94, alpha: 1), roughness: 0.5, isMetallic: false)
        let shaft = ModelEntity(mesh: shaftMesh, materials: [shaftMat])
        shaft.position = SIMD3(0, -0.6, 0)
        pole.addChild(shaft)

        let basketMesh = MeshResource.generateCylinder(height: 0.03, radius: 0.06)
        let basketMat = accentMaterial(accent, opacity: opacity)
        let basket = ModelEntity(mesh: basketMesh, materials: [basketMat])
        basket.position = SIMD3(0, -1.15, 0)
        pole.addChild(basket)

        pole.position = SIMD3(side * 0.3, 0.8, 0.1)
        parent.addChild(pole)
        avatar.poles.append(pole)
    }

    // Athlete body
    buildAthleteBody(into: parent, seated: false, accent: accent, opacity: opacity, avatar: avatar)

    return avatar
}

// MARK: - BikeErg Avatar

@MainActor
private func buildBikeAvatar(
    accent: Color,
    into parent: ModelEntity,
    opacity: Float
) -> SportAvatar {
    let avatar = BikeAvatarParts()
    let wheelR: Float = 0.35

    // Wheels (simplified — sphere instead of torus)
    for z: Float in [0.7, -0.7] {
        let wheel = Entity()
        wheel.name = "wheel-\(z > 0 ? "front" : "rear")"
        let tyreMesh = MeshResource.generateSphere(radius: wheelR)
        let tyreMat = SimpleMaterial(color: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1), roughness: 0.6, isMetallic: false)
        let tyre = ModelEntity(mesh: tyreMesh, materials: [tyreMat])
        tyre.scale = SIMD3(1, 1, 0.3) // Flatten to disc shape
        wheel.addChild(tyre)

        // Spokes (crossed boxes)
        let spokeMesh = MeshResource.generateBox(size: SIMD3(0.02, wheelR * 1.6, 0.02))
        let spokeMat = accentMaterial(accent, opacity: opacity)
        let spoke1 = ModelEntity(mesh: spokeMesh, materials: [spokeMat])
        wheel.addChild(spoke1)
        let spoke2 = ModelEntity(mesh: spokeMesh, materials: [spokeMat])
        spoke2.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3(1, 0, 0))
        wheel.addChild(spoke2)

        wheel.position = SIMD3(0, wheelR, z)
        parent.addChild(wheel)
        avatar.wheels.append(wheel)
    }

    // Frame
    let frameMat = accentMaterial(accent, opacity: opacity)
    let downTubeMesh = MeshResource.generateBox(size: SIMD3(0.06, 0.06, 1.4))
    let downTube = ModelEntity(mesh: downTubeMesh, materials: [frameMat])
    downTube.position = SIMD3(0, wheelR + 0.15, 0)
    parent.addChild(downTube)

    let seatTubeMesh = MeshResource.generateBox(size: SIMD3(0.06, 0.6, 0.06))
    let seatTube = ModelEntity(mesh: seatTubeMesh, materials: [frameMat])
    seatTube.position = SIMD3(0, wheelR + 0.4, -0.35)
    parent.addChild(seatTube)

    let topTubeMesh = MeshResource.generateBox(size: SIMD3(0.05, 0.05, 0.9))
    let topTube = ModelEntity(mesh: topTubeMesh, materials: [frameMat])
    topTube.position = SIMD3(0, wheelR + 0.7, -0.1)
    parent.addChild(topTube)

    // Cranks
    let crankGroup = Entity()
    crankGroup.name = "cranks"
    crankGroup.position = SIMD3(0, wheelR, -0.05)
    let crankDiscMesh = MeshResource.generateSphere(radius: 0.14)
    let crankDiscMat = SimpleMaterial(color: .gray, roughness: 0.4, isMetallic: true)
    let crankDisc = ModelEntity(mesh: crankDiscMesh, materials: [crankDiscMat])
    crankDisc.scale = SIMD3(1, 0.2, 1) // Flatten to disc
    crankGroup.addChild(crankDisc)

    let pedalMesh = MeshResource.generateBox(size: SIMD3(0.18, 0.04, 0.08))
    let pedalMat = SimpleMaterial(color: .darkGray, roughness: 0.7, isMetallic: false)
    for side: Float in [-1, 1] {
        let pedal = ModelEntity(mesh: pedalMesh, materials: [pedalMat])
        pedal.position = SIMD3(side * 0.1, side * 0.14, 0)
        crankGroup.addChild(pedal)
    }
    parent.addChild(crankGroup)
    avatar.cranks = crankGroup

    // Handlebar
    let barMesh = MeshResource.generateCylinder(height: 0.6, radius: 0.02)
    let barMat = SimpleMaterial(color: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1), roughness: 0.6, isMetallic: false)
    let handlebar = ModelEntity(mesh: barMesh, materials: [barMat])
    handlebar.position = SIMD3(0, wheelR + 0.8, 0.35)
    handlebar.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3(0, 0, 1))
    parent.addChild(handlebar)

    // Athlete body
    buildAthleteBody(into: parent, seated: true, accent: accent, opacity: opacity, avatar: avatar)

    return avatar
}

// MARK: - Athlete Body

@MainActor
private func buildAthleteBody(
    into parent: Entity,
    seated: Bool,
    accent: Color,
    opacity: Float,
    avatar: AnySportAvatar
) {
    let skinColor = NSColor(calibratedRed: 0.79, green: 0.60, blue: 0.45, alpha: 1)
    let kitColor = NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.19, alpha: 1)
    let skinMat = SimpleMaterial(color: skinColor, roughness: 0.74, isMetallic: false)
    let kitMat = SimpleMaterial(color: kitColor, roughness: 0.7, isMetallic: false)

    let torsoHeight: Float = seated ? 0.35 : 0.45
    let torsoY: Float = seated ? 0.48 : 0.95

    // Torso
    let torsoMesh = MeshResource.generateBox(size: SIMD3(0.30, torsoHeight, 0.18))
    let torso = ModelEntity(mesh: torsoMesh, materials: [kitMat])
    torso.position = SIMD3(0, torsoY, seated ? 0 : 0.05)
    parent.addChild(torso)
    avatar.torso = torso

    // Head
    let headMesh = MeshResource.generateSphere(radius: 0.10)
    let head = ModelEntity(mesh: headMesh, materials: [skinMat])
    head.position = SIMD3(0, torsoY + torsoHeight / 2 + 0.12, seated ? 0.02 : 0.05)
    parent.addChild(head)

    // Arms (simplified)
    let armMesh = MeshResource.generateCylinder(height: 0.35, radius: 0.025)
    avatar.leftArm = ModelEntity(mesh: armMesh, materials: [skinMat])
    avatar.leftArm.position = SIMD3(-0.2, torsoY + 0.08, seated ? 0.15 : 0)
    parent.addChild(avatar.leftArm)

    avatar.rightArm = ModelEntity(mesh: armMesh, materials: [skinMat])
    avatar.rightArm.position = SIMD3(0.2, torsoY + 0.08, seated ? 0.15 : 0)
    parent.addChild(avatar.rightArm)

    // Legs
    let legMesh = MeshResource.generateCylinder(height: 0.4, radius: 0.035)
    avatar.leftLeg = ModelEntity(mesh: legMesh, materials: [kitMat])
    avatar.leftLeg.position = SIMD3(-0.1, torsoY - torsoHeight / 2 - 0.2, 0)
    parent.addChild(avatar.leftLeg)

    avatar.rightLeg = ModelEntity(mesh: legMesh, materials: [kitMat])
    avatar.rightLeg.position = SIMD3(0.1, torsoY - torsoHeight / 2 - 0.2, 0)
    parent.addChild(avatar.rightLeg)
}

// MARK: - Avatar Parts

/// Base class holding common articulated entity references.
@MainActor
private class AnySportAvatar: SportAvatar {
    var torso: ModelEntity = ModelEntity()
    var leftArm: ModelEntity = ModelEntity()
    var rightArm: ModelEntity = ModelEntity()
    var leftLeg: ModelEntity = ModelEntity()
    var rightLeg: ModelEntity = ModelEntity()

    func animate(
        phase: Double,
        reduceMotion: Bool,
        pose: ReplayStrokePose,
        animPhase: Double
    ) {
        // Override in subclasses
    }
}

@MainActor
private class RowerAvatarParts: AnySportAvatar {
    var hull = ModelEntity()
    var rail = ModelEntity()
    var seat = ModelEntity()
    var handle = ModelEntity()
    var oars: [Entity] = []

    override func animate(
        phase: Double,
        reduceMotion: Bool,
        pose: ReplayStrokePose,
        animPhase: Double
    ) {
        if reduceMotion {
            hull.position.y = 0.15
            seat.position.z = -0.2
            handle.position = SIMD3(0, 0.55, 0.6)
            torso.position.z = 0
            for oar in oars { oar.orientation = .init(angle: 0, axis: SIMD3(0, 1, 0)) }
            return
        }

        let w = pose.warpedPhase
        let drive = Float(cos(w))
        let amp = Float(pose.amplitude)

        // Seat slides along rail
        seat.position.z = -0.2 - drive * 0.18 * amp

        // Handle moves with stroke
        handle.position = SIMD3(0, 0.55 - Float(sin(w)) * 0.04 * amp, 0.6 - drive * 0.06 * amp)

        // Oars sweep
        for (i, oar) in oars.enumerated() {
            let side: Float = i == 0 ? -1 : 1
            oar.orientation = simd_quatf(
                angle: -side * drive * 0.4 * amp,
                axis: SIMD3(0, 1, 0)
            )
        }

        // Body lean
        torso.position.z = -drive * 0.1 * amp
    }
}

@MainActor
private class SkierAvatarParts: AnySportAvatar {
    var cable = ModelEntity()
    var leftHandle = ModelEntity()
    var rightHandle = ModelEntity()
    var poles: [Entity] = []

    override func animate(
        phase: Double,
        reduceMotion: Bool,
        pose: ReplayStrokePose,
        animPhase: Double
    ) {
        if reduceMotion {
            torso.position.y = 0.95
            torso.orientation = .init(angle: 0, axis: SIMD3(1, 0, 0))
            leftHandle.position = SIMD3(-0.15, 0.8, 0.1)
            rightHandle.position = SIMD3(0.15, 0.8, 0.1)
            for pole in poles { pole.orientation = .init(angle: 0, axis: SIMD3(1, 0, 0)) }
            return
        }

        let w = pose.warpedPhase
        let swing = Float(cos(w))
        let crunch = max(0, Float(-sin(w)))
        let amp = Float(pose.amplitude)

        // Upper body crunch
        torso.position.y = 0.95 - crunch * 0.15 * amp
        torso.orientation = simd_quatf(angle: crunch * 0.3 * amp, axis: SIMD3(1, 0, 0))

        // Handles pull down
        let handleY = 0.8 + swing * 0.1 * amp - crunch * 0.1 * amp
        leftHandle.position = SIMD3(-0.15, handleY, 0.1 + swing * 0.15 * amp)
        rightHandle.position = SIMD3(0.15, handleY, 0.1 + swing * 0.15 * amp)

        // Poles swing
        for pole in poles {
            pole.orientation = simd_quatf(angle: -swing * 0.6 * amp - 0.1, axis: SIMD3(1, 0, 0))
        }
    }
}

@MainActor
private class BikeAvatarParts: AnySportAvatar {
    var wheels: [Entity] = []
    var cranks = Entity()

    override func animate(
        phase: Double,
        reduceMotion: Bool,
        pose: ReplayStrokePose,
        animPhase: Double
    ) {
        if reduceMotion {
            for wheel in wheels { wheel.orientation = .init(angle: 0, axis: SIMD3(1, 0, 0)) }
            cranks.orientation = .init(angle: 0, axis: SIMD3(1, 0, 0))
            torso.orientation = .init(angle: 0, axis: SIMD3(0, 0, 1))
            return
        }

        let p = Float(pose.phase)

        // Wheels spin
        for wheel in wheels {
            wheel.orientation = simd_quatf(angle: p * 2.4, axis: SIMD3(1, 0, 0))
        }

        // Cranks turn
        cranks.orientation = simd_quatf(angle: p, axis: SIMD3(1, 0, 0))

        // Subtle rider sway
        torso.orientation = simd_quatf(angle: sin(p) * 0.04, axis: SIMD3(0, 0, 1))
    }
}

// MARK: - Material Helpers

@MainActor
private func accentMaterial(_ color: Color, opacity: Float) -> SimpleMaterial {
    let nsColor = NSColor(color)
    if opacity < 1 {
        return SimpleMaterial(color: nsColor.withAlphaComponent(CGFloat(opacity)), roughness: 0.56, isMetallic: false)
    }
    return SimpleMaterial(color: nsColor, roughness: 0.56, isMetallic: false)
}
