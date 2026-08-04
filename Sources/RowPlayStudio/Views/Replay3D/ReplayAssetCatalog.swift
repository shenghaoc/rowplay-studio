import Foundation
import RowPlayCore

/// The visual source selected for a sport scene.
enum ReplayAssetVisualSource: Equatable, Sendable {
    case procedural
    case bundled
}

/// One converted authored equipment package: a per-sport USDZ produced by
/// `script/convert_rowplay_equipment.py` from the pinned RowPlay V3 GLB, plus
/// its sidecar node/part/material contract.
struct ReplayEquipmentPackageResource: Hashable, Sendable {
    let sport: Sport

    var packageName: String { "rowplay-\(slug)-equipment" }
    var packageExtension: String { "usdz" }
    var contractName: String { "rowplay-\(slug)-equipment.contract" }
    var contractExtension: String { "json" }
    var subdirectory: String { ReplayAssetCatalog.equipmentSubdirectory }

    var slug: String {
        switch sport {
        case .rower: "row"
        case .skierg: "ski"
        case .bike: "bike"
        }
    }
}

/// One node from an equipment sidecar contract.  `sourceName` is the original
/// RowPlay node name (`equipment:row:boat-assembly`); `exportedName` is the
/// USD-safe prim name the converted package actually contains.
struct ReplayEquipmentNodeSpec: Equatable, Sendable {
    let kind: String
    let sourceName: String
    let exportedName: String
    let parts: [ReplayEquipmentPartSpec]
}

struct ReplayEquipmentPartSpec: Equatable, Sendable {
    let part: String
    let sourceName: String
    let exportedName: String
    let materialRole: String?
}

/// Parsed sidecar contract for one sport's converted equipment package.
struct ReplayEquipmentPackageContract: Equatable, Sendable {
    let sport: Sport
    let sourceCommit: String
    let sourceGlbSha256: String
    let nodes: [ReplayEquipmentNodeSpec]

    func node(sourceName: String) -> ReplayEquipmentNodeSpec? {
        nodes.first { $0.sourceName == sourceName }
    }
}

/// One contract entry that a bundled provider must resolve before it can be
/// selected. Composite roots, required parts, and required leaves all share
/// the same runtime geometry invariant.
struct ReplayEquipmentRequiredVisualSpec: Equatable, Sendable {
    let sourceName: String
    let exportedName: String
}

enum ReplayEquipmentContractFailure: Error, Equatable, Sendable {
    case invalidJSON
    case missingField(String)
    case sportMismatch(expected: Sport, actual: String)
    case malformedNode(index: Int, field: String)
    case malformedPart(node: String, index: Int, field: String)
    case missingNode(sourceName: String, expectedKind: String)
    case duplicateNode(sourceName: String)
    case wrongNodeKind(sourceName: String, expected: String, actual: String)
    case missingPart(node: String, part: String)
    case duplicatePart(node: String, part: String)

    var diagnosticCode: String {
        switch self {
        case .invalidJSON: "invalid-json"
        case .missingField: "missing-field"
        case .sportMismatch: "sport-mismatch"
        case .malformedNode: "malformed-node"
        case .malformedPart: "malformed-part"
        case .missingNode: "missing-node"
        case .duplicateNode: "duplicate-node"
        case .wrongNodeKind: "wrong-node-kind"
        case .missingPart: "missing-part"
        case .duplicatePart: "duplicate-part"
        }
    }
}

/// Source of truth for equipment package names and validation.
///
/// Environments are no longer bundled files: the premium venues are built
/// natively by `ReplayEnvironmentBuilder` from the pinned plan and CC0
/// material maps.  Equipment remains an authored conversion of the pinned
/// RowPlay V3 composite GLB.
enum ReplayAssetCatalog {
    static let equipmentSubdirectory = "ReplayReference/equipment"
    static let equipmentManifestName = "rowplay-equipment-manifest"
    static let equipmentManifestExtension = "json"

    static let supportedSports: [Sport] = [.rower, .skierg, .bike]

    /// Composite template roots each sport's package must contain, mirrored
    /// from the pinned `validate-replay-assets.mjs`.
    static func requiredCompositeSourceNames(for sport: Sport) -> [String] {
        switch sport {
        case .rower:
            [
                "equipment:row:boat-assembly",
                "equipment:row:seat-carriage",
                "equipment:row:oar-rig",
            ]
        case .skierg:
            ["equipment:ski:ski-assembly"]
        case .bike:
            [
                "equipment:bike:wheel-assembly",
                "equipment:bike:frame-assembly",
                "equipment:bike:drivetrain-assembly",
            ]
        }
    }

    /// Leaf slots each sport still consumes (SkiErg poles have no composite).
    static func requiredLeafSourceNames(for sport: Sport) -> [String] {
        switch sport {
        case .rower:
            ["equipment:row:blade"]
        case .skierg:
            [
                "equipment:ski:pole-shaft",
                "equipment:ski:pole-grip",
                "equipment:ski:pole-basket",
            ]
        case .bike:
            []
        }
    }

    /// Required parts per composite, mirrored from the pinned validator.
    static let requiredParts: [String: Set<String>] = [
        "equipment:row:boat-assembly": [
            "hull", "stern-deck", "bow-deck", "cockpit-tub", "bulkheads", "gunwales",
            "slide-rails", "accent-strakes", "foot-stretcher", "heel-cups",
            "stretcher-hardware", "riggers", "oarlocks", "keel-fin",
        ],
        "equipment:row:seat-carriage": ["seat-pad", "seat-carriage", "seat-rollers", "seat-guides"],
        "equipment:row:oar-rig": ["shaft", "grip", "handle-cap", "collar", "blade-sleeve"],
        "equipment:ski:ski-assembly": [
            "base", "top-deck", "edge-left", "edge-right", "binding-plate",
            "binding-toe", "binding-heel", "tip-ridge",
        ],
        "equipment:bike:wheel-assembly": ["tyre", "aero-rim", "hub", "brake-rotor", "spokes"],
        "equipment:bike:frame-assembly": [
            "main-triangle", "stays-and-fork", "cockpit", "brake-hoods", "brake-levers",
            "brake-calipers", "chain-and-cassette", "saddle", "seat-post", "fork-crown",
            "rear-axle", "front-axle",
        ],
        "equipment:bike:drivetrain-assembly": [
            "chainring", "spider", "crank-arms", "clipless-pedals", "bottom-bracket",
        ],
    ]

    /// Authored equipment is used where current RowPlay uses it: the High and
    /// Ultra tiers.  Low and Medium render native procedural equipment built
    /// from the same portable dimensional contracts.
    static func bundledVisualsAreEligible(at quality: ReplayRenderQuality) -> Bool {
        quality == .high || quality == .ultra
    }

    /// Bundled equipment is intentionally selected only at High and Ultra.
    /// Low and Medium use the dimensional procedural renderer; at High and
    /// Ultra that same renderer is the coherent load/runtime-failure fallback.
    static func visualSource(
        for effectiveQuality: ReplayRenderQuality,
        assetSetIsValid: Bool
    ) -> ReplayAssetVisualSource {
        bundledVisualsAreEligible(at: effectiveQuality) && assetSetIsValid
            ? .bundled
            : .procedural
    }

    static func parsePackageContract(
        data: Data,
        sport: Sport
    ) -> Result<ReplayEquipmentPackageContract, ReplayEquipmentContractFailure> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.invalidJSON)
        }
        guard let rawSport = root["sport"] as? String else {
            return .failure(.missingField("sport"))
        }
        let expectedSport = ReplayEquipmentPackageResource(sport: sport).slug
        guard rawSport == expectedSport else {
            return .failure(.sportMismatch(expected: sport, actual: rawSport))
        }
        guard let sourceCommit = root["sourceCommit"] as? String else {
            return .failure(.missingField("sourceCommit"))
        }
        guard let sourceGlbSha256 = root["sourceGlbSha256"] as? String else {
            return .failure(.missingField("sourceGlbSha256"))
        }
        guard let rawNodes = root["nodes"] as? [[String: Any]] else {
            return .failure(.missingField("nodes"))
        }
        var nodes: [ReplayEquipmentNodeSpec] = []
        for (nodeIndex, raw) in rawNodes.enumerated() {
            guard let kind = raw["kind"] as? String else {
                return .failure(.malformedNode(index: nodeIndex, field: "kind"))
            }
            guard let sourceName = raw["sourceName"] as? String else {
                return .failure(.malformedNode(index: nodeIndex, field: "sourceName"))
            }
            guard let exportedName = raw["exportedName"] as? String else {
                return .failure(.malformedNode(index: nodeIndex, field: "exportedName"))
            }
            var parts: [ReplayEquipmentPartSpec] = []
            if let rawParts = raw["parts"] as? [[String: Any]] {
                for (partIndex, rawPart) in rawParts.enumerated() {
                    guard let part = rawPart["part"] as? String else {
                        return .failure(.malformedPart(
                            node: sourceName,
                            index: partIndex,
                            field: "part"
                        ))
                    }
                    guard let partSource = rawPart["sourceName"] as? String else {
                        return .failure(.malformedPart(
                            node: sourceName,
                            index: partIndex,
                            field: "sourceName"
                        ))
                    }
                    guard let partExported = rawPart["exportedName"] as? String else {
                        return .failure(.malformedPart(
                            node: sourceName,
                            index: partIndex,
                            field: "exportedName"
                        ))
                    }
                    parts.append(
                        ReplayEquipmentPartSpec(
                            part: part,
                            sourceName: partSource,
                            exportedName: partExported,
                            materialRole: rawPart["materialRole"] as? String
                        )
                    )
                }
            }
            nodes.append(
                ReplayEquipmentNodeSpec(
                    kind: kind,
                    sourceName: sourceName,
                    exportedName: exportedName,
                    parts: parts
                )
            )
        }
        return .success(ReplayEquipmentPackageContract(
            sport: sport,
            sourceCommit: sourceCommit,
            sourceGlbSha256: sourceGlbSha256,
            nodes: nodes
        ))
    }

    /// Validate one sport's sidecar and return the complete runtime visual set.
    /// The provider resolves this exact list before bundled mode can activate.
    static func requiredVisuals(
        in contract: ReplayEquipmentPackageContract
    ) -> Result<[ReplayEquipmentRequiredVisualSpec], ReplayEquipmentContractFailure> {
        var visuals: [ReplayEquipmentRequiredVisualSpec] = []
        let nodesByName = Dictionary(grouping: contract.nodes, by: \.sourceName)

        for composite in requiredCompositeSourceNames(for: contract.sport) {
            guard let matches = nodesByName[composite], !matches.isEmpty else {
                return .failure(.missingNode(sourceName: composite, expectedKind: "composite"))
            }
            guard matches.count == 1, let node = matches.first else {
                return .failure(.duplicateNode(sourceName: composite))
            }
            guard node.kind == "composite" else {
                return .failure(.wrongNodeKind(
                    sourceName: composite,
                    expected: "composite",
                    actual: node.kind
                ))
            }
            guard let required = requiredParts[composite] else {
                return .failure(.missingField("requiredParts.\(composite)"))
            }
            let partsByID = Dictionary(grouping: node.parts, by: \.part)
            if let duplicate = partsByID.first(where: { $0.value.count > 1 })?.key {
                return .failure(.duplicatePart(node: composite, part: duplicate))
            }
            visuals.append(ReplayEquipmentRequiredVisualSpec(
                sourceName: node.sourceName,
                exportedName: node.exportedName
            ))
            for partID in required.sorted() {
                guard let part = partsByID[partID]?.first else {
                    return .failure(.missingPart(node: composite, part: partID))
                }
                visuals.append(ReplayEquipmentRequiredVisualSpec(
                    sourceName: part.sourceName,
                    exportedName: part.exportedName
                ))
            }
        }
        for leaf in requiredLeafSourceNames(for: contract.sport) {
            guard let matches = nodesByName[leaf], !matches.isEmpty else {
                return .failure(.missingNode(sourceName: leaf, expectedKind: "leaf"))
            }
            guard matches.count == 1, let node = matches.first else {
                return .failure(.duplicateNode(sourceName: leaf))
            }
            guard node.kind == "leaf" else {
                return .failure(.wrongNodeKind(
                    sourceName: leaf,
                    expected: "leaf",
                    actual: node.kind
                ))
            }
            visuals.append(ReplayEquipmentRequiredVisualSpec(
                sourceName: node.sourceName,
                exportedName: node.exportedName
            ))
        }
        return .success(visuals)
    }

    /// Validate one sport's sidecar against the required template tables.
    static func validatePackageContract(
        _ contract: ReplayEquipmentPackageContract
    ) -> Result<Void, ReplayEquipmentContractFailure> {
        requiredVisuals(in: contract).map { _ in () }
    }
}
