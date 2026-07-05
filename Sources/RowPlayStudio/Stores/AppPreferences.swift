import Combine
import Foundation
import RowPlayCore

@MainActor
final class AppPreferences: ObservableObject {
    static let demoModeEnabledKey = "demoModeEnabled"
    static let reduceReplayMotionKey = "reduceReplayMotion"
    static let preferredDistanceUnitKey = "preferredDistanceUnit"

    @Published var demoModeEnabled: Bool {
        didSet {
            defaults.set(demoModeEnabled, forKey: Self.demoModeEnabledKey)
        }
    }
    @Published var reduceReplayMotion: Bool {
        didSet {
            defaults.set(reduceReplayMotion, forKey: Self.reduceReplayMotionKey)
        }
    }
    @Published var preferredDistanceUnit: String {
        didSet {
            let normalized = DistanceUnit.from(preferredDistanceUnit).rawValue
            if preferredDistanceUnit != normalized {
                preferredDistanceUnit = normalized
                return
            }
            defaults.set(normalized, forKey: Self.preferredDistanceUnitKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        demoModeEnabled = defaults.object(forKey: Self.demoModeEnabledKey) as? Bool ?? true
        reduceReplayMotion = defaults.object(forKey: Self.reduceReplayMotionKey) as? Bool ?? false
        preferredDistanceUnit = DistanceUnit.from(defaults.string(forKey: Self.preferredDistanceUnitKey) ?? "").rawValue
    }

    var distanceUnit: DistanceUnit {
        DistanceUnit.from(preferredDistanceUnit)
    }
}
