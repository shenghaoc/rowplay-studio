import RowPlayCore
import SwiftUI

@MainActor
final class AppPreferences: ObservableObject {
    @AppStorage("demoModeEnabled") var demoModeEnabled = true
    @AppStorage("reduceReplayMotion") var reduceReplayMotion = false
    @AppStorage("preferredDistanceUnit") var preferredDistanceUnit = "metric"

    var distanceUnit: DistanceUnit {
        DistanceUnit.from(preferredDistanceUnit)
    }
}
