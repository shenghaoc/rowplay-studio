import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// Seam between the scene builder and the native venue construction.
///
/// Construction failure returns `nil`, keeping the caller's procedural ground
/// enabled — the venue never partially installs.
@MainActor
enum ReplayEnvironmentInstaller {
    static func install(
        sport: Sport,
        quality: ReplayRenderQuality,
        colorScheme: ColorScheme
    ) -> Entity? {
        // Placeholder until ReplayEnvironmentBuilder lands in this change.
        nil
    }
}
