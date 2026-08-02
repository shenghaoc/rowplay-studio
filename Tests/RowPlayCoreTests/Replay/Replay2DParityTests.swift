import Foundation
import XCTest
@testable import RowPlayCore

/// Verifies the portable kinematics consumed by the native Canvas renderers
/// against the pinned RowPlay renderer export at 64 phases for every sport.
final class Replay2DParityTests: XCTestCase {
    func testCurrentMain2DKinematicsAcrossAllSports() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "replay-current-main-2d",
            withExtension: "json"
        ))
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        XCTAssertEqual(root["schema"] as? String, "rowplay.replay.current-main.kinematics-parity.v1")
        XCTAssertEqual(
            root["sourceCommit"] as? String,
            "4d96480e7c6fb382f800555bd3aa463d9fe5b1a6"
        )
        XCTAssertEqual((root["sampleCountPerSport"] as? NSNumber)?.intValue, 64)

        let samples = try XCTUnwrap(root["samples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 192)
        var counts: [String: Int] = [:]
        for sample in samples {
            let sportRaw = try XCTUnwrap(sample["sport"] as? String)
            let sport = try XCTUnwrap(Sport(rawValue: sportRaw))
            let phaseIndex = try XCTUnwrap((sample["phaseIndex"] as? NSNumber)?.intValue)
            let pose = try makePose(from: try XCTUnwrap(sample["pose"] as? [String: Any]))
            let expected = try XCTUnwrap(sample["kinematics"] as? [String: NSNumber])
            let actual = flatten(sport: sport, pose: pose)
            XCTAssertEqual(Set(actual.keys), Set(expected.keys), "\(sportRaw) phase \(phaseIndex)")
            for (key, number) in expected {
                XCTAssertEqual(
                    try XCTUnwrap(actual[key]),
                    number.doubleValue,
                    accuracy: 1e-10,
                    "\(sportRaw) \(key), phase \(phaseIndex)"
                )
            }
            counts[sportRaw, default: 0] += 1
        }
        XCTAssertEqual(counts, ["rower": 64, "skierg": 64, "bike": 64])
    }

    private func makePose(from source: [String: Any]) throws -> ReplayStrokePose {
        func double(_ key: String) throws -> Double {
            try XCTUnwrap((source[key] as? NSNumber)?.doubleValue, "Missing \(key)")
        }
        func integer(_ key: String) throws -> Int {
            try XCTUnwrap((source[key] as? NSNumber)?.intValue, "Missing \(key)")
        }
        return ReplayStrokePose(
            index: try integer("index"),
            phase: try double("phase"),
            warpedPhase: try double("warpedPhase"),
            cycleFrac: try double("cycleFrac"),
            driveFrac: try double("driveFrac"),
            drive: try XCTUnwrap(source["drive"] as? Bool),
            driveProgress: try double("driveProgress"),
            recoveryProgress: try double("recoveryProgress"),
            strokeSeconds: try double("strokeSeconds"),
            strokeMeters: try double("strokeMeters"),
            rate: try double("rate"),
            watts: try integer("watts"),
            intensity: try double("intensity"),
            amplitude: try double("amplitude"),
            fatigue: try double("fatigue")
        )
    }

    private func flatten(sport: Sport, pose: ReplayStrokePose) -> [String: Double] {
        switch sport {
        case .rower:
            let value = ReplaySportKinematics.solveRower(pose)
            return [
                "legExtension": value.legExtension,
                "bodySwing": value.bodySwing,
                "armDraw": value.armDraw,
                "bladeDepth": value.bladeDepth,
                "bladeFeather": value.bladeFeather,
                "surge": value.surge,
                "vertical": value.vertical,
            ]
        case .skierg:
            let value = ReplaySportKinematics.solveSkier(pose)
            return [
                "cycle": value.cycle,
                "armPress": value.armPress,
                "hipHinge": value.hipHinge,
                "kneeFlex": value.kneeFlex,
                "poleContact": value.poleContact,
                "poleSweep": value.poleSweep,
                "elbowLoad": value.elbowLoad,
                "armExtension": value.armExtension,
                "poleLift": value.poleLift,
                "poleFlight": value.poleFlight,
                "rebound": value.rebound,
                "surge": value.surge,
            ]
        case .bike:
            let value = ReplaySportKinematics.solveBike(pose)
            return [
                "crankAngle": value.crankAngle,
                "torsoSway": value.torsoSway,
                "hipRock": value.hipRock,
                "anklePitchLeft": value.anklePitchLeft,
                "anklePitchRight": value.anklePitchRight,
            ]
        }
    }
}
