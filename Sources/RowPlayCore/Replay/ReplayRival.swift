import Foundation

/// Kind of rival used in a replay race.
public enum ReplayRivalKind: String, Codable, Sendable, Equatable, CaseIterable {
    case session
    case constantPace
    case importedFile
}

/// Portable rival model for past-session, constant-pace, and imported traces.
///
/// Does not store tokens, full filesystem paths, hardware identifiers, or account data.
/// Imported filenames (last path component only) may be shown in local UI via
/// ``localFileName`` but must never enter logs or exported race reports.
public struct ReplayRival: Equatable, Identifiable, Sendable {
    /// Stable identity for SwiftUI and 3D scene identity.
    public var id: String
    public var kind: ReplayRivalKind
    /// Local display label (may include a session date or pace string).
    public var displayLabel: String
    public var strokes: [Stroke]
    /// True only for genuine Concept2 stroke-by-stroke traces.
    /// Constant-pace and imported rivals are false so 3D uses fallback articulation.
    public var hasGenuineStrokeData: Bool
    /// Present for past-session rivals.
    public var sessionWorkoutID: Int?
    /// Present for constant-pace rivals (seconds per 500 m).
    public var targetPace: TimeInterval?
    /// Optional last-path-component filename for local UI only. Never export or log.
    public var localFileName: String?

    public init(
        id: String,
        kind: ReplayRivalKind,
        displayLabel: String,
        strokes: [Stroke],
        hasGenuineStrokeData: Bool,
        sessionWorkoutID: Int? = nil,
        targetPace: TimeInterval? = nil,
        localFileName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayLabel = displayLabel
        self.strokes = strokes
        self.hasGenuineStrokeData = hasGenuineStrokeData
        self.sessionWorkoutID = sessionWorkoutID
        self.targetPace = targetPace
        self.localFileName = localFileName
    }
}
