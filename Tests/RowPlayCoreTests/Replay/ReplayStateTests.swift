import XCTest
@testable import RowPlayCore

final class ReplayStateTests: XCTestCase {
    private var demoStrokes: [Stroke] {
        DemoWorkoutLibrary.details.first { $0.workout.id == 1001 }?.strokes ?? []
    }

    func testInitialStateIsPausedAtZero() {
        let state = ReplayState(strokes: demoStrokes)
        XCTAssertFalse(state.playing)
        XCTAssertEqual(state.time, 0)
        XCTAssertTrue(state.duration > 0)
    }

    func testFrameTimeAndProgressAreRelativeWhenFirstStrokeStartsAfterZero() {
        let strokes = [
            Stroke(t: 5, d: 10, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 15, d: 60, pace: 110, cadence: 30, watts: 220)
        ]
        let state = ReplayState(strokes: strokes)

        XCTAssertEqual(state.duration, 10)
        XCTAssertEqual(state.currentFrame.t, 0)
        XCTAssertEqual(state.currentFrame.progress, 0)

        state.play()
        state.tick(deltaTime: 2)

        XCTAssertEqual(state.time, 2)
        XCTAssertEqual(state.currentFrame.t, 2)
        XCTAssertEqual(state.currentFrame.progress, 0.2, accuracy: 0.0001)
        XCTAssertTrue(state.currentFrame.d > strokes[0].d)
    }

    func testPlaySetsPlayingTrue() {
        let state = ReplayState(strokes: demoStrokes)
        state.play()
        XCTAssertTrue(state.playing)
    }

    func testPauseSetsPlayingFalse() {
        let state = ReplayState(strokes: demoStrokes)
        state.play()
        state.pause()
        XCTAssertFalse(state.playing)
    }

    func testToggleAlternatesPlayPause() {
        let state = ReplayState(strokes: demoStrokes)
        state.toggle()
        XCTAssertTrue(state.playing)
        state.toggle()
        XCTAssertFalse(state.playing)
    }

    func testTickAdvancesTime() {
        let state = ReplayState(strokes: demoStrokes)
        state.play()
        state.tick(deltaTime: 1.0)
        XCTAssertTrue(state.time > 0)
    }

    func testTickDoesNothingWhenPaused() {
        let state = ReplayState(strokes: demoStrokes)
        let initialTime = state.time
        state.tick(deltaTime: 1.0)
        XCTAssertEqual(state.time, initialTime)
    }

    func testTickIgnoresInvalidDeltas() {
        let state = ReplayState(strokes: demoStrokes)
        state.play()
        XCTAssertFalse(state.tick(deltaTime: -1.0))
        XCTAssertFalse(state.tick(deltaTime: .nan))
        XCTAssertFalse(state.tick(deltaTime: .infinity))
        XCTAssertEqual(state.time, 0)
        XCTAssertTrue(state.playing)
    }

    func testTickRespectsSpeedMultiplier() {
        let state = ReplayState(strokes: demoStrokes)
        state.play()
        state.setSpeed(.two)
        state.tick(deltaTime: 1.0)
        XCTAssertEqual(state.time, 2.0, accuracy: 0.01)
    }

    func testAutoPauseAtEnd() {
        let state = ReplayState(strokes: demoStrokes)
        state.play()
        // Tick well past the end.
        state.tick(deltaTime: state.duration + 10)
        XCTAssertFalse(state.playing)
        XCTAssertEqual(state.time, state.duration, accuracy: 0.01)
    }

    func testSeekClampsToDuration() {
        let state = ReplayState(strokes: demoStrokes)
        state.seek(to: state.duration + 100)
        XCTAssertEqual(state.time, state.duration, accuracy: 0.01)
    }

    func testSeekClampsToZero() {
        let state = ReplayState(strokes: demoStrokes)
        state.seek(to: -100)
        XCTAssertEqual(state.time, 0)
    }

    func testPlayResetsToZeroWhenAtEnd() {
        let state = ReplayState(strokes: demoStrokes)
        state.seek(to: state.duration)
        state.play()
        XCTAssertEqual(state.time, 0)
        XCTAssertTrue(state.playing)
    }

    func testFrameUpdatesWithTime() {
        let state = ReplayState(strokes: demoStrokes)
        let initialFrame = state.currentFrame
        state.play()
        state.tick(deltaTime: 1.0)
        XCTAssertNotEqual(state.currentFrame.t, initialFrame.t)
    }

    func testSpeedPresetsAreDistinct() {
        let speeds = ReplaySpeed.allCases
        XCTAssertEqual(speeds.count, 5)
        XCTAssertEqual(Set(speeds.map(\.rawValue)).count, speeds.count)
    }

    func testOnFrameCallbackIsCalled() {
        var callbackCount = 0
        let state = ReplayState(strokes: demoStrokes) { _, _ in
            callbackCount += 1
        }
        state.play()
        state.tick(deltaTime: 0.1)
        XCTAssertTrue(callbackCount > 0)
    }
}
