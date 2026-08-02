import CryptoKit
import Foundation
import RowPlayCore
import simd

/// Motion sample consumed by the V4 pose adapter.
///
/// Native replay remains authoritative for the clock; this is only the
/// phase/drive fraction used to seek the authored sport motion table.
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

/// One authored rest transform from the contract hierarchy.
struct ReplayAthleteRestTransform: Equatable, Sendable {
    let translation: SIMD3<Double>
    let rotation: ReplayQuaternion
    let scale: SIMD3<Double>

    var isFinite: Bool {
        translation.x.isFinite && translation.y.isFinite && translation.z.isFinite
            && rotation.x.isFinite && rotation.y.isFinite && rotation.z.isFinite
            && rotation.w.isFinite
            && scale.x.isFinite && scale.y.isFinite && scale.z.isFinite
    }
}

/// One semantic movement bone from the contract hierarchy.
struct ReplayAthleteBoneSpec: Equatable, Sendable {
    let name: String
    let parent: String?
    let rest: ReplayAthleteRestTransform
}

/// One visual-only grip helper (palm cup, finger or thumb stage).
struct ReplayAthleteHelperSpec: Equatable, Sendable {
    let name: String
    let parent: String
    let rest: ReplayAthleteRestTransform
    let influencedVertices: Int
}

/// One production material surface role.
struct ReplayAthleteSurfaceSpec: Equatable, Sendable {
    let role: String
    let source: String
}

/// Parsed, validated production contract used by the native loader, motion
/// table, pose adapter, and grip controller.  The semantic and helper
/// hierarchies are read from the live contract — not from a hard-coded name
/// list — so an upstream athlete revision is validated, never silently
/// reinterpreted.
struct ReplayAthleteContract: Equatable, Sendable {
    let schema: String
    let schemaVersion: Int
    let semanticBones: [ReplayAthleteBoneSpec]
    let helpers: [ReplayAthleteHelperSpec]
    let clips: [ReplayAthleteClipSpec]
    let contacts: [ReplayAthleteContactSpec]
    let surfaces: [ReplayAthleteSurfaceSpec]
    let meshName: String
    let vertexCount: Int
    let triangleCount: Int
    let glbSha256: String
    let usdzSha256: String

    var semanticBoneNames: [String] { semanticBones.map(\.name) }
    var helperNames: [String] { helpers.map(\.name) }
    var totalBoneCount: Int { semanticBones.count + helpers.count }

    func clip(for sport: Sport) -> ReplayAthleteClipSpec? {
        clips.first { $0.sport == sport }
    }

    func parentName(of bone: String) -> String? {
        if let semantic = semanticBones.first(where: { $0.name == bone }) {
            return semantic.parent
        }
        return helpers.first(where: { $0.name == bone })?.parent
    }

    func restLocalTransform(of bone: String) -> ReplayAthleteRestTransform? {
        if let semantic = semanticBones.first(where: { $0.name == bone }) {
            return semantic.rest
        }
        return helpers.first(where: { $0.name == bone })?.rest
    }

    /// Every skeleton joint the loaded asset must expose (semantic + helper).
    var allBoneNames: [String] { semanticBoneNames + helperNames }
}

/// Source-manifest facts for the reproducible upstream pin, written by
/// `script/sync_rowplay_reference.py`.
struct ReplayAthleteSourceManifest: Equatable, Sendable {
    let pinnedCommit: String
    let contractSchema: String
    let contractSchemaVersion: Int
    let contractSha256: String
    let glbSha256: String
    let usdzSha256: String
    let semanticBoneCount: Int
    let helperCount: Int
    let totalBoneCount: Int
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

/// Source of truth for reference-bundle names and contract parsing.
///
/// Hashes and the pinned commit intentionally live in the bundled source
/// manifests generated by `sync_rowplay_reference.py`.  Runtime validates the
/// bundle against those manifests instead of keeping a second independently
/// editable Swift copy of the same upstream facts.
enum ReplayAthleteCatalog {
    static let athleteSubdirectory = "ReplayReference/athlete"
    static let motionSubdirectory = "ReplayReference/motion"
    static let usdzResourceName = "rowplay-athlete-v4"
    static let usdzExtension = "usdz"
    static let contractResourceName = "rowplay-athlete-v4.contract"
    static let contractExtension = "json"
    static let sourceManifestResourceName = "rowplay-athlete-source"
    static let sourceManifestExtension = "json"
    static let motionBinResourceName = "rowplay-motion"
    static let motionBinExtension = "bin"
    static let motionManifestResourceName = "rowplay-motion-manifest"
    static let motionManifestExtension = "json"

    static let contractSchema = "rowplay.replay.athlete.v4"
    static let contractSchemaVersion = 1
    static let skinnedMeshName = "v4Athlete"

    static let requiredSurfaceRoles: [String] = [
        "athlete-fabric",
        "athlete-skin",
        "athlete-shorts",
        "athlete-footwear",
        "athlete-hair",
        "athlete-trim",
        "athlete-eye",
        "athlete-face-detail",
    ]

    static let contactEntityNames: [String: String] = [
        "left-hand": "v4LeftHandContact",
        "right-hand": "v4RightHandContact",
        "left-foot": "v4LeftFootContact",
        "right-foot": "v4RightFootContact",
    ]

    /// Map canonical contract sport IDs onto native `Sport`.
    static func sport(fromContractSport raw: String) -> Sport? {
        switch raw {
        case "rower":
            .rower
        case "skierg", "skier":
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

    /// Deterministic phase → clip fraction mapping ported from the web V4
    /// adapter: maps the native stroke cycle onto the authored clip's
    /// drive/recovery split without introducing an independent animation
    /// timer.
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

    static func expectedClipName(for sport: Sport) -> String {
        switch sport {
        case .rower:
            "rowplay-v4-row-cycle"
        case .skierg:
            "rowplay-v4-ski-cycle"
        case .bike:
            "rowplay-v4-bike-cycle"
        }
    }

    // MARK: - Contract parsing

    static func parseContract(data: Data) -> Result<ReplayAthleteContract, ReplayAthleteValidationFailure> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.invalidContract("not JSON"))
        }
        guard let schema = root["schema"] as? String,
              schema == contractSchema else {
            return .failure(.invalidContract("schema"))
        }
        guard let schemaVersion = root["schemaVersion"] as? Int,
              schemaVersion == contractSchemaVersion else {
            return .failure(.invalidContract("schemaVersion"))
        }
        guard let bones = root["bones"] as? [String: Any] else {
            return .failure(.invalidContract("bones"))
        }
        guard let hierarchyRaw = bones["hierarchy"] as? [[String: Any]],
              !hierarchyRaw.isEmpty else {
            return .failure(.invalidContract("bones.hierarchy"))
        }
        var semanticBones: [ReplayAthleteBoneSpec] = []
        for raw in hierarchyRaw {
            guard let name = raw["name"] as? String,
                  let rest = parseRestTransform(raw["restLocalTransform"]) else {
                return .failure(.invalidContract("hierarchy entry"))
            }
            guard rest.isFinite else {
                return .failure(.nonFiniteRestTransform(name))
            }
            let parent = raw["parent"] as? String
            semanticBones.append(
                ReplayAthleteBoneSpec(name: name, parent: parent, rest: rest)
            )
        }
        if let declaredOrder = bones["semanticOrderedNames"] as? [String],
           declaredOrder != semanticBones.map(\.name) {
            return .failure(.invalidContract("semantic order drifted from hierarchy"))
        }
        if let semanticCount = bones["semanticCount"] as? Int,
           semanticCount != semanticBones.count {
            return .failure(.boneCountMismatch(actual: semanticBones.count, expected: semanticCount))
        }

        guard let helpersRaw = bones["helpers"] as? [[String: Any]] else {
            return .failure(.invalidContract("bones.helpers"))
        }
        var helpers: [ReplayAthleteHelperSpec] = []
        for raw in helpersRaw {
            guard let name = raw["name"] as? String,
                  let parent = raw["parent"] as? String,
                  let rest = parseRestTransform(raw["restLocalTransform"]) else {
                return .failure(.invalidContract("helper entry"))
            }
            guard rest.isFinite else {
                return .failure(.nonFiniteRestTransform(name))
            }
            let influenced = raw["influencedVertices"] as? Int ?? 0
            helpers.append(
                ReplayAthleteHelperSpec(
                    name: name,
                    parent: parent,
                    rest: rest,
                    influencedVertices: influenced
                )
            )
        }
        if let helperCount = bones["helperCount"] as? Int, helperCount != helpers.count {
            return .failure(.boneCountMismatch(actual: helpers.count, expected: helperCount))
        }
        if let declaredHelperNames = bones["helperNames"] as? [String],
           declaredHelperNames != helpers.map(\.name) {
            return .failure(.invalidContract("helper order drifted"))
        }
        if let totalCount = bones["totalCount"] as? Int,
           totalCount != semanticBones.count + helpers.count {
            return .failure(
                .boneCountMismatch(actual: semanticBones.count + helpers.count, expected: totalCount)
            )
        }
        // Helper parents must resolve inside the combined hierarchy.
        let semanticNames = Set(semanticBones.map(\.name))
        let helperNames = Set(helpers.map(\.name))
        for helper in helpers {
            guard semanticNames.contains(helper.parent) || helperNames.contains(helper.parent) else {
                return .failure(.missingBone(helper.parent))
            }
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
        for sport in [Sport.rower, .skierg, .bike] {
            let matching = clips.filter { $0.sport == sport }
            guard matching.count == 1 else {
                return .failure(.invalidContract("missing or ambiguous \(sport.rawValue) clip"))
            }
            guard matching[0].name == expectedClipName(for: sport) else {
                return .failure(.invalidContract("unexpected \(sport.rawValue) clip name"))
            }
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

        guard let surfacesRaw = root["surfaces"] as? [[String: Any]] else {
            return .failure(.invalidContract("surfaces"))
        }
        var surfaces: [ReplayAthleteSurfaceSpec] = []
        for raw in surfacesRaw {
            guard let role = raw["role"] as? String,
                  let source = raw["source"] as? String else {
                return .failure(.invalidContract("surface entry"))
            }
            surfaces.append(ReplayAthleteSurfaceSpec(role: role, source: source))
        }
        for role in requiredSurfaceRoles where !surfaces.contains(where: { $0.role == role }) {
            return .failure(.invalidContract("missing surface role \(role)"))
        }

        guard let mesh = root["mesh"] as? [String: Any],
              let meshName = mesh["meshName"] as? String,
              let vertices = mesh["vertices"] as? Int,
              let triangles = mesh["triangles"] as? Int,
              let skinnedMeshes = mesh["skinnedMeshes"] as? Int else {
            return .failure(.invalidContract("mesh"))
        }
        guard skinnedMeshes == 1 else {
            return .failure(skinnedMeshes == 0 ? .missingSkinnedAthlete : .multipleSkinnedAthletes)
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
                semanticBones: semanticBones,
                helpers: helpers,
                clips: clips,
                contacts: contacts,
                surfaces: surfaces,
                meshName: meshName,
                vertexCount: vertices,
                triangleCount: triangles,
                glbSha256: glbSha,
                usdzSha256: usdzSha
            )
        )
    }

    private static func parseRestTransform(_ raw: Any?) -> ReplayAthleteRestTransform? {
        guard let dictionary = raw as? [String: Any],
              let translation = dictionary["translation"] as? [Double],
              let rotation = dictionary["rotationQuaternion"] as? [Double],
              let scale = dictionary["scale"] as? [Double],
              translation.count == 3,
              rotation.count == 4,
              scale.count == 3 else {
            return nil
        }
        return ReplayAthleteRestTransform(
            translation: SIMD3(translation[0], translation[1], translation[2]),
            rotation: ReplayQuaternion(
                x: rotation[0],
                y: rotation[1],
                z: rotation[2],
                w: rotation[3]
            ),
            scale: SIMD3(scale[0], scale[1], scale[2])
        )
    }

    // MARK: - Source manifest

    static func parseSourceManifest(data: Data) -> Result<ReplayAthleteSourceManifest, ReplayAthleteValidationFailure> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pinnedCommit = root["pinnedCommit"] as? String,
              let contractSchema = root["contractSchema"] as? String,
              let contractSchemaVersion = root["contractSchemaVersion"] as? Int,
              let contractSha256 = root["contractSha256"] as? String,
              let glbSha256 = root["glbSha256"] as? String,
              let usdzSha256 = root["usdzSha256"] as? String,
              let semanticBoneCount = root["semanticBoneCount"] as? Int,
              let helperCount = root["helperCount"] as? Int,
              let totalBoneCount = root["totalBoneCount"] as? Int else {
            return .failure(.invalidContract("source manifest"))
        }
        return .success(
            ReplayAthleteSourceManifest(
                pinnedCommit: pinnedCommit,
                contractSchema: contractSchema,
                contractSchemaVersion: contractSchemaVersion,
                contractSha256: contractSha256,
                glbSha256: glbSha256,
                usdzSha256: usdzSha256,
                semanticBoneCount: semanticBoneCount,
                helperCount: helperCount,
                totalBoneCount: totalBoneCount
            )
        )
    }

    static func validateSourceManifest(
        _ manifest: ReplayAthleteSourceManifest
    ) -> ReplayAthleteValidationResult {
        var failures: [ReplayAthleteValidationFailure] = []
        if manifest.pinnedCommit.count != 40
            || !manifest.pinnedCommit.allSatisfy({ $0.isHexDigit }) {
            failures.append(.pinMismatch("pinnedCommit"))
        }
        for (name, value) in [
            ("glbSha256", manifest.glbSha256),
            ("usdzSha256", manifest.usdzSha256),
            ("contractSha256", manifest.contractSha256),
        ] {
            if value.count != 64 || !value.allSatisfy({ $0.isHexDigit }) {
                failures.append(.invalidContract("manifest \(name)"))
            }
        }
        if manifest.contractSchema != contractSchema {
            failures.append(.invalidContract("source schema"))
        }
        if manifest.contractSchemaVersion != contractSchemaVersion {
            failures.append(.invalidContract("source schemaVersion"))
        }
        if manifest.totalBoneCount != manifest.semanticBoneCount + manifest.helperCount {
            failures.append(
                .boneCountMismatch(
                    actual: manifest.semanticBoneCount + manifest.helperCount,
                    expected: manifest.totalBoneCount
                )
            )
        }
        return ReplayAthleteValidationResult(failures: failures)
    }

    static func validateContract(
        _ contract: ReplayAthleteContract,
        manifest: ReplayAthleteSourceManifest
    ) -> ReplayAthleteValidationResult {
        var failures: [ReplayAthleteValidationFailure] = []
        if contract.glbSha256 != manifest.glbSha256 {
            failures.append(.hashMismatch(
                resource: "contract.glb",
                expected: manifest.glbSha256,
                actual: contract.glbSha256
            ))
        }
        if contract.usdzSha256 != manifest.usdzSha256 {
            failures.append(.hashMismatch(
                resource: "contract.usdz",
                expected: manifest.usdzSha256,
                actual: contract.usdzSha256
            ))
        }
        if contract.semanticBones.count != manifest.semanticBoneCount {
            failures.append(.boneCountMismatch(
                actual: contract.semanticBones.count,
                expected: manifest.semanticBoneCount
            ))
        }
        if contract.helpers.count != manifest.helperCount {
            failures.append(.boneCountMismatch(
                actual: contract.helpers.count,
                expected: manifest.helperCount
            ))
        }
        return ReplayAthleteValidationResult(failures: failures)
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
