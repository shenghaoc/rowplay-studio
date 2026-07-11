import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// Container for the persistent 3D scene entities.
@MainActor
final class Replay3DSceneContainer {
    let root: Entity
    let camera: PerspectiveCamera
    let liveGroup: ModelEntity
    let liveAvatar: SportAvatar
    let ghostGroup: ModelEntity
    let ghostAvatar: SportAvatar
    let course: Entity
    let groundEntity: ModelEntity
    let light: DirectionalLight
    let fillLight: DirectionalLight
    let sport: Sport
    let layout: ReplayCourseLayout

    init(
        root: Entity,
        camera: PerspectiveCamera,
        liveGroup: ModelEntity,
        liveAvatar: SportAvatar,
        ghostGroup: ModelEntity,
        ghostAvatar: SportAvatar,
        course: Entity,
        groundEntity: ModelEntity,
        light: DirectionalLight,
        fillLight: DirectionalLight,
        sport: Sport,
        layout: ReplayCourseLayout
    ) {
        self.root = root
        self.camera = camera
        self.liveGroup = liveGroup
        self.liveAvatar = liveAvatar
        self.ghostGroup = ghostGroup
        self.ghostAvatar = ghostAvatar
        self.course = course
        self.groundEntity = groundEntity
        self.light = light
        self.fillLight = fillLight
        self.sport = sport
        self.layout = layout
    }
}

/// Builds and updates the RealityKit scene for the 3D replay.
@MainActor
enum Replay3DSceneBuilder {
    static let loopMeters = ReplayCourseLayout.loopMeters

    // MARK: - Build

    static func buildScene(
        sport: Sport,
        colorScheme: ColorScheme
    ) throws -> Replay3DSceneContainer {
        let root = Entity()
        root.name = "scene-root"

        let layout = ReplayCourseLayout.standard

        // Camera
        let camera = PerspectiveCamera()
        camera.name = "chase-camera"
        camera.camera.fieldOfViewInDegrees = 46
        camera.position = SIMD3(0, 6, -12)
        root.addChild(camera)

        // Lighting — directional sun + warm fill
        let sun = DirectionalLight()
        sun.name = "sun"
        sun.light.color = .white
        sun.light.intensity = 12_000
        sun.look(at: SIMD3(0, 0, 0), from: SIMD3(14, 26, 10), relativeTo: nil)
        root.addChild(sun)

        let fill = DirectionalLight()
        fill.name = "fill-light"
        fill.light.color = NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.82, alpha: 1)
        fill.light.intensity = 3_000
        fill.look(at: SIMD3(0, 0, 0), from: SIMD3(-10, 8, -6), relativeTo: nil)
        root.addChild(fill)

        // Ground
        let groundMesh = MeshResource.generatePlane(width: 160, depth: 160)
        let groundColor = groundColor(for: sport, colorScheme: colorScheme)
        let groundMaterial = SimpleMaterial(color: groundColor, roughness: 0.85, isMetallic: false)
        let ground = ModelEntity(mesh: groundMesh, materials: [groundMaterial])
        ground.name = "ground"
        ground.position = SIMD3(0, -0.05, 0)
        root.addChild(ground)

        // Course ring
        let courseEntity = Entity()
        courseEntity.name = "course"
        root.addChild(courseEntity)
        buildCourseRing(into: courseEntity, layout: layout, sport: sport, colorScheme: colorScheme)

        // Start/finish marker
        buildStartFinishMarker(into: courseEntity, layout: layout, colorScheme: colorScheme)

        // Live avatar
        let liveGroup = ModelEntity()
        liveGroup.name = "live-athlete"
        root.addChild(liveGroup)
        let liveAvatar = buildSportAvatar(sport: sport, accent: .green, into: liveGroup)

        // Ghost avatar
        let ghostGroup = ModelEntity()
        ghostGroup.name = "ghost-athlete"
        ghostGroup.isEnabled = false
        root.addChild(ghostGroup)
        let ghostAvatar = buildSportAvatar(sport: sport, accent: .purple, into: ghostGroup, opacity: 0.45)

        return Replay3DSceneContainer(
            root: root,
            camera: camera,
            liveGroup: liveGroup,
            liveAvatar: liveAvatar,
            ghostGroup: ghostGroup,
            ghostAvatar: ghostAvatar,
            course: courseEntity,
            groundEntity: ground,
            light: sun,
            fillLight: fill,
            sport: sport,
            layout: layout
        )
    }

    // MARK: - Update

    /// Update all entity positions, orientations, and animation state for the
    /// current frame. Called from the `RealityView.update` closure.
    static func updateScene(
        container: Replay3DSceneContainer,
        livePose: ReplayStrokePose,
        liveDistance: Double,
        liveFrame: ReplayFrame,
        sport: Sport,
        ghostPose: ReplayStrokePose?,
        ghostDistance: Double,
        ghostVisible: Bool,
        reduceMotion: Bool,
        colorScheme: ColorScheme,
        animPhase: Double
    ) {
        let layout = container.layout

        // Live position
        let livePos = layout.position(at: liveDistance)
        let liveHeading = layout.headingAngle(at: liveDistance)
        // Vertical bob: 6cm peak-to-peak, scaled by animation amplitude.
        let bob: Float = reduceMotion ? 0 : Float(sin(livePose.warpedPhase) * 0.06 * livePose.amplitude)

        container.liveGroup.position = SIMD3(Float(livePos.x), bob, Float(livePos.z))
        container.liveGroup.orientation = simd_quatf(angle: Float(liveHeading), axis: SIMD3(0, 1, 0))

        // Animate live avatar
        container.liveAvatar.animate(
            phase: livePose.phase,
            reduceMotion: reduceMotion,
            pose: livePose,
            animPhase: animPhase
        )

        // Ghost
        if ghostVisible, let ghostPose {
            container.ghostGroup.isEnabled = true
            let ghostPos = layout.ghostPosition(at: ghostDistance)
            let ghostHeading = layout.headingAngle(at: ghostDistance)
            container.ghostGroup.position = SIMD3(Float(ghostPos.x), 0, Float(ghostPos.z))
            container.ghostGroup.orientation = simd_quatf(angle: Float(ghostHeading), axis: SIMD3(0, 1, 0))
            container.ghostAvatar.animate(
                phase: ghostPose.phase,
                reduceMotion: reduceMotion,
                pose: ghostPose,
                animPhase: animPhase * 0.9
            )
        } else {
            container.ghostGroup.isEnabled = false
        }

        // Chase camera
        updateCamera(
            camera: container.camera,
            target: container.liveGroup.position,
            heading: Float(liveHeading),
            reduceMotion: reduceMotion
        )
    }

    // MARK: - Camera

    private static func updateCamera(
        camera: PerspectiveCamera,
        target: SIMD3<Float>,
        heading: Float,
        reduceMotion: Bool
    ) {
        // Chase camera offsets: 8m behind, 5m above, looking 6m ahead.
        let back: Float = 8
        let height: Float = 5
        let ahead: Float = 6

        let sinH = sin(heading)
        let cosH = cos(heading)

        let desiredPos = SIMD3(
            target.x - sinH * back,
            height,
            target.z - cosH * back
        )
        let lookTarget = SIMD3(
            target.x + sinH * ahead,
            0.5,
            target.z + cosH * ahead
        )

        if reduceMotion {
            camera.position = desiredPos
        } else {
            // Simple per-frame lerp. RealityKit's update cadence is tied to the
            // display refresh rate, so the effective smoothing speed is roughly
            // proportional to frame rate. This is acceptable for a chase camera
            // that only needs to feel smooth, not be physically accurate.
            let factor: Float = 0.08
            camera.position = camera.position + (desiredPos - camera.position) * factor
        }

        camera.look(at: lookTarget, from: camera.position, relativeTo: nil)
    }

    // MARK: - Course Geometry

    private static func buildCourseRing(
        into parent: Entity,
        layout: ReplayCourseLayout,
        sport: Sport,
        colorScheme: ColorScheme
    ) {
        let radius = Float(layout.loopRadius)

        // Main lane ring. Build a narrow annulus from tangent-aligned segments
        // rather than a single box, which would cover the entire course
        // interior and obscure the sport-specific ground surface.
        let segmentCount = 160
        let laneWidth: Float = 5
        let segmentLength = (2 * Float.pi * radius) / Float(segmentCount) * 1.02
        let ringMesh = MeshResource.generateBox(size: SIMD3(segmentLength, 0.06, laneWidth))
        let ringColor = laneColor(for: sport, colorScheme: colorScheme)
        let ringMat = SimpleMaterial(color: ringColor, roughness: 0.5, isMetallic: false)
        for index in 0..<segmentCount {
            let angle = Float(index) / Float(segmentCount) * Float.pi * 2
            let ringSegment = ModelEntity(mesh: ringMesh, materials: [ringMat])
            ringSegment.name = "lane-ring-segment-\(index)"
            ringSegment.position = SIMD3(radius * sin(angle), 0.03, radius * cos(angle))
            ringSegment.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
            parent.addChild(ringSegment)
        }

        // Use small boxes around the circle as lane markers
        let markerMesh = MeshResource.generateBox(size: SIMD3(0.12, 0.08, 0.4))
        let markerColor: NSColor = sport == .bike
            ? NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.1, alpha: 1)
            : NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.9, alpha: 1)
        let markerMat = SimpleMaterial(color: markerColor, roughness: 0.5, isMetallic: false)

        for i in 0..<80 {
            let angle = Float(i) / 80.0 * Float.pi * 2
            let x = radius * sin(angle)
            let z = radius * cos(angle)
            let marker = ModelEntity(mesh: markerMesh, materials: [markerMat])
            marker.position = SIMD3(x, 0.04, z)
            marker.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
            parent.addChild(marker)
        }

        // Distance markers (every 50m)
        let distMarkerMesh = MeshResource.generateBox(size: SIMD3(0.15, 0.08, 0.5))
        let distMarkerMat = SimpleMaterial(color: markerColor, roughness: 0.5, isMetallic: false)
        for i in 0..<8 {
            let dist = Double(i) * 50
            let pos = layout.position(at: dist, laneOffset: 2.5)
            let marker = ModelEntity(mesh: distMarkerMesh, materials: [distMarkerMat])
            marker.position = SIMD3(Float(pos.x), 0.04, Float(pos.z))
            parent.addChild(marker)
        }
    }

    private static func buildStartFinishMarker(
        into parent: Entity,
        layout: ReplayCourseLayout,
        colorScheme: ColorScheme
    ) {
        // Checkerboard pattern across the lane at distance 0
        let cellSize: Float = 0.8
        let darkColor = NSColor.black
        let lightColor = NSColor.white
        let darkMat = SimpleMaterial(color: darkColor, roughness: 0.6, isMetallic: false)
        let lightMat = SimpleMaterial(color: lightColor, roughness: 0.6, isMetallic: false)
        let cellMesh = MeshResource.generateBox(size: SIMD3(cellSize, 0.06, cellSize))

        let innerR = Float(layout.loopRadius) - 3
        let outerR = Float(layout.loopRadius) + 3
        let rows = Int((outerR - innerR) / cellSize)

        for row in 0..<rows {
            for col in 0..<3 {
                let radius = innerR + Float(row) * cellSize + cellSize / 2
                let angle = Float(col) * cellSize / radius - Float.pi * 2 * 0.002
                let x = radius * sin(angle)
                let z = radius * cos(angle)
                let isDark = (row + col) % 2 == 0
                let cell = ModelEntity(mesh: cellMesh, materials: [isDark ? darkMat : lightMat])
                cell.position = SIMD3(x, 0.03, z)
                parent.addChild(cell)
            }
        }
    }

    // MARK: - Colors

    private static func groundColor(for sport: Sport, colorScheme: ColorScheme) -> NSColor {
        switch sport {
        case .rower:
            colorScheme == .dark
                ? NSColor(calibratedRed: 0.07, green: 0.23, blue: 0.28, alpha: 1)
                : NSColor(calibratedRed: 0.50, green: 0.77, blue: 0.84, alpha: 1)
        case .skierg:
            colorScheme == .dark
                ? NSColor(calibratedRed: 0.72, green: 0.77, blue: 0.80, alpha: 1)
                : NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.97, alpha: 1)
        case .bike:
            colorScheme == .dark
                ? NSColor(calibratedRed: 0.15, green: 0.20, blue: 0.23, alpha: 1)
                : NSColor(calibratedRed: 0.60, green: 0.64, blue: 0.67, alpha: 1)
        }
    }

    private static func laneColor(for sport: Sport, colorScheme: ColorScheme) -> NSColor {
        switch sport {
        case .rower:
            colorScheme == .dark
                ? NSColor(calibratedRed: 0.31, green: 0.70, blue: 0.78, alpha: 1)
                : NSColor(calibratedRed: 0.85, green: 0.97, blue: 1.0, alpha: 1)
        case .skierg:
            colorScheme == .dark
                ? NSColor(calibratedRed: 0.72, green: 0.79, blue: 0.84, alpha: 1)
                : NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.91, alpha: 1)
        case .bike:
            colorScheme == .dark
                ? NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.08, alpha: 1)
                : NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.04, alpha: 1)
        }
    }
}
