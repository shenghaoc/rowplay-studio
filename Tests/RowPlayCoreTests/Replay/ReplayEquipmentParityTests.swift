import Foundation
import XCTest
@testable import RowPlayCore

final class ReplayEquipmentParityTests: XCTestCase {
    func testPinnedEquipmentMetadataAndSampleCountsAreSealed() throws {
        let root = try fixtureRoot()
        XCTAssertEqual(root["schema"] as? String, "rowplay.replay.current-main.equipment-parity.v1")
        XCTAssertEqual(root["generatorVersion"] as? String, "export_rowplay_native_parity/1.0.0")
        XCTAssertEqual(
            root["sourceCommit"] as? String,
            "4d96480e7c6fb382f800555bd3aa463d9fe5b1a6"
        )

        let sourceHashes = try dictionary(root, "sourceFileSha256s")
        XCTAssertEqual(sourceHashes.count, 9)
        XCTAssertTrue(sourceHashes.values.allSatisfy {
            guard let hash = $0 as? String else { return false }
            return hash.count == 64 && hash.allSatisfy(\.isHexDigit)
        })

        let samples = try dictionary(root, "samples")
        XCTAssertEqual(try array(samples, "oarYaw").count, 20)
        XCTAssertEqual(try array(samples, "elbowFlexion").count, 10)
        XCTAssertEqual(try array(samples, "reachForFlexion").count, 10)
        XCTAssertEqual(try array(samples, "bikeKneeFlexion").count, 16)
        XCTAssertEqual(try array(samples, "skierElbowDirection").count, 32)

        let saddle = try dictionary(samples, "saddleDrop")
        let saddleGridCount = try array(saddle, "xs").count * array(saddle, "zs").count
        XCTAssertEqual(saddleGridCount, 165)
        XCTAssertEqual(try int(root, "sampleCount"), 253)
        XCTAssertEqual(20 + 10 + 10 + 16 + saddleGridCount + 32, 253)
    }

    func testPinnedEquipmentConstantTreesMatchPortableContracts() throws {
        let root = try fixtureRoot()
        try assertRowConstants(in: dictionary(root, "row"))
        try assertSkiConstants(in: dictionary(root, "ski"))
        try assertBikeConstants(in: dictionary(root, "bike"))
        try assertSaddleConstants(in: dictionary(root, "saddle"))
    }

    func testPinnedOarYawSamplesMatchPortableSolver() throws {
        let samples = try sampleArray("oarYaw")
        for (index, raw) in samples.enumerated() {
            let sample = try castDictionary(raw, "oarYaw[\(index)]")
            let input = try dictionary(sample, "input")
            let shoulder = try vector(input, "shoulder")
            let actual = ReplayRowGripContract.solveOarYaw(
                shoulder: SIMD3(shoulder[0], shoulder[1], shoulder[2]),
                pinX: try double(input, "pinX"),
                pinY: try double(input, "pinY"),
                pinZ: try double(input, "pinZ"),
                signedInboard: try double(input, "signedInboard"),
                bladeRoll: try double(input, "bladeRoll"),
                requestedReach: try double(input, "requestedReach"),
                preferredYaw: try double(input, "preferredYaw"),
                forceReachBoundary: try bool(input, "forceReachBoundary")
            )
            XCTAssertEqual(actual, try double(sample, "output"), accuracy: 1e-12, "sample \(index)")
        }
    }

    func testPinnedElbowFlexionSamplesMatchPortableSolver() throws {
        for (index, raw) in try sampleArray("elbowFlexion").enumerated() {
            let sample = try castDictionary(raw, "elbowFlexion[\(index)]")
            let actual = ReplayRowGripContract.elbowFlexion(
                chordLength: try double(sample, "chordLength"),
                upperArmLength: try double(sample, "upperArmLength"),
                forearmLength: try double(sample, "forearmLength")
            )
            XCTAssertEqual(actual, try double(sample, "output"), accuracy: 1e-12, "sample \(index)")
        }
    }

    func testPinnedReachForFlexionSamplesMatchPortableSolver() throws {
        for (index, raw) in try sampleArray("reachForFlexion").enumerated() {
            let sample = try castDictionary(raw, "reachForFlexion[\(index)]")
            let actual = ReplayRowGripContract.reachForFlexion(
                try double(sample, "flexion"),
                upperArmLength: try double(sample, "upperArmLength"),
                forearmLength: try double(sample, "forearmLength")
            )
            XCTAssertEqual(actual, try double(sample, "output"), accuracy: 1e-12, "sample \(index)")
        }
    }

    func testPinnedBikeKneeFlexionSamplesMatchPortableSolver() throws {
        for (index, raw) in try sampleArray("bikeKneeFlexion").enumerated() {
            let sample = try castDictionary(raw, "bikeKneeFlexion[\(index)]")
            let actual = ReplayBikeGripContract.kneeFlexion(
                atCrankAngle: try double(sample, "angle")
            )
            XCTAssertEqual(actual, try double(sample, "output"), accuracy: 1e-12, "sample \(index)")
        }
    }

    func testPinnedSaddleDropGridMatchesPortableSolver() throws {
        let samples = try dictionary(dictionary(try fixtureRoot(), "samples"), "saddleDrop")
        let xs = try vector(samples, "xs")
        let zs = try vector(samples, "zs")
        let rows = try array(samples, "drops")
        XCTAssertEqual(rows.count, zs.count)

        for (zIndex, rawRow) in rows.enumerated() {
            let expectedRow = try castArray(rawRow, "saddleDrop.drops[\(zIndex)]")
            XCTAssertEqual(expectedRow.count, xs.count)
            for (xIndex, expected) in expectedRow.enumerated() {
                let actual = ReplayBikeSaddle.drop(atX: xs[xIndex], z: zs[zIndex])
                if expected is NSNull {
                    XCTAssertNil(actual, "grid [\(zIndex)][\(xIndex)]")
                } else {
                    XCTAssertEqual(
                        try XCTUnwrap(actual),
                        try number(expected, "saddleDrop.drops[\(zIndex)][\(xIndex)]"),
                        accuracy: 1e-12
                    )
                }
            }
        }
    }

    func testPinnedSkierElbowSamplesMatchMotionAndPortableSolver() throws {
        for (index, raw) in try sampleArray("skierElbowDirection").enumerated() {
            let sample = try castDictionary(raw, "skierElbowDirection[\(index)]")
            let pose = try strokePose(dictionary(sample, "pose"))
            let expectedKinematics = try dictionary(sample, "kinematics")
            let actualKinematics = ReplaySportKinematics.solveSkier(pose)
            try assertSkierKinematics(actualKinematics, equals: expectedKinematics, sample: index)

            let expectedDirection = try dictionary(sample, "direction")
            let actualDirection = ReplaySportKinematics.solveSkierElbowDirection(actualKinematics)
            XCTAssertEqual(
                actualDirection.vertical,
                try double(expectedDirection, "vertical"),
                accuracy: 1e-12,
                "sample \(index)"
            )
            XCTAssertEqual(
                actualDirection.foreAft,
                try double(expectedDirection, "foreAft"),
                accuracy: 1e-12,
                "sample \(index)"
            )
        }
    }

    private func assertRowConstants(in row: [String: Any]) throws {
        try assertDoubles(dictionary(row, "footContact"), [
            "lateral": ReplayRowGripContract.footContact.lateral,
            "y": ReplayRowGripContract.footContact.y,
            "z": ReplayRowGripContract.footContact.z,
        ])
        try assertDoubles(dictionary(row, "stretcher"), [
            "centerY": ReplayRowGripContract.stretcher.centerY,
            "centerZ": ReplayRowGripContract.stretcher.centerZ,
            "boardRotation": ReplayRowGripContract.stretcher.boardRotation,
            "shoeCatchPitch": ReplayRowGripContract.stretcher.shoeCatchPitch,
            "shoeFinishPitch": ReplayRowGripContract.stretcher.shoeFinishPitch,
        ])
        try assertDoubles(dictionary(row, "scullGrip"), [
            "radius": ReplayRowGripContract.scullGrip.radius,
            "length": ReplayRowGripContract.scullGrip.length,
            "anchorFromEnd": ReplayRowGripContract.scullGrip.anchorFromEnd,
        ])
        try assertDoubles(dictionary(row, "oarlock"), [
            "lateral": ReplayRowGripContract.oarlock.lateral,
            "y": ReplayRowGripContract.oarlock.y,
            "z": ReplayRowGripContract.oarlock.z,
        ])
        try assertDoubles(dictionary(row, "elbowCorridor"), [
            "maxOutboard": ReplayRowGripContract.elbowCorridor.maxOutboard,
            "maxInboard": ReplayRowGripContract.elbowCorridor.maxInboard,
            "maxBehindShoulder": ReplayRowGripContract.elbowCorridor.maxBehindShoulder,
            "maxOutboardPerRearward": ReplayRowGripContract.elbowCorridor.maxOutboardPerRearward,
        ])
        let plane = try dictionary(row, "elbowPlane")
        try assertDoubles(plane, [
            "authorityStart": ReplayRowGripContract.elbowPlane.authorityStart,
            "authorityFull": ReplayRowGripContract.elbowPlane.authorityFull,
            "drawnOutboardWeight": ReplayRowGripContract.elbowPlane.drawnOutboardWeight,
            "drawnDownWeight": ReplayRowGripContract.elbowPlane.drawnDownWeight,
        ], exactKeys: false)
        try assertVector(dictionary(plane, "relaxed"), equals: ReplayRowGripContract.elbowPlane.relaxed)
        try assertVector(dictionary(plane, "drawn"), equals: ReplayRowGripContract.elbowPlane.drawn)
        XCTAssertEqual(try double(row, "drawFinishFlexion"), ReplayRowGripContract.drawFinishFlexion)
        XCTAssertEqual(try double(row, "drawSoftFlexion"), ReplayRowGripContract.drawSoftFlexion)
    }

    private func assertSkiConstants(in ski: [String: Any]) throws {
        let athlete = ReplaySkiGripContract.athleteProportions
        try assertDoubles(dictionary(ski, "athleteProportions"), [
            "standingHeight": athlete.standingHeight,
            "shoulderHalfWidth": athlete.shoulderHalfWidth,
            "hipHalfWidth": athlete.hipHalfWidth,
            "upperArmLength": athlete.upperArmLength,
            "forearmLength": athlete.forearmLength,
            "thighLength": athlete.thighLength,
            "shinLength": athlete.shinLength,
            "skiCenterOffset": athlete.skiCenterOffset,
            "skiLength": athlete.skiLength,
            "skiWidth": athlete.skiWidth,
            "poleLength": athlete.poleLength,
            "polePlantLateralOffset": athlete.polePlantLateralOffset,
            "polePlantForwardOffset": athlete.polePlantForwardOffset,
        ])
        XCTAssertEqual(try double(ski, "gripShift"), ReplaySkiGripContract.gripShift)
        XCTAssertEqual(try double(ski, "poleGripRadius"), ReplaySkiGripContract.poleGripRadius)
        XCTAssertEqual(try double(ski, "poleThumbOppose"), ReplaySkiGripContract.poleThumbOppose)

        let details = try dictionary(ski, "equipmentDetail")
        for quality in ReplayRenderQuality.allCases {
            let expected = ReplaySkiGripContract.equipmentDetail(for: quality)
            let actual = try dictionary(details, quality.rawValue)
            XCTAssertEqual(try int(actual, "radialSegments"), expected.radialSegments)
            XCTAssertEqual(try bool(actual, "topSheet"), expected.topSheet)
            XCTAssertEqual(try bool(actual, "metalEdges"), expected.metalEdges)
            XCTAssertEqual(try bool(actual, "bindingRails"), expected.bindingRails)
            XCTAssertEqual(try bool(actual, "bootClosures"), expected.bootClosures)
            XCTAssertEqual(try bool(actual, "gripStraps"), expected.gripStraps)
            XCTAssertEqual(try bool(actual, "basketRibs"), expected.basketRibs)
        }
    }

    private func assertBikeConstants(in bike: [String: Any]) throws {
        let rig = try dictionary(bike, "rig")
        try assertDoubles(rig, [
            "wheelRadius": ReplayBikeGripContract.wheelRadius,
            "tyreTube": ReplayBikeGripContract.tyreTube,
            "frontAxleZ": ReplayBikeGripContract.frontAxleZ,
            "rearAxleZ": ReplayBikeGripContract.rearAxleZ,
            "saddlePadHalfHeight": ReplayBikeGripContract.saddlePadHalfHeight,
            "saddleClampZ": ReplayBikeGripContract.saddleClampZ,
        ], exactKeys: false)
        try assertVector(array(rig, "bottomBracket"), equals: SIMD3(0, ReplayBikeGripContract.bbY, ReplayBikeGripContract.bbZ))
        try assertVector(array(rig, "seatCluster"), equals: SIMD3(0, ReplayBikeGripContract.seatClusterY, ReplayBikeGripContract.seatClusterZ))
        try assertVector(array(rig, "saddleClamp"), equals: SIMD3(0, ReplayBikeGripContract.saddleClampY, ReplayBikeGripContract.saddleZ + ReplayBikeGripContract.saddleClampZ))
        try assertVector(array(rig, "headBottom"), equals: SIMD3(0, ReplayBikeGripContract.headBottomY, ReplayBikeGripContract.headBottomZ))
        try assertVector(array(rig, "headTop"), equals: SIMD3(0, ReplayBikeGripContract.headTopY, ReplayBikeGripContract.headTopZ))
        try assertVector(array(rig, "saddle"), equals: SIMD3(0, ReplayBikeGripContract.saddleY, ReplayBikeGripContract.saddleZ))

        let handlebar = try dictionary(rig, "handlebar")
        try assertVector(array(handlebar, "base"), equals: ReplayBikeGripContract.handlebarBase)
        try assertDoubles(dictionary(handlebar, "grip"), [
            "y": ReplayBikeGripContract.handlebarGripY,
            "z": ReplayBikeGripContract.handlebarGripZ,
            "halfSpan": ReplayBikeGripContract.handlebarGripHalfSpan,
        ])
        try assertDoubles(dictionary(handlebar, "hood"), [
            "rotationX": ReplayBikeGripContract.hoodRotationX,
            "radius": ReplayBikeGripContract.hoodRadius,
        ])
        try assertDoubles(dictionary(rig, "crank"), [
            "lateral": ReplayBikeGripContract.crankLateral,
            "pedalRadius": ReplayBikeGripContract.crankRadius,
        ])
        let rider = try dictionary(rig, "rider")
        try assertVector(array(rider, "root"), equals: ReplayBikeGripContract.riderRoot)
        try assertVector(array(rider, "pelvisOffset"), equals: ReplayBikeGripContract.riderPelvisOffset)
        try assertVector(array(rider, "sitSurfaceFromHip"), equals: SIMD3(
            0,
            ReplayBikeGripContract.sitSurfaceFromHipY,
            ReplayBikeGripContract.sitContactZFromHip
        ))
        try assertDoubles(rider, [
            "perineumFromHipY": ReplayBikeGripContract.perineumFromHipY,
            "sitNestle": ReplayBikeGripContract.sitNestle,
            "kneeFlexionAtBdc": ReplayBikeGripContract.kneeFlexionAtBDC,
        ], exactKeys: false)
        try assertDoubles(dictionary(rig, "athlete"), [
            "thigh": ReplayBikeGripContract.athleteThigh,
            "shin": ReplayBikeGripContract.athleteShin,
            "soleDrop": ReplayBikeGripContract.athleteSoleDrop,
        ])
        // These derived lengths cross JavaScript fixture generation and Swift
        // runtime arithmetic. Equivalent operations may differ by a few ULPs
        // across toolchains; one picometre still detects any geometry drift.
        let derivedLengthAccuracy = 1e-12
        XCTAssertEqual(
            try double(bike, "wheelAxleY"),
            ReplayBikeGripContract.wheelAxleY(),
            accuracy: derivedLengthAccuracy
        )
        XCTAssertEqual(
            try double(bike, "saddleTopY"),
            ReplayBikeGripContract.saddleTopY(),
            accuracy: derivedLengthAccuracy
        )
        XCTAssertEqual(
            try double(bike, "riderHipY"),
            ReplayBikeGripContract.derivedRiderHipY(),
            accuracy: derivedLengthAccuracy
        )
    }

    private func assertSaddleConstants(in saddle: [String: Any]) throws {
        try assertDoubles(saddle, [
            "shellThickness": ReplayBikeSaddle.shellThickness,
            "rearZ": ReplayBikeSaddle.rearZ,
            "noseZ": ReplayBikeSaddle.noseZ,
            "length": ReplayBikeSaddle.length,
            "maxHalfWidth": ReplayBikeSaddle.maxHalfWidth,
        ], exactKeys: false)
        let stations = try array(saddle, "stations")
        XCTAssertEqual(stations.count, ReplayBikeSaddle.stations.count)
        for (index, expected) in ReplayBikeSaddle.stations.enumerated() {
            try assertDoubles(castDictionary(stations[index], "saddle.stations[\(index)]"), [
                "z": expected.z,
                "halfWidth": expected.halfWidth,
                "dropOuter": expected.dropOuter,
                "dropChannel": expected.dropChannel,
                "cutout": expected.cutout,
            ])
        }
    }

    private func assertSkierKinematics(
        _ actual: ReplaySkierKinematics,
        equals expected: [String: Any],
        sample: Int
    ) throws {
        let values: [(String, Double)] = [
            ("cycle", actual.cycle),
            ("armPress", actual.armPress),
            ("hipHinge", actual.hipHinge),
            ("kneeFlex", actual.kneeFlex),
            ("poleContact", actual.poleContact),
            ("poleSweep", actual.poleSweep),
            ("elbowLoad", actual.elbowLoad),
            ("armExtension", actual.armExtension),
            ("poleLift", actual.poleLift),
            ("poleFlight", actual.poleFlight),
            ("rebound", actual.rebound),
            ("surge", actual.surge),
        ]
        for (key, value) in values {
            XCTAssertEqual(value, try double(expected, key), accuracy: 1e-12, "sample \(sample) \(key)")
        }
    }

    private func strokePose(_ raw: [String: Any]) throws -> ReplayStrokePose {
        ReplayStrokePose(
            index: try int(raw, "index"),
            phase: try double(raw, "phase"),
            warpedPhase: try double(raw, "warpedPhase"),
            cycleFrac: try double(raw, "cycleFrac"),
            driveFrac: try double(raw, "driveFrac"),
            drive: try bool(raw, "drive"),
            driveProgress: try double(raw, "driveProgress"),
            recoveryProgress: try double(raw, "recoveryProgress"),
            strokeSeconds: try double(raw, "strokeSeconds"),
            strokeMeters: try double(raw, "strokeMeters"),
            rate: try double(raw, "rate"),
            watts: try int(raw, "watts"),
            intensity: try double(raw, "intensity"),
            amplitude: try double(raw, "amplitude"),
            fatigue: try double(raw, "fatigue")
        )
    }

    private func sampleArray(_ key: String) throws -> [Any] {
        try array(dictionary(try fixtureRoot(), "samples"), key)
    }

    private func fixtureRoot() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "replay-current-main-equipment",
            withExtension: "json"
        ))
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    private func assertDoubles(
        _ actual: [String: Any],
        _ expected: [String: Double],
        exactKeys: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        if exactKeys {
            XCTAssertEqual(Set(actual.keys), Set(expected.keys), file: file, line: line)
        } else {
            XCTAssertTrue(Set(expected.keys).isSubset(of: Set(actual.keys)), file: file, line: line)
        }
        for (key, value) in expected {
            XCTAssertEqual(try double(actual, key), value, accuracy: 1e-12, key, file: file, line: line)
        }
    }

    private func assertVector(
        _ actual: [String: Any],
        equals expected: SIMD3<Double>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        assertVector([
            try double(actual, "x"),
            try double(actual, "y"),
            try double(actual, "z"),
        ], equals: expected, file: file, line: line)
    }

    private func assertVector(
        _ raw: [Any],
        equals expected: SIMD3<Double>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try assertVector(raw.map { try number($0, "vector") }, equals: expected, file: file, line: line)
    }

    private func assertVector(
        _ actual: [Double],
        equals expected: SIMD3<Double>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, 3, file: file, line: line)
        guard actual.count == 3 else { return }
        XCTAssertEqual(actual[0], expected.x, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(actual[1], expected.y, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(actual[2], expected.z, accuracy: 1e-12, file: file, line: line)
    }

    private func dictionary(_ source: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(source[key] as? [String: Any], "Expected dictionary at \(key)")
    }

    private func array(_ source: [String: Any], _ key: String) throws -> [Any] {
        try XCTUnwrap(source[key] as? [Any], "Expected array at \(key)")
    }

    private func vector(_ source: [String: Any], _ key: String) throws -> [Double] {
        try array(source, key).map { try number($0, key) }
    }

    private func double(_ source: [String: Any], _ key: String) throws -> Double {
        try number(try XCTUnwrap(source[key], "Expected number at \(key)"), key)
    }

    private func int(_ source: [String: Any], _ key: String) throws -> Int {
        try XCTUnwrap(source[key] as? NSNumber, "Expected integer at \(key)").intValue
    }

    private func bool(_ source: [String: Any], _ key: String) throws -> Bool {
        try XCTUnwrap(source[key] as? Bool, "Expected boolean at \(key)")
    }

    private func number(_ raw: Any, _ path: String) throws -> Double {
        try XCTUnwrap(raw as? NSNumber, "Expected number at \(path)").doubleValue
    }

    private func castDictionary(_ raw: Any, _ path: String) throws -> [String: Any] {
        try XCTUnwrap(raw as? [String: Any], "Expected dictionary at \(path)")
    }

    private func castArray(_ raw: Any, _ path: String) throws -> [Any] {
        try XCTUnwrap(raw as? [Any], "Expected array at \(path)")
    }
}
