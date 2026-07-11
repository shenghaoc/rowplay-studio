import Combine
import Foundation
import RowPlayCore

/// Shared application preferences backed by UserDefaults.
///
/// All views that read user settings should use this model via `@EnvironmentObject`
/// rather than independent `@AppStorage` instances. The keys match the existing
/// `SettingsView` bindings to preserve any values the user has already set.
@MainActor
public final class AppPreferences: ObservableObject {
    public static let demoModeEnabledKey = "demoModeEnabled"
    public static let reduceReplayMotionKey = "reduceReplayMotion"
    public static let preferredDistanceUnitKey = "preferredDistanceUnit"

    @Published public var demoModeEnabled: Bool
    @Published public var reduceReplayMotion: Bool
    @Published public var distanceUnit: DistanceUnit

    private let defaults: UserDefaults
    private var externalCancellable: AnyCancellable?
    private var internalCancellables = Set<AnyCancellable>()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Read persisted values (or fall back to defaults).
        self.demoModeEnabled = defaults.object(forKey: Self.demoModeEnabledKey) as? Bool ?? true
        self.reduceReplayMotion = defaults.object(forKey: Self.reduceReplayMotionKey) as? Bool ?? false
        let unitString = defaults.string(forKey: Self.preferredDistanceUnitKey) ?? ""
        self.distanceUnit = DistanceUnit(rawValue: unitString) ?? .metric

        // Subscribe to external UserDefaults changes (e.g. from another process or extension).
        externalCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let newDemoMode = self.defaults.object(forKey: Self.demoModeEnabledKey) as? Bool ?? true
                if self.demoModeEnabled != newDemoMode {
                    self.demoModeEnabled = newDemoMode
                }

                let newReduceMotion = self.defaults.object(forKey: Self.reduceReplayMotionKey) as? Bool ?? false
                if self.reduceReplayMotion != newReduceMotion {
                    self.reduceReplayMotion = newReduceMotion
                }

                let unitString = self.defaults.string(forKey: Self.preferredDistanceUnitKey) ?? ""
                let newDistanceUnit = DistanceUnit(rawValue: unitString) ?? .metric
                if self.distanceUnit != newDistanceUnit {
                    self.distanceUnit = newDistanceUnit
                }
            }

        // Persist changes made through @Published bindings.
        $demoModeEnabled
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                if self.defaults.object(forKey: Self.demoModeEnabledKey) as? Bool != value {
                    self.defaults.set(value, forKey: Self.demoModeEnabledKey)
                }
            }
            .store(in: &internalCancellables)

        $reduceReplayMotion
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                if self.defaults.bool(forKey: Self.reduceReplayMotionKey) != value {
                    self.defaults.set(value, forKey: Self.reduceReplayMotionKey)
                }
            }
            .store(in: &internalCancellables)

        $distanceUnit
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                if self.defaults.string(forKey: Self.preferredDistanceUnitKey) != value.rawValue {
                    self.defaults.set(value.rawValue, forKey: Self.preferredDistanceUnitKey)
                }
            }
            .store(in: &internalCancellables)
    }
}
