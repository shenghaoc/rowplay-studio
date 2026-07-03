import Foundation
import Observation

/// Available playback speed presets.
public enum ReplaySpeed: Double, CaseIterable, Sendable {
    case half = 0.5
    case one = 1.0
    case oneAndHalf = 1.5
    case two = 2.0
    case four = 4.0

    public var label: String {
        switch self {
        case .half: "0.5×"
        case .one: "1×"
        case .oneAndHalf: "1.5×"
        case .two: "2×"
        case .four: "4×"
        }
    }
}

/// Pure playback state machine for replay. Driven externally by a timer tick.
///
/// This is the native equivalent of the web's `ReplayEngine` but uses a tick-based
/// model instead of `requestAnimationFrame`, since SwiftUI's `TimelineView` or a
/// `CADisplayLink` drives the ticks externally.
@Observable
public final class ReplayState {
    /// The stroke data being replayed.
    private let strokes: [Stroke]

    /// Time offset of the first stroke (origin).
    private let originT: TimeInterval

    /// Total workout duration in seconds (relative to first stroke).
    public let duration: TimeInterval

    /// Current playback time in seconds.
    public private(set) var time: TimeInterval = 0

    /// Whether playback is currently active.
    public private(set) var playing = false

    /// Current playback speed multiplier.
    public private(set) var speed: ReplaySpeed = .one

    /// The interpolated frame at the current time.
    public private(set) var currentFrame: ReplayFrame

    /// Callback invoked on each frame update with the new frame and playing state.
    private let onFrame: ((ReplayFrame, Bool) -> Void)?

    public init(strokes: [Stroke], onFrame: ((ReplayFrame, Bool) -> Void)? = nil) {
        self.strokes = strokes
        self.originT = strokes.first?.t ?? 0
        let lastT = strokes.last?.t ?? 0
        self.duration = lastT - self.originT
        self.onFrame = onFrame
        self.time = 0
        self.currentFrame = Self.relativeFrame(
            from: ReplaySample.sampleAt(strokes: strokes, t: self.originT),
            playbackTime: 0,
            duration: self.duration
        )
    }

    // MARK: - Playback Controls

    /// Start playback. Resets to beginning if at the end.
    public func play() {
        guard !playing, duration > 0 else { return }
        if time >= duration { time = 0 }
        playing = true
        emit()
    }

    /// Pause playback.
    public func pause() {
        playing = false
        emit()
    }

    /// Toggle between play and pause.
    public func toggle() {
        if playing {
            pause()
        } else {
            play()
        }
    }

    /// Seek to a specific time, clamped to [0, duration].
    public func seek(to t: TimeInterval) {
        time = max(0, min(duration, t))
        emit()
    }

    /// Set the playback speed.
    public func setSpeed(_ s: ReplaySpeed) {
        speed = s
    }

    // MARK: - Tick

    /// Advance the clock by `deltaTime` seconds (real wall-clock). Returns true
    /// if the frame changed.
    @discardableResult
    public func tick(deltaTime: TimeInterval) -> Bool {
        guard playing, deltaTime.isFinite, deltaTime > 0 else { return false }
        time += deltaTime * speed.rawValue
        if time >= duration {
            time = duration
            playing = false
            emit()
            return true
        }
        emit()
        return true
    }

    // MARK: - Private

    private func emit() {
        currentFrame = Self.relativeFrame(
            from: ReplaySample.sampleAt(strokes: strokes, t: time + originT),
            playbackTime: time,
            duration: duration
        )
        onFrame?(currentFrame, playing)
    }

    private static func relativeFrame(
        from sampledFrame: ReplayFrame,
        playbackTime: TimeInterval,
        duration: TimeInterval
    ) -> ReplayFrame {
        var frame = sampledFrame
        frame.t = playbackTime
        frame.progress = duration > 0 ? max(0, min(1, playbackTime / duration)) : 0
        return frame
    }
}
