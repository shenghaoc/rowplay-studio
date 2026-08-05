import Foundation
import RowPlayCore

/// Launch-only configuration for deterministic staged-app replay acceptance.
///
/// Active exclusively when `ROWPLAY_REPLAY_ACCEPTANCE=1`. Invalid environment
/// values fail loudly with fixed public diagnostics. Values never persist into
/// normal user preferences.
struct ReplayAcceptanceConfiguration: Equatable, Sendable {
    enum Diagnostic: String, Error, Equatable, Sendable {
        case missingAcceptanceFlag = "ROWPLAY_REPLAY_ACCEPTANCE must be 1 to enable acceptance mode"
        case invalidSport = "ROWPLAY_QA_SPORT must be rower|skierg|bike"
        case invalidRenderer = "ROWPLAY_QA_RENDERER must be 2d|3d"
        case invalidQuality = "ROWPLAY_QA_QUALITY must be low|medium|high|ultra"
        case invalidCamera = "ROWPLAY_QA_CAMERA must be chase|side|overhead|orbit"
        case invalidTheme = "ROWPLAY_QA_THEME must be light|dark"
        case invalidRival = "ROWPLAY_QA_RIVAL must be none|session|pace"
        case invalidTime = "ROWPLAY_QA_TIME must be a finite non-negative number of seconds"
        case invalidReducedMotion = "ROWPLAY_QA_REDUCED_MOTION must be 0|1"
        case invalidWidth = "ROWPLAY_QA_WIDTH must be a finite window width within 800...4096"
        case invalidHeight = "ROWPLAY_QA_HEIGHT must be a finite window height within 600...2160"
        case invalidOutput = "ROWPLAY_QA_OUTPUT must be a non-empty local directory path when supplied"
    }

    enum Theme: String, Equatable, Sendable, CaseIterable {
        case light
        case dark
    }

    enum RivalMode: String, Equatable, Sendable, CaseIterable {
        case none
        case session
        case pace
    }

    static let acceptanceEnvironmentKey = "ROWPLAY_REPLAY_ACCEPTANCE"
    static let minimumWindowWidth: Double = 800
    static let maximumWindowWidth: Double = 4_096
    static let minimumWindowHeight: Double = 600
    static let maximumWindowHeight: Double = 2_160

    /// Stable demo workout IDs used exclusively by acceptance mode.
    static let rowerDemoWorkoutID = 1001
    static let skiergDemoWorkoutID = 1003
    static let bikeDemoWorkoutID = 1004

    let sport: Sport
    let rendererMode: ReplayRendererMode
    let quality: ReplayRenderQuality
    let camera: ReplayCameraPreset
    let theme: Theme
    let rival: RivalMode
    let timeSeconds: TimeInterval
    let reducedMotion: Bool
    let windowWidth: Double
    let windowHeight: Double
    /// Local metrics directory when supplied. Never logged as a private path.
    let outputDirectory: String?
    /// Public catalog token threaded to telemetry. Not a private path.
    let scenarioID: String?

    var demoWorkoutID: Int {
        Self.demoWorkoutID(for: sport)
    }

    static func demoWorkoutID(for sport: Sport) -> Int {
        switch sport {
        case .rower: rowerDemoWorkoutID
        case .skierg: skiergDemoWorkoutID
        case .bike: bikeDemoWorkoutID
        }
    }

    static func isAcceptanceEnabled(in environment: [String: String]) -> Bool {
        environment[acceptanceEnvironmentKey] == "1"
    }

    /// Parses acceptance configuration when the launch flag is set.
    ///
    /// Returns `nil` when acceptance mode is inactive. Throws a fixed public
    /// diagnostic for any invalid value while the flag is active.
    static func parse(from environment: [String: String]) throws -> ReplayAcceptanceConfiguration? {
        guard isAcceptanceEnabled(in: environment) else {
            return nil
        }

        let sport = try parseSport(environment["ROWPLAY_QA_SPORT"])
        let rendererMode = try parseRenderer(environment["ROWPLAY_QA_RENDERER"])
        let quality = try parseQuality(environment["ROWPLAY_QA_QUALITY"])
        let camera = try parseCamera(environment["ROWPLAY_QA_CAMERA"])
        let theme = try parseTheme(environment["ROWPLAY_QA_THEME"])
        let rival = try parseRival(environment["ROWPLAY_QA_RIVAL"])
        let timeSeconds = try parseTime(environment["ROWPLAY_QA_TIME"])
        let reducedMotion = try parseReducedMotion(environment["ROWPLAY_QA_REDUCED_MOTION"])
        let width = try parseWindowDimension(
            environment["ROWPLAY_QA_WIDTH"],
            default: 1_280,
            minimum: minimumWindowWidth,
            maximum: maximumWindowWidth,
            invalid: .invalidWidth
        )
        let height = try parseWindowDimension(
            environment["ROWPLAY_QA_HEIGHT"],
            default: 800,
            minimum: minimumWindowHeight,
            maximum: maximumWindowHeight,
            invalid: .invalidHeight
        )
        let outputDirectory = try parseOutputDirectory(environment["ROWPLAY_QA_OUTPUT"])
        let scenarioID = parseScenarioID(environment["ROWPLAY_QA_SCENARIO"])

        return ReplayAcceptanceConfiguration(
            sport: sport,
            rendererMode: rendererMode,
            quality: quality,
            camera: camera,
            theme: theme,
            rival: rival,
            timeSeconds: timeSeconds,
            reducedMotion: reducedMotion,
            windowWidth: width,
            windowHeight: height,
            outputDirectory: outputDirectory,
            scenarioID: scenarioID
        )
    }

    /// Builds a finite, Sendable initial configuration for `ReplayView`.
    func makeViewConfiguration() -> ReplayViewInitialConfiguration {
        ReplayViewInitialConfiguration(
            rendererMode: rendererMode,
            cameraPreset: camera,
            quality: quality,
            seekTime: timeSeconds,
            rivalMode: rival,
            forceReducedMotion: reducedMotion,
            persistsQualityPreference: false,
            autoPlay: !reducedMotion
        )
    }

    private static func parseSport(_ raw: String?) throws -> Sport {
        switch (raw ?? "rower").lowercased() {
        case "rower": return .rower
        case "skierg": return .skierg
        case "bike": return .bike
        default: throw Diagnostic.invalidSport
        }
    }

    private static func parseRenderer(_ raw: String?) throws -> ReplayRendererMode {
        switch (raw ?? "3d").lowercased() {
        case "2d": return .twoD
        case "3d": return .threeD
        default: throw Diagnostic.invalidRenderer
        }
    }

    private static func parseQuality(_ raw: String?) throws -> ReplayRenderQuality {
        guard let quality = ReplayRenderQuality(rawValue: (raw ?? "medium").lowercased()) else {
            throw Diagnostic.invalidQuality
        }
        return quality
    }

    private static func parseCamera(_ raw: String?) throws -> ReplayCameraPreset {
        guard let camera = ReplayCameraPreset(rawValue: (raw ?? "chase").lowercased()) else {
            throw Diagnostic.invalidCamera
        }
        return camera
    }

    private static func parseTheme(_ raw: String?) throws -> Theme {
        guard let theme = Theme(rawValue: (raw ?? "dark").lowercased()) else {
            throw Diagnostic.invalidTheme
        }
        return theme
    }

    private static func parseRival(_ raw: String?) throws -> RivalMode {
        guard let rival = RivalMode(rawValue: (raw ?? "none").lowercased()) else {
            throw Diagnostic.invalidRival
        }
        return rival
    }

    private static func parseTime(_ raw: String?) throws -> TimeInterval {
        let value = raw ?? "12"
        guard let parsed = Double(value), parsed.isFinite, parsed >= 0 else {
            throw Diagnostic.invalidTime
        }
        return parsed
    }

    private static func parseReducedMotion(_ raw: String?) throws -> Bool {
        switch raw ?? "0" {
        case "0": return false
        case "1": return true
        default: throw Diagnostic.invalidReducedMotion
        }
    }

    private static func parseWindowDimension(
        _ raw: String?,
        default defaultValue: Double,
        minimum: Double,
        maximum: Double,
        invalid: Diagnostic
    ) throws -> Double {
        let value: Double
        if let raw {
            guard let parsed = Double(raw), parsed.isFinite else {
                throw invalid
            }
            value = parsed
        } else {
            value = defaultValue
        }
        guard value >= minimum, value <= maximum else {
            throw invalid
        }
        return value
    }

    private static func parseOutputDirectory(_ raw: String?) throws -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Diagnostic.invalidOutput
        }
        return trimmed
    }

    private static func parseScenarioID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(128))
    }
}

/// Defaulted initial state for `ReplayView` that keeps normal call sites
/// source-compatible. Acceptance mode supplies every field; production routes
/// leave the default empty configuration.
struct ReplayViewInitialConfiguration: Equatable, Sendable {
    var rendererMode: ReplayRendererMode?
    var cameraPreset: ReplayCameraPreset?
    var quality: ReplayRenderQuality?
    var seekTime: TimeInterval?
    var rivalMode: ReplayAcceptanceConfiguration.RivalMode?
    var forceReducedMotion: Bool?
    /// When false, quality is applied only for the session and never written
    /// into `AppPreferences`.
    var persistsQualityPreference: Bool
    /// Acceptance runs start playback so performance samples accumulate.
    var autoPlay: Bool

    static let production = ReplayViewInitialConfiguration(
        rendererMode: nil,
        cameraPreset: nil,
        quality: nil,
        seekTime: nil,
        rivalMode: nil,
        forceReducedMotion: nil,
        persistsQualityPreference: true,
        autoPlay: false
    )

    init(
        rendererMode: ReplayRendererMode? = nil,
        cameraPreset: ReplayCameraPreset? = nil,
        quality: ReplayRenderQuality? = nil,
        seekTime: TimeInterval? = nil,
        rivalMode: ReplayAcceptanceConfiguration.RivalMode? = nil,
        forceReducedMotion: Bool? = nil,
        persistsQualityPreference: Bool = true,
        autoPlay: Bool = false
    ) {
        self.rendererMode = rendererMode
        self.cameraPreset = cameraPreset
        self.quality = quality
        self.seekTime = seekTime
        self.rivalMode = rivalMode
        self.forceReducedMotion = forceReducedMotion
        self.persistsQualityPreference = persistsQualityPreference
        self.autoPlay = autoPlay
    }
}
