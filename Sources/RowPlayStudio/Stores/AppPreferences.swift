import Combine
import Foundation
import RowPlayCore

/// Shared application preferences backed by UserDefaults.
///
/// All views that read user settings should use this model via `@EnvironmentObject`
/// rather than independent `@AppStorage` instances. The keys match the existing
/// `SettingsView` bindings to preserve any values the user has already set.
@MainActor
final class AppPreferences: ObservableObject {
    static let demoModeEnabledKey = "demoModeEnabled"
    static let reduceReplayMotionKey = "reduceReplayMotion"
    static let preferredDistanceUnitKey = "preferredDistanceUnit"

    @Published var demoModeEnabled: Bool
    @Published var reduceReplayMotion: Bool
    @Published var distanceUnit: DistanceUnit

    private let defaults: UserDefaults
    private var externalCancellable: AnyCancellable?
    private var internalCancellables = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Read persisted values (or fall back to defaults).
        self.demoModeEnabled = defaults.object(forKey: Self.demoModeEnabledKey) as? Bool ?? true
        self.reduceReplayMotion = defaults.object(forKey: Self.reduceReplayMotionKey) as? Bool ?? false
        let unitString = defaults.string(forKey: Self.preferredDistanceUnitKey) ?? ""
        self.distanceUnit = DistanceUnit(rawValue: unitString) ?? .metric

        // Subscribe to external UserDefaults changes (e.g. from SettingsView @AppStorage).
        externalCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.demoModeEnabled = self.defaults.object(forKey: Self.demoModeEnabledKey) as? Bool ?? true
                self.reduceReplayMotion = self.defaults.object(forKey: Self.reduceReplayMotionKey) as? Bool ?? false
                let unitString = self.defaults.string(forKey: Self.preferredDistanceUnitKey) ?? ""
                self.distanceUnit = DistanceUnit(rawValue: unitString) ?? .metric
            }

        // Persist changes made through @Published bindings.
        $demoModeEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Self.demoModeEnabledKey)
            }
            .store(in: &internalCancellables)

        $reduceReplayMotion
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Self.reduceReplayMotionKey)
            }
            .store(in: &internalCancellables)

        $distanceUnit
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: Self.preferredDistanceUnitKey)
            }
            .store(in: &internalCancellables)
    }

    /// The string representation for backward-compatible storage.
    var preferredDistanceUnit: String {
        get { distanceUnit.rawValue }
        set { distanceUnit = DistanceUnit(rawValue: newValue) ?? .metric }
    }
}
