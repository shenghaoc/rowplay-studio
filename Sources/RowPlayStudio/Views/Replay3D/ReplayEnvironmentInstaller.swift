import RealityKit
import RowPlayCore
import SwiftUI

/// Thin orchestration seam for the complete native venue. Geometry is
/// deterministic and non-failable; individual missing texture maps degrade to
/// scalar PBR in ReplayEnvironmentMaterialLibrary.
@MainActor
enum ReplayEnvironmentInstaller {
    static func install(
        sport: Sport,
        quality: ReplayRenderQuality,
        colorScheme: ColorScheme,
        layout: ReplayCourseLayout = .standard
    ) -> Entity {
        let plan = ReplayEnvironmentPlan.plan(for: sport)
        let mapping = ReplayEnvironmentPlanarMapping(layout: layout)
        let theme: ReplayEnvironmentTheme = colorScheme == .dark ? .dark : .light
        let materials = ReplayEnvironmentMaterialLibrary.shared
        let root = Entity()
        root.name = "premium-environment-\(sport.rawValue)-\(quality.rawValue)"

        let ground = ModelEntity(
            mesh: .generatePlane(
                width: mapping.extent(plan.ground.halfExtent * 2),
                depth: mapping.extent(plan.ground.halfExtent * 2)
            ),
            materials: [materials.material(
                family: plan.ground.family,
                baseColor: plan.ground.color.resolvedColor(for: theme),
                roughness: plan.ground.roughness,
                quality: quality,
                textureRepeat: plan.ground.textureRepeat,
                metallic: plan.ground.metallic
            )]
        )
        ground.name = "venue-ground"
        ground.position.y = -0.04
        root.addChild(ground)

        if sport != .bike {
            ReplayEnvironmentGeometry.addOutdoorAtmosphere(
                plan: plan,
                theme: theme,
                mapping: mapping,
                to: root
            )
        }

        let dressing = Entity()
        dressing.name = "venue-dressing-\(quality.rawValue)"
        root.addChild(dressing)

        switch plan.venue {
        case let .rower(venue):
            ReplayRowerEnvironmentBuilder.build(
                venue,
                plan: plan,
                quality: quality,
                theme: theme,
                mapping: mapping,
                materials: materials,
                into: dressing
            )
        case let .skierg(venue):
            ReplaySkiEnvironmentBuilder.build(
                venue,
                plan: plan,
                quality: quality,
                theme: theme,
                mapping: mapping,
                materials: materials,
                into: dressing
            )
        case let .bike(venue):
            ReplayBikeEnvironmentBuilder.build(
                venue,
                quality: quality,
                theme: theme,
                mapping: mapping,
                materials: materials,
                into: dressing
            )
        }
        return root
    }
}
