import Foundation
import RealityKit
import SwiftUI

/// Reusable mesh and material helpers for articulated sport rigs.
///
/// All mesh/material creation happens once during scene construction.
/// Frame updates change transforms only — no per-frame allocations.
@MainActor
enum ReplayMeshFactory {
    // MARK: - Material Constants

    static let humanSkin = NSColor(calibratedRed: 0.79, green: 0.60, blue: 0.45, alpha: 1)
    static let humanHair = NSColor(calibratedRed: 0.14, green: 0.11, blue: 0.09, alpha: 1)
    static let humanKit = NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.19, alpha: 1)
    static let humanKitDark = NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.17, alpha: 1)
    static let humanShoe = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.10, alpha: 1)

    // MARK: - Material Factories

    static func skinMaterial(opacity: Float = 1) -> SimpleMaterial {
        let color = opacity < 1
            ? humanSkin.withAlphaComponent(CGFloat(opacity))
            : humanSkin
        return SimpleMaterial(color: color, roughness: 0.74, isMetallic: false)
    }

    static func hairMaterial(opacity: Float = 1) -> SimpleMaterial {
        let color = opacity < 1
            ? humanHair.withAlphaComponent(CGFloat(opacity))
            : humanHair
        return SimpleMaterial(color: color, roughness: 0.8, isMetallic: false)
    }

    static func kitMaterial(opacity: Float = 1) -> SimpleMaterial {
        let color = opacity < 1
            ? humanKit.withAlphaComponent(CGFloat(opacity))
            : humanKit
        return SimpleMaterial(color: color, roughness: 0.7, isMetallic: false)
    }

    static func kitDarkMaterial(opacity: Float = 1) -> SimpleMaterial {
        let color = opacity < 1
            ? humanKitDark.withAlphaComponent(CGFloat(opacity))
            : humanKitDark
        return SimpleMaterial(color: color, roughness: 0.7, isMetallic: false)
    }

    static func shoeMaterial(opacity: Float = 1) -> SimpleMaterial {
        let color = opacity < 1
            ? humanShoe.withAlphaComponent(CGFloat(opacity))
            : humanShoe
        return SimpleMaterial(color: color, roughness: 0.8, isMetallic: false)
    }

    static func accentMaterial(_ color: Color, opacity: Float = 1) -> SimpleMaterial {
        let nsColor = NSColor(color)
        let finalColor = opacity < 1
            ? nsColor.withAlphaComponent(CGFloat(opacity))
            : nsColor
        return SimpleMaterial(color: finalColor, roughness: 0.56, isMetallic: false)
    }

    static func metalMaterial(
        _ color: NSColor,
        opacity: Float = 1
    ) -> SimpleMaterial {
        let finalColor = opacity < 1
            ? color.withAlphaComponent(CGFloat(opacity))
            : color
        return SimpleMaterial(color: finalColor, isMetallic: true)
    }

    // MARK: - Mesh Helpers

    /// Creates a hand mesh: palm sphere with four finger cylinders and a thumb.
    static func handEntity(material: SimpleMaterial) -> Entity {
        let hand = Entity()
        hand.name = "hand"
        // Palm
        let palm = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.03),
            materials: [material]
        )
        palm.scale = SIMD3(1.3, 0.8, 1.6)
        palm.name = "palm"
        hand.addChild(palm)
        // Fingers
        for i in 0..<4 {
            let finger = ModelEntity(
                mesh: MeshResource.generateCylinder(height: 0.035, radius: 0.008),
                materials: [material]
            )
            finger.position = SIMD3(Float(i - 1) * 0.012, 0, 0.035)
            finger.name = "finger-\(i)"
            hand.addChild(finger)
        }
        // Thumb
        let thumb = ModelEntity(
            mesh: MeshResource.generateCylinder(height: 0.03, radius: 0.01),
            materials: [material]
        )
        thumb.position = SIMD3(-0.025, 0.005, 0.02)
        thumb.name = "thumb"
        hand.addChild(thumb)
        return hand
    }

    /// Creates a foot mesh: shoe-shaped sole with toe and heel.
    static func footEntity(material: SimpleMaterial) -> Entity {
        let foot = Entity()
        foot.name = "foot"
        // Sole
        let sole = ModelEntity(
            mesh: MeshResource.generateBox(size: SIMD3(0.08, 0.035, 0.16)),
            materials: [material]
        )
        sole.position = SIMD3(0, 0, 0.04)
        sole.name = "sole"
        foot.addChild(sole)
        // Toe
        let toe = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.03),
            materials: [material]
        )
        toe.scale = SIMD3(1.3, 0.8, 1.6)
        toe.position = SIMD3(0, -0.005, 0.12)
        toe.name = "toe"
        foot.addChild(toe)
        // Heel
        let heel = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.028),
            materials: [material]
        )
        heel.scale = SIMD3(1.2, 1, 1)
        heel.position = SIMD3(0, 0, -0.04)
        heel.name = "heel"
        foot.addChild(heel)
        return foot
    }

    /// Creates a head with cranium, jaw, ears, and hair cap.
    static func headEntity(
        skinMaterial: SimpleMaterial,
        hairMaterial: SimpleMaterial
    ) -> Entity {
        let head = Entity()
        head.name = "head"
        // Cranium
        let cranium = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.105),
            materials: [skinMaterial]
        )
        cranium.scale = SIMD3(1, 1.24, 0.95)
        cranium.name = "cranium"
        head.addChild(cranium)
        // Jaw
        let jaw = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.065),
            materials: [skinMaterial]
        )
        jaw.scale = SIMD3(1.2, 0.77, 1.08)
        jaw.position = SIMD3(0, -0.07, 0.02)
        jaw.name = "jaw"
        head.addChild(jaw)
        // Ears
        for side: Float in [-1, 1] {
            let ear = ModelEntity(
                mesh: MeshResource.generateSphere(radius: 0.022),
                materials: [skinMaterial]
            )
            ear.scale = SIMD3(0.5, 1, 1)
            ear.position = SIMD3(side * 0.1, -0.01, -0.01)
            ear.name = "ear-\(side > 0 ? "R" : "L")"
            head.addChild(ear)
        }
        // Hair cap
        let hair = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.11),
            materials: [hairMaterial]
        )
        hair.scale = SIMD3(1, 0.5, 0.95)
        hair.position = SIMD3(0, 0.09, 0)
        hair.name = "hair"
        head.addChild(hair)
        return head
    }

    /// Creates a wheel with tyre sphere (flattened) and crossed spokes.
    static func wheelEntity(
        radius: Float,
        tyreMaterial: SimpleMaterial,
        spokeMaterial: SimpleMaterial
    ) -> Entity {
        let wheel = Entity()
        wheel.name = "wheel"
        // Tyre — flattened sphere as disc approximation
        let tyre = ModelEntity(
            mesh: MeshResource.generateSphere(radius: radius),
            materials: [tyreMaterial]
        )
        tyre.scale = SIMD3(1, 1, 0.3)
        tyre.name = "tyre"
        wheel.addChild(tyre)
        // Spokes — crossed boxes
        let spokeMesh = MeshResource.generateBox(
            size: SIMD3(0.02, radius * 1.6, 0.02)
        )
        let spoke1 = ModelEntity(mesh: spokeMesh, materials: [spokeMaterial])
        spoke1.name = "spoke-1"
        wheel.addChild(spoke1)
        let spoke2 = ModelEntity(mesh: spokeMesh, materials: [spokeMaterial])
        spoke2.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        spoke2.name = "spoke-2"
        wheel.addChild(spoke2)
        return wheel
    }
}
