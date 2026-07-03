import Foundation

/// Sport-specific display theme for replay rendering.
public struct ReplaySportTheme: Equatable, Sendable {
    public var label: String
    /// Word for the per-minute cadence metric.
    public var cadenceUnit: String

    public init(label: String, cadenceUnit: String) {
        self.label = label
        self.cadenceUnit = cadenceUnit
    }
}

/// Machine accent color in hex for canvas rendering.
public struct MachineColor: Equatable, Sendable {
    public var light: String
    public var dark: String

    public init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }
}

public enum ReplaySportThemeLookup {
    /// Returns the display theme for a sport.
    public static func theme(for sport: Sport) -> ReplaySportTheme {
        switch sport {
        case .rower:
            ReplaySportTheme(label: "RowErg", cadenceUnit: "spm")
        case .skierg:
            ReplaySportTheme(label: "SkiErg", cadenceUnit: "spm")
        case .bike:
            ReplaySportTheme(label: "BikeErg", cadenceUnit: "rpm")
        }
    }

    /// Canvas hex colors matching the web app's --m-* CSS variables.
    public static func machineColor(for sport: Sport) -> MachineColor {
        switch sport {
        case .rower:
            MachineColor(light: "#2b5e78", dark: "#5a8aaa")
        case .skierg:
            MachineColor(light: "#2e8c7e", dark: "#5aaa9a")
        case .bike:
            MachineColor(light: "#6257b8", dark: "#8a7ad0")
        }
    }
}
