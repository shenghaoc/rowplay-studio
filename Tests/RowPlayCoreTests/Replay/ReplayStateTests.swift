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
