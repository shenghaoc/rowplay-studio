import Foundation

/// Available renderer modes for the workout replay surface.
public enum ReplayRendererMode: String, CaseIterable, Identifiable, Sendable {
    case twoD = "2D"
    case threeD = "3D"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .twoD: "2D"
        case .threeD: "3D"
        }
    }
}
