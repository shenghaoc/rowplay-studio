import Foundation

/// One sampled bone-local transform from the athlete motion table.
public struct ReplayAthleteBoneTransform: Equatable, Sendable {
    public var translation: SIMD3<Double>
    public var rotation: ReplayQuaternion
    public var scale: SIMD3<Double>

    public init(
        translation: SIMD3<Double> = SIMD3(0, 0, 0),
        rotation: ReplayQuaternion = .identity,
        scale: SIMD3<Double> = SIMD3(1, 1, 1)
    ) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }
}

/// Authored base-motion table sampled from the production athlete's GLB clips
/// (`rowplay-motion.bin` + manifest).
///
/// The table stores every semantic bone's local transform at
/// `samplesPerSport` evenly spaced phases per sport, as compact little-endian
/// Float32.  Sampling interpolates translation and scale linearly and
/// rotations with shortest-path normalized quaternion interpolation, wrapping
/// at the cycle seam.  There is no JSON parsing or name lookup on the sample
/// path — callers resolve bone indices once and reuse them.
public struct ReplayAthleteMotionTable: Sendable {
    public struct ClipInfo: Equatable, Sendable {
        public let sport: Sport
        public let clipName: String
        public let durationSeconds: Double
        public let driveEnd: Double
        public let phaseLandmarks: [String: Double]
    }

    /// Parsed manifest shared by bundle seal validation and table loading so
    /// callers never independently reinterpret the same JSON payload.
    public struct Manifest: Equatable, Sendable {
        public let formatVersion: Int
        public let boneNames: [String]
        public let samplesPerSport: Int
        public let sports: [Sport]
        public let clips: [Sport: ClipInfo]
        public let sourceCommit: String
        public let sourceGlbSha256: String?
        public let motionBinSha256: String?
        public let motionBinByteCount: Int?
    }

    public static let floatsPerBone = 10
    public static let expectedFormatVersion = 2

    public let boneNames: [String]
    public let samplesPerSport: Int
    public let sports: [Sport]
    public let clips: [Sport: ClipInfo]
    public let sourceCommit: String

    private let values: [Float]
    private let strideBone: Int
    private let stridePhase: Int
    private let strideSport: Int
    private let sportOffsets: [Sport: Int]

    public enum LoadError: Error, Equatable, Sendable {
        case invalidManifest(String)
        case payloadSizeMismatch(expected: Int, actual: Int)
        case nonFinitePayload
        case unsupportedFormatVersion(Int)
    }

    public init(manifestData: Data, binData: Data) throws {
        try self.init(manifest: Self.parseManifest(data: manifestData), binData: binData)
    }

    public init(manifest: Manifest, binData: Data) throws {
        let boneNames = manifest.boneNames
        let samples = manifest.samplesPerSport
        let sports = manifest.sports
        let clips = manifest.clips
        let sourceCommit = manifest.sourceCommit
        let strideBone = Self.floatsPerBone
        let stridePhase = boneNames.count * strideBone
        let strideSport = samples * stridePhase
        let expectedBytes = sports.count * strideSport * MemoryLayout<Float>.size
        guard binData.count == expectedBytes else {
            throw LoadError.payloadSizeMismatch(expected: expectedBytes, actual: binData.count)
        }

        var values = [Float](repeating: 0, count: binData.count / MemoryLayout<Float>.size)
        _ = values.withUnsafeMutableBytes { destination in
            binData.copyBytes(to: destination)
        }
        // Stored little-endian; every current target is little-endian, and a
        // big-endian port would fail the finite gate below immediately.
        for value in values where !value.isFinite {
            throw LoadError.nonFinitePayload
        }

        var sportOffsets: [Sport: Int] = [:]
        for (index, sport) in sports.enumerated() {
            sportOffsets[sport] = index * strideSport
        }

        self.boneNames = boneNames
        self.samplesPerSport = samples
        self.sports = sports
        self.clips = clips
        self.sourceCommit = sourceCommit
        self.values = values
        self.strideBone = strideBone
        self.stridePhase = stridePhase
        self.strideSport = strideSport
        self.sportOffsets = sportOffsets
    }

    public static func parseManifest(data manifestData: Data) throws -> Manifest {
        guard let root = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
            throw LoadError.invalidManifest("not JSON")
        }
        guard let version = root["formatVersion"] as? Int else {
            throw LoadError.invalidManifest("formatVersion")
        }
        guard version == Self.expectedFormatVersion else {
            throw LoadError.unsupportedFormatVersion(version)
        }
        guard let boneNames = root["boneNames"] as? [String], !boneNames.isEmpty else {
            throw LoadError.invalidManifest("boneNames")
        }
        guard let samples = root["samplesPerSport"] as? Int, samples > 1 else {
            throw LoadError.invalidManifest("samplesPerSport")
        }
        guard let sportsRaw = root["sports"] as? [String], !sportsRaw.isEmpty else {
            throw LoadError.invalidManifest("sports")
        }
        guard let clipsRaw = root["clips"] as? [[String: Any]] else {
            throw LoadError.invalidManifest("clips")
        }
        guard let sourceCommit = root["sourceCommit"] as? String,
              !sourceCommit.isEmpty else {
            throw LoadError.invalidManifest("sourceCommit")
        }

        var sports: [Sport] = []
        for raw in sportsRaw {
            guard let sport = Self.sport(fromManifestName: raw) else {
                throw LoadError.invalidManifest("unknown sport \(raw)")
            }
            guard !sports.contains(sport) else {
                throw LoadError.invalidManifest("duplicate sport \(raw)")
            }
            sports.append(sport)
        }

        var clips: [Sport: ClipInfo] = [:]
        for raw in clipsRaw {
            guard let sportRaw = raw["sport"] as? String,
                  let sport = Self.sport(fromManifestName: sportRaw),
                  let clipName = raw["clipName"] as? String,
                  let duration = raw["durationSeconds"] as? Double,
                  let driveEnd = raw["driveEnd"] as? Double,
                  let landmarks = raw["phaseLandmarks"] as? [String: Double],
                  !landmarks.isEmpty,
                  landmarks.values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
                  duration > 0, driveEnd > 0, driveEnd < 1 else {
                throw LoadError.invalidManifest("clip entry")
            }
            guard clips[sport] == nil else {
                throw LoadError.invalidManifest("duplicate clip for \(sport.rawValue)")
            }
            clips[sport] = ClipInfo(
                sport: sport,
                clipName: clipName,
                durationSeconds: duration,
                driveEnd: driveEnd,
                phaseLandmarks: landmarks
            )
        }
        for sport in sports where clips[sport] == nil {
            throw LoadError.invalidManifest("missing clip for \(sport.rawValue)")
        }
        if let undeclaredSport = clips.keys
            .filter({ !sports.contains($0) })
            .sorted(by: { $0.rawValue < $1.rawValue })
            .first {
            throw LoadError.invalidManifest(
                "clip for undeclared sport \(undeclaredSport.rawValue)"
            )
        }
        return Manifest(
            formatVersion: version,
            boneNames: boneNames,
            samplesPerSport: samples,
            sports: sports,
            clips: clips,
            sourceCommit: sourceCommit,
            sourceGlbSha256: root["sourceGlbSha256"] as? String,
            motionBinSha256: root["motionBinSha256"] as? String,
            motionBinByteCount: root["motionBinByteCount"] as? Int
        )
    }

    public func boneIndex(named name: String) -> Int? {
        boneNames.firstIndex(of: name)
    }

    /// Sample every bone's local transform at a wrapped clip fraction,
    /// writing into a caller-owned buffer sized `boneNames.count`.
    /// O(bones); no allocation, no lookup by name.
    @discardableResult
    public func sample(
        sport: Sport,
        fraction: Double,
        into output: inout [ReplayAthleteBoneTransform]
    ) -> Bool {
        guard let base = sportOffsets[sport], output.count == boneNames.count else { return false }
        let wrapped = Self.wrapUnit(fraction)
        let scaled = wrapped * Double(samplesPerSport)
        let lowerPhase = Int(scaled) % samplesPerSport
        let upperPhase = (lowerPhase + 1) % samplesPerSport
        let t = scaled - scaled.rounded(.down)

        let lowerBase = base + lowerPhase * stridePhase
        let upperBase = base + upperPhase * stridePhase
        for bone in 0..<boneNames.count {
            let lower = lowerBase + bone * strideBone
            let upper = upperBase + bone * strideBone
            let translation = SIMD3(
                lerp(values[lower], values[upper], t),
                lerp(values[lower + 1], values[upper + 1], t),
                lerp(values[lower + 2], values[upper + 2], t)
            )
            let lowerRotation = ReplayQuaternion(
                x: Double(values[lower + 3]),
                y: Double(values[lower + 4]),
                z: Double(values[lower + 5]),
                w: Double(values[lower + 6])
            )
            let upperRotation = ReplayQuaternion(
                x: Double(values[upper + 3]),
                y: Double(values[upper + 4]),
                z: Double(values[upper + 5]),
                w: Double(values[upper + 6])
            )
            let scale = SIMD3(
                lerp(values[lower + 7], values[upper + 7], t),
                lerp(values[lower + 8], values[upper + 8], t),
                lerp(values[lower + 9], values[upper + 9], t)
            )
            output[bone] = ReplayAthleteBoneTransform(
                translation: translation,
                rotation: lowerRotation.interpolated(towards: upperRotation, fraction: t),
                scale: scale
            )
        }
        return true
    }

    public static func wrapUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        var wrapped = value - value.rounded(.down)
        if wrapped < 0 { wrapped += 1 }
        if wrapped >= 1 { wrapped = 0 }
        return wrapped
    }

    public static func sport(fromManifestName raw: String) -> Sport? {
        switch raw {
        case "rower": .rower
        case "skierg", "skier": .skierg
        case "bike": .bike
        default: nil
        }
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Double) -> Double {
        Double(a) + (Double(b) - Double(a)) * t
    }
}
