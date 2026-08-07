import Foundation
import RowPlayCore

/// QA-only, bounded recorder for staged replay acceptance scenarios.
///
/// Records at most 600 steady-state samples. Emits only when acceptance mode is
/// active. Never stores workout IDs, tokens, account data, stroke values, or
/// absolute private paths.
struct ReplayAcceptanceMetrics: Equatable, Sendable {
    static let maximumSampleCount = 600

    struct Sample: Equatable, Sendable {
        let frameIntervalMilliseconds: Double
        let sceneUpdateDurationMilliseconds: Double
    }

    struct Summary: Equatable, Sendable {
        let sampleCount: Int
        let averageFrameIntervalMilliseconds: Double
        let p50FrameIntervalMilliseconds: Double
        let p95FrameIntervalMilliseconds: Double
        let p99FrameIntervalMilliseconds: Double
        let worstFrameIntervalMilliseconds: Double
        let averageSceneUpdateDurationMilliseconds: Double
        let p50SceneUpdateDurationMilliseconds: Double
        let p95SceneUpdateDurationMilliseconds: Double
        let p99SceneUpdateDurationMilliseconds: Double
        let worstSceneUpdateDurationMilliseconds: Double
        let samplesAboveBudget: Int
        let selectedQuality: String
        let effectiveQuality: String
        let adaptiveDegradationCount: Int
        let sceneRebuildCount: Int
        let fallbackCount: Int
        let fallbackCategory: String
        let firstSceneReadyLatencyMilliseconds: Double?
        let firstAthleteReadyLatencyMilliseconds: Double?
        let livePresent: Bool
        let rivalPresent: Bool

        func jsonObject() -> [String: Any] {
            var object: [String: Any] = [
                "sampleCount": sampleCount,
                "averageFrameIntervalMilliseconds": averageFrameIntervalMilliseconds,
                "p50FrameIntervalMilliseconds": p50FrameIntervalMilliseconds,
                "p95FrameIntervalMilliseconds": p95FrameIntervalMilliseconds,
                "p99FrameIntervalMilliseconds": p99FrameIntervalMilliseconds,
                "worstFrameIntervalMilliseconds": worstFrameIntervalMilliseconds,
                "averageSceneUpdateDurationMilliseconds": averageSceneUpdateDurationMilliseconds,
                "p50SceneUpdateDurationMilliseconds": p50SceneUpdateDurationMilliseconds,
                "p95SceneUpdateDurationMilliseconds": p95SceneUpdateDurationMilliseconds,
                "p99SceneUpdateDurationMilliseconds": p99SceneUpdateDurationMilliseconds,
                "worstSceneUpdateDurationMilliseconds": worstSceneUpdateDurationMilliseconds,
                "samplesAboveBudget": samplesAboveBudget,
                "selectedQuality": selectedQuality,
                "effectiveQuality": effectiveQuality,
                "adaptiveDegradationCount": adaptiveDegradationCount,
                "sceneRebuildCount": sceneRebuildCount,
                "fallbackCount": fallbackCount,
                "fallbackCategory": fallbackCategory,
                "livePresent": livePresent,
                "rivalPresent": rivalPresent,
            ]
            if let firstSceneReadyLatencyMilliseconds {
                object["firstSceneReadyLatencyMilliseconds"] = firstSceneReadyLatencyMilliseconds
            }
            if let firstAthleteReadyLatencyMilliseconds {
                object["firstAthleteReadyLatencyMilliseconds"] = firstAthleteReadyLatencyMilliseconds
            }
            return object
        }
    }

    private var frameIntervals: [Double] = []
    private var sceneUpdates: [Double] = []
    private var samplesAboveBudget = 0
    private(set) var selectedQuality: ReplayRenderQuality = .medium
    private(set) var effectiveQuality: ReplayRenderQuality = .medium
    private(set) var adaptiveDegradationCount = 0
    private(set) var sceneRebuildCount = 0
    private(set) var fallbackCount = 0
    private(set) var fallbackCategory = "none"
    private(set) var firstSceneReadyLatencyMilliseconds: Double?
    private(set) var firstAthleteReadyLatencyMilliseconds: Double?
    private(set) var livePresent = true
    private(set) var rivalPresent = false
    private(set) var isEnabled = false

    var sampleCount: Int { frameIntervals.count }

    mutating func enable(
        selectedQuality: ReplayRenderQuality,
        effectiveQuality: ReplayRenderQuality,
        livePresent: Bool,
        rivalPresent: Bool
    ) {
        reset()
        isEnabled = true
        self.selectedQuality = selectedQuality
        self.effectiveQuality = effectiveQuality
        self.livePresent = livePresent
        self.rivalPresent = rivalPresent
    }

    mutating func disable() {
        reset()
        isEnabled = false
    }

    mutating func reset() {
        frameIntervals.removeAll(keepingCapacity: true)
        sceneUpdates.removeAll(keepingCapacity: true)
        samplesAboveBudget = 0
        adaptiveDegradationCount = 0
        sceneRebuildCount = 0
        fallbackCount = 0
        fallbackCategory = "none"
        firstSceneReadyLatencyMilliseconds = nil
        firstAthleteReadyLatencyMilliseconds = nil
        livePresent = true
        rivalPresent = false
        selectedQuality = .medium
        effectiveQuality = .medium
    }

    /// Records one paired production sample when acceptance mode is enabled.
    mutating func record(
        frameIntervalMilliseconds: Double,
        sceneUpdateDurationMilliseconds: Double,
        activeBudgetMilliseconds: Double
    ) {
        guard isEnabled else { return }
        guard ReplayPerformanceGovernor.isAcceptedFrameInterval(frameIntervalMilliseconds),
              sceneUpdateDurationMilliseconds.isFinite,
              sceneUpdateDurationMilliseconds >= 0,
              activeBudgetMilliseconds.isFinite,
              activeBudgetMilliseconds > 0 else {
            return
        }
        guard sampleCount < Self.maximumSampleCount else { return }

        frameIntervals.append(frameIntervalMilliseconds)
        sceneUpdates.append(sceneUpdateDurationMilliseconds)
        if frameIntervalMilliseconds > activeBudgetMilliseconds {
            samplesAboveBudget += 1
        }
    }

    mutating func noteSelectedQuality(_ quality: ReplayRenderQuality) {
        guard isEnabled else { return }
        selectedQuality = quality
    }

    mutating func noteEffectiveQuality(_ quality: ReplayRenderQuality) {
        guard isEnabled else { return }
        effectiveQuality = quality
    }

    mutating func noteAdaptiveDegradation() {
        guard isEnabled else { return }
        adaptiveDegradationCount += 1
    }

    mutating func noteSceneRebuild() {
        guard isEnabled else { return }
        sceneRebuildCount += 1
    }

    mutating func noteFallback(category: String) {
        guard isEnabled else { return }
        fallbackCount += 1
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        fallbackCategory = trimmed.isEmpty ? "unknown" : String(trimmed.prefix(64))
    }

    mutating func noteFirstSceneReadyLatencyMilliseconds(_ value: Double) {
        guard isEnabled, firstSceneReadyLatencyMilliseconds == nil else { return }
        guard value.isFinite, value >= 0 else { return }
        firstSceneReadyLatencyMilliseconds = value
    }

    mutating func noteFirstAthleteReadyLatencyMilliseconds(_ value: Double) {
        guard isEnabled, firstAthleteReadyLatencyMilliseconds == nil else { return }
        guard value.isFinite, value >= 0 else { return }
        firstAthleteReadyLatencyMilliseconds = value
    }

    mutating func notePresence(live: Bool, rival: Bool) {
        guard isEnabled else { return }
        livePresent = live
        rivalPresent = rival
    }

    func makeSummary() -> Summary {
        Summary(
            sampleCount: sampleCount,
            averageFrameIntervalMilliseconds: average(of: frameIntervals),
            p50FrameIntervalMilliseconds: percentile(frameIntervals, 0.50),
            p95FrameIntervalMilliseconds: percentile(frameIntervals, 0.95),
            p99FrameIntervalMilliseconds: percentile(frameIntervals, 0.99),
            worstFrameIntervalMilliseconds: frameIntervals.max() ?? 0,
            averageSceneUpdateDurationMilliseconds: average(of: sceneUpdates),
            p50SceneUpdateDurationMilliseconds: percentile(sceneUpdates, 0.50),
            p95SceneUpdateDurationMilliseconds: percentile(sceneUpdates, 0.95),
            p99SceneUpdateDurationMilliseconds: percentile(sceneUpdates, 0.99),
            worstSceneUpdateDurationMilliseconds: sceneUpdates.max() ?? 0,
            samplesAboveBudget: samplesAboveBudget,
            selectedQuality: selectedQuality.rawValue,
            effectiveQuality: effectiveQuality.rawValue,
            adaptiveDegradationCount: adaptiveDegradationCount,
            sceneRebuildCount: sceneRebuildCount,
            fallbackCount: fallbackCount,
            fallbackCategory: fallbackCategory,
            firstSceneReadyLatencyMilliseconds: firstSceneReadyLatencyMilliseconds,
            firstAthleteReadyLatencyMilliseconds: firstAthleteReadyLatencyMilliseconds,
            livePresent: livePresent,
            rivalPresent: rivalPresent
        )
    }

    /// Deterministic synthetic injection for unit tests.
    mutating func recordSyntheticSamples(
        frameIntervals: [Double],
        sceneUpdates: [Double],
        budgetMilliseconds: Double
    ) {
        for index in frameIntervals.indices {
            let scene = index < sceneUpdates.count ? sceneUpdates[index] : 0
            record(
                frameIntervalMilliseconds: frameIntervals[index],
                sceneUpdateDurationMilliseconds: scene,
                activeBudgetMilliseconds: budgetMilliseconds
            )
        }
    }

    private func average(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Nearest-rank percentile for a finite sample set. Empty sets yield 0.
    private func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }
        let clamped = min(1, max(0, fraction))
        let rank = Int(ceil(clamped * Double(sorted.count))) - 1
        let index = min(sorted.count - 1, max(0, rank))
        return sorted[index]
    }
}

/// Process-local acceptance metrics bridge used by the 3D performance path.
@MainActor
enum ReplayAcceptanceMetricsStore {
    private(set) static var metrics = ReplayAcceptanceMetrics()
    private(set) static var scenarioID: String?
    private static var didEmitSummary = false

    static func beginScenario(
        scenarioID: String?,
        selectedQuality: ReplayRenderQuality,
        effectiveQuality: ReplayRenderQuality,
        livePresent: Bool,
        rivalPresent: Bool
    ) {
        self.scenarioID = scenarioID
        didEmitSummary = false
        metrics.enable(
            selectedQuality: selectedQuality,
            effectiveQuality: effectiveQuality,
            livePresent: livePresent,
            rivalPresent: rivalPresent
        )
    }

    static func endAndEmit(outputDirectory: String?) {
        guard metrics.isEnabled else { return }
        let summary = metrics.makeSummary()
        // Always refresh the on-disk summary so a late kill still captures the
        // latest bounded window. Log the privacy-safe event only once.
        if !didEmitSummary {
            didEmitSummary = true
            ReplayPerformanceTelemetry.recordAcceptanceSummary(
                summary,
                scenarioID: scenarioID
            )
        }
        if let outputDirectory {
            writeSummaryJSON(summary, to: outputDirectory)
        }
    }

    static func recordPairedSample(
        frameIntervalMilliseconds: Double,
        sceneUpdateDurationMilliseconds: Double,
        activeBudgetMilliseconds: Double
    ) {
        metrics.record(
            frameIntervalMilliseconds: frameIntervalMilliseconds,
            sceneUpdateDurationMilliseconds: sceneUpdateDurationMilliseconds,
            activeBudgetMilliseconds: activeBudgetMilliseconds
        )
    }

    /// Test/profile seam: snapshot current metrics without disabling collection.
    static func currentSummary() -> ReplayAcceptanceMetrics.Summary {
        metrics.makeSummary()
    }

    static func noteAdaptiveDegradation(effectiveQuality: ReplayRenderQuality) {
        metrics.noteAdaptiveDegradation()
        metrics.noteEffectiveQuality(effectiveQuality)
    }

    static func noteSceneRebuild() {
        metrics.noteSceneRebuild()
    }

    static func noteFallback(category: String) {
        metrics.noteFallback(category: category)
    }

    static func noteFirstSceneReadyLatencyMilliseconds(_ value: Double) {
        metrics.noteFirstSceneReadyLatencyMilliseconds(value)
    }

    static func noteFirstAthleteReadyLatencyMilliseconds(_ value: Double) {
        metrics.noteFirstAthleteReadyLatencyMilliseconds(value)
    }

    static func notePresence(live: Bool, rival: Bool) {
        metrics.notePresence(live: live, rival: rival)
    }

    static func resetForTests() {
        metrics = ReplayAcceptanceMetrics()
        scenarioID = nil
        didEmitSummary = false
    }

    private static func writeSummaryJSON(
        _ summary: ReplayAcceptanceMetrics.Summary,
        to outputDirectory: String
    ) {
        let url = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
            let fileURL = url.appendingPathComponent("acceptance-metrics.json")
            let object = summary.jsonObject()
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Fixed public category only; never log the private path.
            ReplayPerformanceTelemetry.recordAcceptanceWriteFailure()
        }
    }
}
