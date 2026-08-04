import Foundation
import RowPlayCore
import simd

enum ReplayAthleteContactRole: String, CaseIterable, Sendable {
    case leftHand = "left-hand"
    case rightHand = "right-hand"
    case leftFoot = "left-foot"
    case rightFoot = "right-foot"
}

/// A contact role authored on the V4 contract.
struct ReplayAthleteContactSpec: Equatable, Sendable {
    let bone: String
    let role: ReplayAthleteContactRole
    let localOffset: SIMD3<Double>
}

/// Runtime interpretation of one validated authored contact.
///
/// The pinned athlete contract keeps its sport-neutral palm points as source
/// provenance. Runtime hand solving is channel-native because each equipment
/// surface has a different grip radius; sole contacts continue to use the
/// authored contract point directly.
enum ReplayAthleteRuntimeContactModel: Equatable, Sendable {
    case sportGripChannel
    case authoredSole
}

struct ReplayAthleteResolvedContactSpec: Equatable, Sendable {
    let bone: String
    let role: ReplayAthleteContactRole
    let localOffset: SIMD3<Double>
    let model: ReplayAthleteRuntimeContactModel
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

/// The eight reviewed vertex-colour regions carried by the canonical V4
/// athlete. The native derivative preserves this exact order as material
/// subsets while the source contract keeps its own declaration order.
enum ReplayAthleteSurfaceRole: String, CaseIterable, Hashable, Sendable {
    case skin = "athlete-skin"
    case jersey = "athlete-fabric"
    case lower = "athlete-shorts"
    case footwear = "athlete-footwear"
    case hair = "athlete-hair"
    case trim = "athlete-trim"
    case eye = "athlete-eye"
    case faceDetail = "athlete-face-detail"

    var runtimeMaterialName: String {
        switch self {
        case .skin: "rowplay-v4-skin"
        case .jersey: "rowplay-v4-jersey"
        case .lower: "rowplay-v4-lower"
        case .footwear: "rowplay-v4-footwear"
        case .hair: "rowplay-v4-hair"
        case .trim: "rowplay-v4-trim"
        case .eye: "rowplay-v4-eye"
        case .faceDetail: "rowplay-v4-face-detail"
        }
    }
}

/// Reproducible manifest for the native material-subset derivative. Geometry,
/// skinning, contacts, and animation stay in the pinned USDZ; only the pinned
/// GLB's reviewed vertex colours become RealityKit-addressable material slots.
struct ReplayAthleteNativeManifest: Equatable, Sendable {
    let schema: String
    let sourceCommit: String
    let sourceGlbSha256: String
    let sourceUsdzSha256: String
    let sourceContractSha256: String
    let runtimeUsdzSha256: String
    let runtimeUsdzByteCount: Int
    let skinnedMeshCount: Int
    let materialSlotCount: Int
    let surfaceRoles: [ReplayAthleteSurfaceRole]
    let runtimeMaterialNames: [String]
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
    case unreadableResource(String)
    case hashMismatch(resource: String, expected: String, actual: String)
    case invalidContract(String)
    case invalidMotionManifest(String)
    case motionTableLoad(ReplayAthleteMotionTable.LoadError)
    case byteCountMismatch(resource: String, expected: Int, actual: Int)
    case missingBone(String)
    case duplicateBone(String)
    case boneCountMismatch(actual: Int, expected: Int)
    case jointCountMismatch(actual: Int, expected: Int)
    case missingClip(Sport)
    case invalidClipTiming(Sport)
    case missingContact(String)
    case duplicateContact(String)
    case nonFiniteRestTransform(String)
    case nonFiniteJointTransform(String)
    case missingSkinnedAthlete
    case multipleSkinnedAthletes
    case missingModelComponent
    case surfaceCountMismatch(actual: Int, expected: Int)
    case missingSkeletalPose
    case missingAnimation
    case invalidRuntimeAsset
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
    static let nativeUsdzResourceName = "rowplay-athlete-v4-native"
    static let nativeUsdzExtension = "usdz"
    static let nativeManifestResourceName = "rowplay-athlete-v4-native"
    static let nativeManifestExtension = "json"
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

    static let requiredSurfaceRoles = ReplayAthleteSurfaceRole.allCases.map(\.rawValue)

    static let nativeManifestSchema = "rowplay.replay.athlete-native.v1"

    static let contactEntityNames: [ReplayAthleteContactRole: String] = [
        .leftHand: "v4LeftHandContact",
        .rightHand: "v4RightHandContact",
        .leftFoot: "v4LeftFootContact",
        .rightFoot: "v4RightFootContact",
    ]

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
                  let sport = ReplayAthleteMotionTable.sport(fromManifestName: sportRaw),
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
                  let roleRaw = raw["role"] as? String,
                  let role = ReplayAthleteContactRole(rawValue: roleRaw),
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
        let allBoneNames = semanticNames.union(helperNames)
        for contact in contacts where !allBoneNames.contains(contact.bone) {
            return .failure(.missingBone(contact.bone))
        }
        for role in ReplayAthleteContactRole.allCases {
            let count = contacts.filter { $0.role == role }.count
            if count == 0 { return .failure(.missingContact(role.rawValue)) }
            if count > 1 { return .failure(.duplicateContact(role.rawValue)) }
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

    // MARK: - Native material derivative

    static func parseNativeManifest(
        data: Data
    ) -> Result<ReplayAthleteNativeManifest, ReplayAthleteValidationFailure> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schema = root["schema"] as? String,
              let sourceCommit = root["sourceCommit"] as? String,
              let sourceGlbSha256 = root["sourceGlbSha256"] as? String,
              let sourceUsdzSha256 = root["sourceUsdzSha256"] as? String,
              let sourceContractSha256 = root["sourceContractSha256"] as? String,
              let runtimeUsdzSha256 = root["runtimeUsdzSha256"] as? String,
              let runtimeUsdzByteCount = root["runtimeUsdzByteCount"] as? Int,
              let skinnedMeshCount = root["skinnedMeshCount"] as? Int,
              let materialSlotCount = root["materialSlotCount"] as? Int,
              let surfaceRoleNames = root["surfaceRoles"] as? [String],
              let runtimeMaterialNames = root["runtimeMaterialNames"] as? [String] else {
            return .failure(.invalidContract("native manifest"))
        }
        var roles: [ReplayAthleteSurfaceRole] = []
        for raw in surfaceRoleNames {
            guard let role = ReplayAthleteSurfaceRole(rawValue: raw) else {
                return .failure(.invalidContract("native surface role \(raw)"))
            }
            guard !roles.contains(role) else {
                return .failure(.invalidContract("duplicate native surface role \(raw)"))
            }
            roles.append(role)
        }
        return .success(ReplayAthleteNativeManifest(
            schema: schema,
            sourceCommit: sourceCommit,
            sourceGlbSha256: sourceGlbSha256,
            sourceUsdzSha256: sourceUsdzSha256,
            sourceContractSha256: sourceContractSha256,
            runtimeUsdzSha256: runtimeUsdzSha256,
            runtimeUsdzByteCount: runtimeUsdzByteCount,
            skinnedMeshCount: skinnedMeshCount,
            materialSlotCount: materialSlotCount,
            surfaceRoles: roles,
            runtimeMaterialNames: runtimeMaterialNames
        ))
    }

    static func validateNativeManifest(
        _ native: ReplayAthleteNativeManifest,
        source: ReplayAthleteSourceManifest,
        contract: ReplayAthleteContract
    ) -> ReplayAthleteValidationResult {
        var failures: [ReplayAthleteValidationFailure] = []
        if native.schema != nativeManifestSchema {
            failures.append(.invalidContract("native schema"))
        }
        if native.sourceCommit != source.pinnedCommit {
            failures.append(.pinMismatch("native.sourceCommit"))
        }
        if native.sourceGlbSha256 != source.glbSha256
            || native.sourceGlbSha256 != contract.glbSha256 {
            failures.append(.pinMismatch("native.sourceGlbSha256"))
        }
        if native.sourceUsdzSha256 != source.usdzSha256
            || native.sourceUsdzSha256 != contract.usdzSha256 {
            failures.append(.pinMismatch("native.sourceUsdzSha256"))
        }
        if native.sourceContractSha256 != source.contractSha256 {
            failures.append(.pinMismatch("native.sourceContractSha256"))
        }
        if native.skinnedMeshCount != 1 {
            failures.append(native.skinnedMeshCount == 0
                ? .missingSkinnedAthlete
                : .multipleSkinnedAthletes)
        }
        let expectedRoles = ReplayAthleteSurfaceRole.allCases
        if native.surfaceRoles != expectedRoles {
            failures.append(.invalidContract("native surface role order"))
        }
        if native.runtimeMaterialNames != expectedRoles.map(\.runtimeMaterialName) {
            failures.append(.invalidContract("native material name order"))
        }
        if native.materialSlotCount != expectedRoles.count {
            failures.append(.surfaceCountMismatch(
                actual: native.materialSlotCount,
                expected: expectedRoles.count
            ))
        }
        if Set(contract.surfaces.map(\.role)) != Set(expectedRoles.map(\.rawValue)) {
            failures.append(.invalidContract("contract surface roles"))
        }
        for (name, value) in [
            ("native.sourceUsdzSha256", native.sourceUsdzSha256),
            ("native.sourceContractSha256", native.sourceContractSha256),
            ("native.runtimeUsdzSha256", native.runtimeUsdzSha256),
        ] where value.count != 64 || !value.allSatisfy({ $0.isHexDigit }) {
            failures.append(.invalidContract(name))
        }
        if native.runtimeUsdzByteCount <= 0 {
            failures.append(.invalidContract("native runtimeUsdzByteCount"))
        }
        return ReplayAthleteValidationResult(failures: failures)
    }

    static func validateContract(
        _ contract: ReplayAthleteContract,
        manifest: ReplayAthleteSourceManifest
    ) -> ReplayAthleteValidationResult {
        var failures: [ReplayAthleteValidationFailure] = []
        if contract.meshName != skinnedMeshName {
            failures.append(.invalidContract("mesh.meshName"))
        }
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

    // MARK: - Motion manifest

    static func parseMotionManifest(
        data: Data
    ) -> Result<ReplayAthleteMotionTable.Manifest, ReplayAthleteValidationFailure> {
        do {
            return .success(try ReplayAthleteMotionTable.parseManifest(data: data))
        } catch let error as ReplayAthleteMotionTable.LoadError {
            return .failure(.motionTableLoad(error))
        } catch {
            return .failure(.invalidMotionManifest("unrecognized load error"))
        }
    }

    static func validateMotionManifest(
        _ motion: ReplayAthleteMotionTable.Manifest,
        source: ReplayAthleteSourceManifest,
        binData: Data
    ) -> ReplayAthleteValidationResult {
        var failures: [ReplayAthleteValidationFailure] = []
        if motion.sourceCommit != source.pinnedCommit {
            failures.append(.pinMismatch("motion.sourceCommit"))
        }
        if motion.sourceGlbSha256 != source.glbSha256 {
            failures.append(.pinMismatch("motion.sourceGlbSha256"))
        }
        guard let byteCount = motion.motionBinByteCount, byteCount > 0 else {
            return ReplayAthleteValidationResult(
                failures: failures + [.invalidMotionManifest("motionBinByteCount")]
            )
        }
        if byteCount != binData.count {
            failures.append(.byteCountMismatch(
                resource: "motion.bin",
                expected: byteCount,
                actual: binData.count
            ))
        }
        let actualHash = ReplayBundledResourceSupport.sha256Hex(of: binData)
        guard let expectedHash = motion.motionBinSha256, !expectedHash.isEmpty else {
            return ReplayAthleteValidationResult(
                failures: failures + [.invalidMotionManifest("motionBinSha256")]
            )
        }
        if expectedHash != actualHash {
            failures.append(.hashMismatch(
                resource: "motion.bin",
                expected: expectedHash,
                actual: actualHash
            ))
        }
        return ReplayAthleteValidationResult(failures: failures)
    }

}
