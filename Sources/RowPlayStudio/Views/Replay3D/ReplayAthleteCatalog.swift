import CryptoKit
import Foundation
import RowPlayCore
import simd

/// Motion sample consumed by the V4 pose adapter.
///
/// Native replay remains authoritative for the clock; this is only the
/// phase/drive fraction used to seek the authored sport animation.
struct ReplayAthleteMotionSample: Equatable, Sendable {
    let phase: Double
    let cycleFrac: Double
    let driveFrac: Double

    init(phase: Double, cycleFrac: Double, driveFrac: Double) {
        self.phase = phase
        self.cycleFrac = cycleFrac
        self.driveFrac = driveFrac
    }

    init(strokePose: ReplayStrokePose) {
        self.phase = strokePose.phase
        self.cycleFrac = strokePose.cycleFrac
        self.driveFrac = strokePose.driveFrac
    }
}

/// A contact role authored on the V4 contract.
struct ReplayAthleteContactSpec: Equatable, Sendable {
    let bone: String
    let role: String
    let localOffset: SIMD3<Double>
}

/// Sport animation metadata from the versioned V4 contract.
struct ReplayAthleteClipSpec: Equatable, Sendable {
    let sport: Sport
    let name: String
    let durationSeconds: Double
    let driveEnd: Double
    let phaseLandmarks: [String: Double]
}

/// Parsed, validated V4 contract used by the native loader and pose adapter.
struct ReplayAthleteContract: Equatable, Sendable {
    let schema: String
    let schemaVersion: Int
    let orderedBoneNames: [String]
    let clips: [ReplayAthleteClipSpec]
    let contacts: [ReplayAthleteContactSpec]
    let glbSha256: String
    let usdzSha256: String

    func clip(for sport: Sport) -> ReplayAthleteClipSpec? {
        clips.first { $0.sport == sport }
    }
}

/// Source-manifest facts for the provisional/final upstream pin.
struct ReplayAthleteSourceManifest: Equatable, Sendable {
    let pinnedCommit: String
    let status: String
    let upstreamPR: Int
    let upstreamRepository: String
    let glbSha256: String
    let usdzSha256: String
    let contractSha256: String
    let copiedUsdzSha256: String
    let contractSchema: String
    let contractSchemaVersion: Int
}

/// Reasons the canonical athlete package cannot be used.
enum ReplayAthleteValidationFailure: Error, Equatable, Sendable {
    case missingResource(String)
    case hashMismatch(resource: String, expected: String, actual: String)
    case invalidContract(String)
    case missingBone(String)
    case boneCountMismatch(actual: Int, expected: Int)
    case missingClip(Sport)
    case invalidClipTiming(Sport)
    case missingContact(String)
    case nonFiniteRestTransform(String)
    case missingSkinnedAthlete
    case multipleSkinnedAthletes
    case missingAnimation
    case pinMismatch(String)
}

struct ReplayAthleteValidationResult: Equatable, Sendable {
    let failures: [ReplayAthleteValidationFailure]
    var isValid: Bool { failures.isEmpty }

    init(failures: [ReplayAthleteValidationFailure] = []) {
        self.failures = failures
    }
}

/// Single source of truth for the V4 athlete pin, names, and contract helpers.
///
/// Updating the provisional PR #171 snapshot is mechanical: change the pin
/// constants here and in `script/sync_rowplay_athlete.py`, then re-run the
/// sync script.
enum ReplayAthleteCatalog {
    static let resourceSubdirectory = "Replay3D"
    static let usdzResourceName = "rowplay-athlete-v4"
    static let usdzExtension = "usdz"
    static let contractResourceName = "rowplay-athlete-v4.contract"
    static let contractExtension = "json"
    static let sourceManifestResourceName = "rowplay-athlete-v4-source"
    static let sourceManifestExtension = "json"

    static let usdzFileName = "\(usdzResourceName).\(usdzExtension)"
    static let contractFileName = "\(contractResourceName).\(contractExtension)"
    static let sourceManifestFileName = "\(sourceManifestResourceName).\(sourceManifestExtension)"

    /// Provisional pin from upstream PR #171. Refresh with the sync script.
    static let pinnedCommit = "dba7211bfa94d3f86e60b75921bd5853ec736f55"
    static let pinStatus = "provisional"
    static let upstreamPR = 171
    static let upstreamRepository = "https://github.com/shenghaoc/rowplay"

    static let expectedGLBSHA256 =
        "a9a215f07bd39d15daa5c45c5bfbbb1788656ad7916fc39f172c5dcc78129963"
    static let expectedUSDZSHA256 =
        "5591b13c7d58bc4f44194728c1a2fc1c669086232d2f1bd97723672392c50723"
    static let expectedContractSHA256 =
        "96acec971c3247120e71af726388420dd89866437c76c3a417ea267481976dba"

    static let contractSchema = "rowplay.replay.athlete.v4"
    static let skinnedMeshName = "v4Athlete"
    static let rootEntityName = "rowplay_v4_athlete_root"

    /// Canonical 19-joint hierarchy. Paths match RealityKit's jointNames form.
    static let orderedBoneNames: [String] = [
        "v4Hips",
        "v4Spine",
        "v4Chest",
        "v4Neck",
        "v4Head",
        "v4LeftClavicle",
        "v4LeftUpperArm",
        "v4LeftForearm",
        "v4LeftHand",
        "v4RightClavicle",
        "v4RightUpperArm",
        "v4RightForearm",
        "v4RightHand",
        "v4LeftUpperLeg",
        "v4LeftLowerLeg",
        "v4LeftFoot",
        "v4RightUpperLeg",
        "v4RightLowerLeg",
        "v4RightFoot",
    ]

    static let orderedJointPaths: [String] = [
        "v4Hips",
        "v4Hips/v4Spine",
        "v4Hips/v4Spine/v4Chest",
        "v4Hips/v4Spine/v4Chest/v4Neck",
        "v4Hips/v4Spine/v4Chest/v4Neck/v4Head",
        "v4Hips/v4Spine/v4Chest/v4LeftClavicle",
        "v4Hips/v4Spine/v4Chest/v4LeftClavicle/v4LeftUpperArm",
        "v4Hips/v4Spine/v4Chest/v4LeftClavicle/v4LeftUpperArm/v4LeftForearm",
        "v4Hips/v4Spine/v4Chest/v4LeftClavicle/v4LeftUpperArm/v4LeftForearm/v4LeftHand",
        "v4Hips/v4Spine/v4Chest/v4RightClavicle",
        "v4Hips/v4Spine/v4Chest/v4RightClavicle/v4RightUpperArm",
        "v4Hips/v4Spine/v4Chest/v4RightClavicle/v4RightUpperArm/v4RightForearm",
        "v4Hips/v4Spine/v4Chest/v4RightClavicle/v4RightUpperArm/v4RightForearm/v4RightHand",
        "v4Hips/v4LeftUpperLeg",
        "v4Hips/v4LeftUpperLeg/v4LeftLowerLeg",
        "v4Hips/v4LeftUpperLeg/v4LeftLowerLeg/v4LeftFoot",
        "v4Hips/v4RightUpperLeg",
        "v4Hips/v4RightUpperLeg/v4RightLowerLeg",
        "v4Hips/v4RightUpperLeg/v4RightLowerLeg/v4RightFoot",
    ]

    static let contactEntityNames: [String: String] = [
        "left-hand": "v4LeftHandContact",
        "right-hand": "v4RightHandContact",
        "left-foot": "v4LeftFootContact",
        "right-foot": "v4RightFootContact",
    ]

    /// Map contract sport strings (`rower` / `skier` / `bike`) onto native `Sport`.
    static func sport(fromContractSport raw: String) -> Sport? {
        switch raw {
        case "rower":
            .rower
        case "skier", "skierg":
            .skierg
        case "bike":
            .bike
        default:
            nil
        }
    }

    static func wrapUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        var wrapped = value - value.rounded(.down)
        if wrapped < 0 { wrapped += 1 }
        if wrapped >= 1 { wrapped = 0 }
        return wrapped
    }

    /// Deterministic phase → clip fraction mapping ported from the web V4 adapter.
    ///
    /// Maps the native stroke cycle onto the authored clip's drive/recovery split
    /// without introducing an independent animation timer.
    static func clipFraction(
        sample: ReplayAthleteMotionSample,
        authoredDriveEnd: Double
    ) -> Double {
        let phaseCycle = wrapUnit(sample.phase / (2 * Double.pi))
        let cycle = sample.cycleFrac.isFinite ? wrapUnit(sample.cycleFrac) : phaseCycle
        let sourceDrive = min(0.95, max(0.05, sample.driveFrac.isFinite ? sample.driveFrac : 0.4))
        let clipDrive = min(0.95, max(0.05, authoredDriveEnd.isFinite ? authoredDriveEnd : 0.5))
        if cycle < sourceDrive {
            return (cycle / sourceDrive) * clipDrive
        }
        return clipDrive + ((cycle - sourceDrive) / (1 - sourceDrive)) * (1 - clipDrive)
    }

    static func parseContract(data: Data) -> Result<ReplayAthleteContract, ReplayAthleteValidationFailure> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.invalidContract("not JSON"))
        }
        guard let schema = root["schema"] as? String,
              schema == contractSchema else {
            return .failure(.invalidContract("schema"))
        }
        guard let schemaVersion = root["schemaVersion"] as? Int else {
            return .failure(.invalidContract("schemaVersion"))
        }
        guard let bones = root["bones"] as? [String: Any],
              let ordered = bones["orderedNames"] as? [String] else {
            return .failure(.invalidContract("bones.orderedNames"))
        }
        guard ordered == orderedBoneNames else {
            return .failure(.invalidContract("bone order drifted"))
        }
        guard let animation = root["animation"] as? [String: Any],
              let rawClips = animation["clips"] as? [[String: Any]] else {
            return .failure(.invalidContract("animation.clips"))
        }

        var clips: [ReplayAthleteClipSpec] = []
        for raw in rawClips {
            guard let sportRaw = raw["sport"] as? String,
                  let sport = sport(fromContractSport: sportRaw),
                  let name = raw["name"] as? String,
                  let duration = raw["durationSeconds"] as? Double,
                  let driveEnd = raw["driveEnd"] as? Double,
                  let landmarks = raw["phaseLandmarks"] as? [String: Double],
                  duration > 0,
                  driveEnd > 0,
                  driveEnd < 1 else {
                return .failure(.invalidContract("clip entry"))
            }
            clips.append(
                ReplayAthleteClipSpec(
                    sport: sport,
                    name: name,
                    durationSeconds: duration,
                    driveEnd: driveEnd,
                    phaseLandmarks: landmarks
                )
            )
        }
        guard clips.contains(where: { $0.sport == .rower }),
              clips.contains(where: { $0.sport == .skierg }),
              clips.contains(where: { $0.sport == .bike }) else {
            return .failure(.invalidContract("missing sport clips"))
        }

        guard let rawContacts = root["contacts"] as? [[String: Any]] else {
            return .failure(.invalidContract("contacts"))
        }
        var contacts: [ReplayAthleteContactSpec] = []
        for raw in rawContacts {
            guard let bone = raw["bone"] as? String,
                  let role = raw["role"] as? String,
                  let offset = raw["localOffset"] as? [Double],
                  offset.count == 3,
                  offset.allSatisfy(\.isFinite) else {
                return .failure(.invalidContract("contact entry"))
            }
            contacts.append(
                ReplayAthleteContactSpec(
                    bone: bone,
                    role: role,
                    localOffset: SIMD3(offset[0], offset[1], offset[2])
                )
            )
        }
        for role in ["left-hand", "right-hand", "left-foot", "right-foot"] {
            if !contacts.contains(where: { $0.role == role }) {
                return .failure(.missingContact(role))
            }
        }

        guard let web = root["webRuntimeArtifact"] as? [String: Any],
              let glbSha = web["sha256"] as? String,
              let native = root["nativeDerivativeArtifact"] as? [String: Any],
              let usdzSha = native["sha256"] as? String else {
            return .failure(.invalidContract("artifact hashes"))
        }

        return .success(
            ReplayAthleteContract(
                schema: schema,
                schemaVersion: schemaVersion,
                orderedBoneNames: ordered,
                clips: clips,
                contacts: contacts,
                glbSha256: glbSha,
                usdzSha256: usdzSha
            )
        )
    }

    static func parseSourceManifest(data: Data) -> Result<ReplayAthleteSourceManifest, ReplayAthleteValidationFailure> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pinnedCommit = root["pinnedCommit"] as? String,
              let status = root["status"] as? String,
              let upstreamPR = root["upstreamPR"] as? Int,
              let upstreamRepository = root["upstreamRepository"] as? String,
              let glbSha256 = root["glbSha256"] as? String,
              let usdzSha256 = root["usdzSha256"] as? String,
              let contractSha256 = root["contractSha256"] as? String,
              let copiedUsdzSha256 = root["copiedUsdzSha256"] as? String,
              let contractSchema = root["contractSchema"] as? String,
              let contractSchemaVersion = root["contractSchemaVersion"] as? Int else {
            return .failure(.invalidContract("source manifest"))
        }
        return .success(
            ReplayAthleteSourceManifest(
                pinnedCommit: pinnedCommit,
                status: status,
                upstreamPR: upstreamPR,
                upstreamRepository: upstreamRepository,
                glbSha256: glbSha256,
                usdzSha256: usdzSha256,
                contractSha256: contractSha256,
                copiedUsdzSha256: copiedUsdzSha256,
                contractSchema: contractSchema,
                contractSchemaVersion: contractSchemaVersion
            )
        )
    }

    static func validateSourceManifest(
        _ manifest: ReplayAthleteSourceManifest
    ) -> ReplayAthleteValidationResult {
        var failures: [ReplayAthleteValidationFailure] = []
        if manifest.pinnedCommit != pinnedCommit {
            failures.append(.pinMismatch("pinnedCommit"))
        }
        if manifest.status != pinStatus {
            failures.append(.pinMismatch("status"))
        }
        if manifest.upstreamPR != upstreamPR {
            failures.append(.pinMismatch("upstreamPR"))
        }
        if manifest.glbSha256 != expectedGLBSHA256 {
            failures.append(.hashMismatch(
                resource: "glb",
                expected: expectedGLBSHA256,
                actual: manifest.glbSha256
            ))
        }
        if manifest.usdzSha256 != expectedUSDZSHA256 {
            failures.append(.hashMismatch(
                resource: "usdz",
                expected: expectedUSDZSHA256,
                actual: manifest.usdzSha256
            ))
        }
        if manifest.contractSha256 != expectedContractSHA256 {
            failures.append(.hashMismatch(
                resource: "contract",
                expected: expectedContractSHA256,
                actual: manifest.contractSha256
            ))
        }
        if manifest.copiedUsdzSha256 != expectedUSDZSHA256 {
            failures.append(.hashMismatch(
                resource: "copied-usdz",
                expected: expectedUSDZSHA256,
                actual: manifest.copiedUsdzSha256
            ))
        }
        if manifest.contractSchema != contractSchema {
            failures.append(.invalidContract("source schema"))
        }
        return ReplayAthleteValidationResult(failures: failures)
    }

    static func validateContractHashes(
        _ contract: ReplayAthleteContract
    ) -> ReplayAthleteValidationResult {
        var failures: [ReplayAthleteValidationFailure] = []
        if contract.glbSha256 != expectedGLBSHA256 {
            failures.append(.hashMismatch(
                resource: "contract.glb",
                expected: expectedGLBSHA256,
                actual: contract.glbSha256
            ))
        }
        if contract.usdzSha256 != expectedUSDZSHA256 {
            failures.append(.hashMismatch(
                resource: "contract.usdz",
                expected: expectedUSDZSHA256,
                actual: contract.usdzSha256
            ))
        }
        return ReplayAthleteValidationResult(failures: failures)
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
