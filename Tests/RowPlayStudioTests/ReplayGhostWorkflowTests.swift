import CoreGraphics
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayGhostWorkflowTests: XCTestCase {
    func testReplayViewConstructsWithAndWithoutPastSessionCandidates() {
        guard let detail = DemoWorkoutLibrary.details.first else {
            return XCTFail("Demo data must include a replayable workout")
        }

        _ = ReplayView(detail: detail)
        _ = ReplayView(detail: detail, ghostCandidates: [detail], initialGhostID: detail.id)
        _ = ReplayView(detail: detail, ghostCandidates: [detail], initialGhostID: -1)
    }

    func testPrimaryContentIdentityChangesWithTraceAndRaceSemantics() {
        guard let detail = DemoWorkoutLibrary.details.first,
              !detail.strokes.isEmpty else {
            return XCTFail("Demo data must include replay strokes")
        }
        let original = ReplayPrimaryContentIdentity(detail: detail)
        var changedTrace = detail
        changedTrace.strokes[changedTrace.strokes.count - 1].d += 1
        var changedTarget = detail
        changedTarget.workout.time += 1

        XCTAssertNotEqual(ReplayPrimaryContentIdentity(detail: changedTrace), original)
        XCTAssertNotEqual(ReplayPrimaryContentIdentity(detail: changedTarget), original)
        XCTAssertEqual(ReplayPrimaryContentIdentity(detail: detail), original)
    }

    func testTelemetryIntegerFormattingRejectsExtremeFiniteValues() {
        XCTAssertEqual(ReplayTelemetryFormatting.roundedInteger(28.4), "28")
        XCTAssertEqual(ReplayTelemetryFormatting.roundedInteger(1e308), "-")
        XCTAssertEqual(ReplayTelemetryFormatting.roundedInteger(.infinity), "-")
    }

    func testSessionRivalReconciliationRefreshesChangedTraceForSameWorkoutID() throws {
        guard let detail = DemoWorkoutLibrary.details.first,
              detail.strokes.count >= 2 else {
            return XCTFail("Demo data must include a replayable workout")
        }
        let originalRival = try XCTUnwrap(ReplayRivalFactory.makeSessionRival(from: detail))
        var refreshedDetail = detail
        refreshedDetail.strokes[refreshedDetail.strokes.count - 1].d += 1

        let reconciled = try XCTUnwrap(ReplaySessionRivalReconciler.reconcile(
            activeRival: originalRival,
            candidates: [refreshedDetail]
        ))

        XCTAssertEqual(reconciled.sessionWorkoutID, originalRival.sessionWorkoutID)
        XCTAssertEqual(reconciled.strokes, refreshedDetail.strokes)
        XCTAssertNotEqual(reconciled.id, originalRival.id)
    }

    func testSessionRivalReconciliationRemovesMissingWorkout() throws {
        guard let detail = DemoWorkoutLibrary.details.first else {
            return XCTFail("Demo data must include a replayable workout")
        }
        let originalRival = try XCTUnwrap(ReplayRivalFactory.makeSessionRival(from: detail))

        let reconciled = ReplaySessionRivalReconciler.reconcile(
            activeRival: originalRival,
            candidates: []
        )

        XCTAssertNil(reconciled)
    }

    func testSessionRivalReconciliationPreservesImportedSelection() {
        let imported = ReplayRival(
            id: "file-user-import",
            kind: .importedFile,
            displayLabel: "Imported",
            strokes: [
                Stroke(t: 0, d: 0, pace: 120, cadence: 28, watts: 200),
                Stroke(t: 10, d: 50, pace: 120, cadence: 28, watts: 200),
            ],
            hasGenuineStrokeData: false,
            localFileName: "rival.csv"
        )

        XCTAssertEqual(
            ReplaySessionRivalReconciler.reconcile(activeRival: imported, candidates: []),
            imported
        )
    }

    func testFinishGateAcceptsZeroSecondDistanceFinishButRequiresPositiveTimeHorizon() {
        XCTAssertTrue(ReplayFinishGate.shouldShowVerdict(
            axis: .distance,
            playerFinishTime: 0,
            workoutTargetDuration: 0,
            replayDuration: 0,
            playbackTime: 0
        ))
        XCTAssertFalse(ReplayFinishGate.shouldShowVerdict(
            axis: .time,
            playerFinishTime: 0,
            workoutTargetDuration: 0,
            replayDuration: 0,
            playbackTime: 0
        ))
        XCTAssertFalse(ReplayFinishGate.shouldShowVerdict(
            axis: .time,
            playerFinishTime: 0,
            workoutTargetDuration: 10,
            replayDuration: 0,
            playbackTime: 9.999
        ))
        XCTAssertTrue(ReplayFinishGate.shouldShowVerdict(
            axis: .time,
            playerFinishTime: 0,
            workoutTargetDuration: 10,
            replayDuration: 0,
            playbackTime: 10
        ))
        XCTAssertFalse(ReplayFinishGate.shouldShowVerdict(
            axis: .time,
            playerFinishTime: 600,
            workoutTargetDuration: 600,
            replayDuration: 599.5,
            playbackTime: 599.499
        ))
        XCTAssertTrue(ReplayFinishGate.shouldShowVerdict(
            axis: .time,
            playerFinishTime: 600,
            workoutTargetDuration: 600,
            replayDuration: 599.5,
            playbackTime: 599.5
        ))
    }

    func testGhostPathUsesGhostElapsedTimeWithPlayerChartScale() {
        guard let detail = DemoWorkoutLibrary.details.first else {
            return XCTFail("Demo data must include a replayable workout")
        }
        let playerStrokes = [
            Stroke(t: 10, d: 0, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 20, d: 100, pace: 120, cadence: 28, watts: 200),
        ]
        let ghostStrokes = [
            Stroke(t: 30, d: 0, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 40, d: 100, pace: 120, cadence: 28, watts: 200),
        ]

        let path = ReplayView(detail: detail).makeGhostStrokePath(
            ghostStrokes: ghostStrokes,
            playerStrokes: playerStrokes,
            size: CGSize(width: 100, height: 100)
        )

        let bounds = path.cgPath.boundingBoxOfPath
        XCTAssertEqual(bounds.minX, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 100, accuracy: 0.001)
    }

    func testGhostPathIsEmptyWithoutEnoughStrokeData() {
        guard let detail = DemoWorkoutLibrary.details.first else {
            return XCTFail("Demo data must include a replayable workout")
        }
        let stroke = Stroke(t: 10, d: 0, pace: 120, cadence: 28, watts: 200)

        let path = ReplayView(detail: detail).makeGhostStrokePath(
            ghostStrokes: [stroke],
            playerStrokes: [stroke, Stroke(t: 20, d: 100, pace: 120, cadence: 28, watts: 200)],
            size: CGSize(width: 100, height: 100)
        )

        XCTAssertTrue(path.isEmpty)
    }

    func testGhostPathInterpolatesLongerRivalAtPlayerFinish() {
        let ghostStrokes = [
            Stroke(t: 20, d: 0, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 25, d: 60, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 35, d: 180, pace: 120, cadence: 28, watts: 200),
        ]

        let samples = ReplayRivalPathBuilder.samples(
            ghostStrokes: ghostStrokes,
            playerDuration: 10,
            maximumPointCount: 100
        )

        XCTAssertEqual(samples.last?.elapsed, 10)
        XCTAssertEqual(samples.last?.distance ?? -1, 120, accuracy: 0.001)
        XCTAssertTrue(samples.allSatisfy { $0.elapsed <= 10 })
    }

    func testGhostPathHoldsShorterRivalAtPlayerFinish() {
        let ghostStrokes = [
            Stroke(t: 0, d: 0, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 5, d: 50, pace: 120, cadence: 28, watts: 200),
        ]

        let samples = ReplayRivalPathBuilder.samples(
            ghostStrokes: ghostStrokes,
            playerDuration: 10,
            maximumPointCount: 100
        )

        XCTAssertEqual(samples.map(\.elapsed), [0, 5, 10])
        XCTAssertEqual(samples.last?.distance, 50)
    }

    func testGhostPathVisualSamplesAreBoundedAndKeepEndpoints() {
        let ghostStrokes = (0...5_000).map { index in
            Stroke(
                t: Double(index),
                d: Double(index) * 2,
                pace: 120,
                cadence: 28,
                watts: 200
            )
        }

        let samples = ReplayRivalPathBuilder.samples(
            ghostStrokes: ghostStrokes,
            playerDuration: 5_000,
            maximumPointCount: 25
        )

        XCTAssertEqual(samples.count, 25)
        XCTAssertEqual(samples.first, ReplayRivalPathBuilder.Sample(elapsed: 0, distance: 0))
        XCTAssertEqual(samples.last, ReplayRivalPathBuilder.Sample(elapsed: 5_000, distance: 10_000))
        XCTAssertEqual(
            ReplayRivalPathBuilder.pointLimit(for: CGSize(width: 10_000, height: 100)),
            2_048
        )
    }

    func testConstantPaceRivalCreatesTwoStrokeTrace() {
        guard let detail = DemoWorkoutLibrary.details.first else {
            return XCTFail("Demo data must include a replayable workout")
        }
        let rival = ReplayRivalFactory.makeConstantPaceRival(
            pacePer500m: 120,
            player: detail.workout
        )
        XCTAssertNotNil(rival)
        XCTAssertEqual(rival?.kind, .constantPace)
        XCTAssertEqual(rival?.hasGenuineStrokeData, false)
        XCTAssertEqual(rival?.strokes.count, 2)
    }

    func testImportedRivalFactoryFromParsedCSV() throws {
        let csv = "time,distance\n0,0\n10,50\n20,100\n"
        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "r.csv")
        let rival = ReplayRivalFactory.makeImportedRival(strokes: parsed.strokes, fileName: parsed.fileName)
        XCTAssertNotNil(rival)
        XCTAssertEqual(rival?.kind, .importedFile)
        XCTAssertEqual(rival?.hasGenuineStrokeData, false)
        XCTAssertEqual(rival?.localFileName, "r.csv")
    }

    func testImportLoaderReadsAndParsesSelectedFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rowplay-rival-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("time,distance\n0,0\n10,50\n".utf8).write(to: url)

        let rival = try ReplayRivalImportLoader.loadRival(from: url, fileName: url.lastPathComponent)

        XCTAssertEqual(rival.kind, .importedFile)
        XCTAssertEqual(rival.strokes.count, 2)
        XCTAssertEqual(rival.localFileName, url.lastPathComponent)
    }

    func testSecurityScopedImportWrapperReadsAndParsesSelectedFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rowplay-rival-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("time,distance\n0,0\n10,50\n".utf8).write(to: url)

        let rival = try ReplayRivalImportLoader.loadSecurityScopedRival(
            from: url,
            fileName: url.lastPathComponent
        )

        XCTAssertEqual(rival.kind, .importedFile)
        XCTAssertEqual(rival.strokes.count, 2)
    }

    func testImportReadHonorsTaskCancellation() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rowplay-rival-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("time,distance\n0,0\n10,50\n".utf8).write(to: url)

        let task = Task.detached { () throws -> Data in
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try ReplayRivalImportLoader.readData(from: url)
        }

        do {
            _ = try await task.value
            XCTFail("A cancelled import must not continue")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testImportGenerationRejectsCompletionAfterNewerSelection() {
        var generation = ReplayRivalImportGeneration()
        let oldImport = generation.advance()

        XCTAssertTrue(generation.accepts(oldImport))

        let newerSelection = generation.advance()

        XCTAssertFalse(generation.accepts(oldImport))
        XCTAssertTrue(generation.accepts(newerSelection))
    }

    func testImportLoaderRejectsOversizedFileWithoutReadingItAll() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rowplay-rival-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0x41, count: 128).write(to: url)

        XCTAssertThrowsError(
            try ReplayRivalImportLoader.readData(from: url, maximumBytes: 32)
        ) { error in
            XCTAssertEqual(error as? ReplayRivalFileParserError, .fileTooLarge)
        }
    }

    func testFilePanelCancellationIsNotPresentedAsAnImportOrExportError() {
        let cancellation = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        let unrelated = NSError(domain: "example", code: NSUserCancelledError)

        XCTAssertTrue(ReplayView.isUserCancellation(cancellation))
        XCTAssertTrue(ReplayView.isUserCancellation(CancellationError()))
        XCTAssertFalse(ReplayView.isUserCancellation(unrelated))
        XCTAssertFalse(ReplayView.isUserCancellation(ReplayRivalFileParserError.malformed))
    }

    func testSceneIdentityUsesGenericRivalID() {
        let noRival = Replay3DSceneIdentity(
            workoutID: 1,
            rivalID: nil,
            sportRawValue: Sport.rower.rawValue
        )
        let pace = Replay3DSceneIdentity(
            workoutID: 1,
            rivalID: "pace-120",
            sportRawValue: Sport.rower.rawValue
        )
        let session = Replay3DSceneIdentity(
            workoutID: 1,
            rivalID: "session-2",
            sportRawValue: Sport.rower.rawValue
        )
        XCTAssertNotEqual(noRival, pace)
        XCTAssertNotEqual(pace, session)
        XCTAssertEqual(pace.rivalID, "pace-120")
    }

    func testRaceResultCachedSemanticsForDistanceWin() {
        guard let detail = DemoWorkoutLibrary.details.first else {
            return XCTFail("Demo data must include a replayable workout")
        }
        let rival = ReplayRivalFactory.makeConstantPaceRival(
            pacePer500m: detail.workout.pace + 20,
            player: detail.workout
        )
        guard let rival else {
            return XCTFail("Expected constant-pace rival")
        }
        let result = ReplayRaceResultCalculator.result(
            playerStrokes: detail.strokes,
            rivalStrokes: rival.strokes,
            workout: detail.workout
        )
        // Slower pace boat should lose when player finishes the distance piece.
        if detail.workout.distance > 0,
           ComparabilityGuard.classifyAxis(workoutType: detail.workout.workoutType) == .distance {
            XCTAssertNotNil(result)
        }
    }

    func testConstantPaceAndImportedRivalsMarkNonGenuineStrokeData() throws {
        guard let detail = DemoWorkoutLibrary.details.first else {
            return XCTFail("Demo data must include a replayable workout")
        }
        let pace = try XCTUnwrap(
            ReplayRivalFactory.makeConstantPaceRival(pacePer500m: 120, player: detail.workout)
        )
        XCTAssertFalse(pace.hasGenuineStrokeData)

        let csv = "time,distance\n0,0\n10,50\n20,100\n"
        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "i.csv")
        let imported = try XCTUnwrap(
            ReplayRivalFactory.makeImportedRival(strokes: parsed.strokes, fileName: parsed.fileName)
        )
        XCTAssertFalse(imported.hasGenuineStrokeData)

        let session = try XCTUnwrap(ReplayRivalFactory.makeSessionRival(from: detail))
        // Demo workouts with stroke data are genuine session rivals.
        if detail.workout.hasStrokeData, detail.strokes.count >= 2 {
            XCTAssertTrue(session.hasGenuineStrokeData)
        }
    }

    func test3DSessionRivalUsesGenuineArticulationWhileSyntheticRivalsUseFallback() throws {
        guard let detail = DemoWorkoutLibrary.details.first(where: {
            $0.workout.hasStrokeData && $0.strokes.count >= 2
        }) else {
            return XCTFail("Demo data must include a genuine session rival")
        }
        let context = makeGhostPoseContext(peakWatts: 240)
        let session = try XCTUnwrap(ReplayRivalFactory.makeSessionRival(from: detail))
        let pace = try XCTUnwrap(
            ReplayRivalFactory.makeConstantPaceRival(pacePer500m: 120, player: detail.workout)
        )
        let parsed = try ReplayRivalFileParser.parse(
            data: Data("time,distance\n0,0\n10,50\n20,100\n".utf8),
            fileName: "rival.csv"
        )
        let imported = try XCTUnwrap(
            ReplayRivalFactory.makeImportedRival(
                strokes: parsed.strokes,
                fileName: parsed.fileName
            )
        )

        XCTAssertEqual(
            Replay3DGhostArticulation.select(rival: session, poseContext: context),
            .genuine(context)
        )
        XCTAssertEqual(
            Replay3DGhostArticulation.select(rival: pace, poseContext: context),
            .fallback
        )
        XCTAssertEqual(
            Replay3DGhostArticulation.select(rival: imported, poseContext: context),
            .fallback
        )
        XCTAssertEqual(
            Replay3DGhostArticulation.select(rival: session, poseContext: nil),
            .fallback
        )
    }

    func testRivalChangeIdentityDiffersAcrossKinds() {
        let session = Replay3DSceneIdentity(
            workoutID: 1,
            rivalID: "session-9",
            sportRawValue: Sport.rower.rawValue
        )
        let pace = Replay3DSceneIdentity(
            workoutID: 1,
            rivalID: "pace-120.0000-d-2000.000",
            sportRawValue: Sport.rower.rawValue
        )
        let imported = Replay3DSceneIdentity(
            workoutID: 1,
            rivalID: "file-abc",
            sportRawValue: Sport.rower.rawValue
        )
        XCTAssertNotEqual(session, pace)
        XCTAssertNotEqual(pace, imported)
        XCTAssertNotEqual(session.rivalID, imported.rivalID)
    }

    func testSceneStateGhostPoseAggregatesRecomputeForRivalReplacement() {
        let state = Replay3DSceneState()
        let first = makeGhostPoseContext(peakWatts: 200)
        let replacement = makeGhostPoseContext(peakWatts: 300)

        XCTAssertEqual(
            state.updateGhostPoseAggregates(for: "session-a") {
                (context: first, medianHR: 140)
            },
            .recomputed
        )
        XCTAssertEqual(
            state.updateGhostPoseAggregates(for: "session-b") {
                (context: replacement, medianHR: 155)
            },
            .recomputed
        )

        XCTAssertEqual(state.ghostPoseContext, replacement)
        XCTAssertEqual(state.ghostMedianHR, 155)
        XCTAssertEqual(state.ghostPoseRivalID, "session-b")
    }

    func testSceneStateGhostPoseAggregatesClearForFallbackRival() {
        let state = Replay3DSceneState()
        state.updateGhostPoseAggregates(for: "session-a") {
            (context: makeGhostPoseContext(peakWatts: 200), medianHR: 140)
        }

        XCTAssertEqual(state.clearGhostPoseAggregates(), .cleared)

        XCTAssertNil(state.ghostPoseRivalID)
        XCTAssertNil(state.ghostPoseContext)
        XCTAssertEqual(state.ghostMedianHR, 0)
        XCTAssertEqual(state.clearGhostPoseAggregates(), .unchanged)
    }

    func testSceneStateGhostPoseAggregatesPreserveSameRivalWithoutRecompute() {
        let state = Replay3DSceneState()
        let original = makeGhostPoseContext(peakWatts: 200)
        state.updateGhostPoseAggregates(for: "session-a") {
            (context: original, medianHR: 140)
        }
        var recomputeCount = 0

        let update = state.updateGhostPoseAggregates(for: "session-a") {
            recomputeCount += 1
            return (context: makeGhostPoseContext(peakWatts: 999), medianHR: 199)
        }

        XCTAssertEqual(update, .unchanged)
        XCTAssertEqual(recomputeCount, 0)
        XCTAssertEqual(state.ghostPoseContext, original)
        XCTAssertEqual(state.ghostMedianHR, 140)
        XCTAssertEqual(state.ghostPoseRivalID, "session-a")
    }

    func testImportLoaderParsesPreloadedBytesWithoutURLAccess() throws {
        let data = Data("time,distance\n0,0\n10,50\n".utf8)
        let rival = try ReplayRivalImportLoader.makeRival(from: data, fileName: "preloaded.csv")
        XCTAssertEqual(rival.kind, .importedFile)
        XCTAssertEqual(rival.strokes.count, 2)
        XCTAssertEqual(rival.localFileName, "preloaded.csv")
    }

    private func makeGhostPoseContext(peakWatts: Int) -> ReplayStrokePoseContext {
        ReplayStrokePoseContext(
            sport: .rower,
            peakWatts: peakWatts,
            medianWatts: peakWatts - 20,
            medianDPS: 10,
            maxHR: 180
        )
    }
}
