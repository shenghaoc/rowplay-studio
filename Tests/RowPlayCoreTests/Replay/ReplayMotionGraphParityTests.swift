import Foundation
import XCTest
@testable import RowPlayCore

/// Full-channel parity against a corpus exported by
/// `script/export_rowplay_motion_parity.mjs` from merged RowPlay V4.
final class ReplayMotionGraphParityTests: XCTestCase {
    func testCurrentMainMotionGraphParityAcross129PhasesPerSport() throws {
        let root = try fixtureRoot()
        XCTAssertEqual(root["schema"] as? String, "rowplay.replay.current-main.motion-parity.v1")
        XCTAssertEqual(
            root["sourceCommit"] as? String,
            "4d96480e7c6fb382f800555bd3aa463d9fe5b1a6"
        )
        XCTAssertEqual((root["sampleCountPerSport"] as? NSNumber)?.intValue, 129)
        let samples = try XCTUnwrap(root["samples"] as? [[String: Any]])
        let channelsBySport = try XCTUnwrap(root["channelsBySport"] as? [String: [String]])
        XCTAssertEqual(samples.count, 387)

        var counts: [String: Int] = [:]
        for sample in samples {
            let sportRaw = try XCTUnwrap(sample["sport"] as? String)
            counts[sportRaw, default: 0] += 1
            let sport = try XCTUnwrap(Sport(rawValue: sportRaw))
            let phaseIndex = (sample["phaseIndex"] as? NSNumber)?.intValue ?? -1
            let pose = try makePose(from: try XCTUnwrap(sample["pose"] as? [String: Any]))
            let channels = try XCTUnwrap(channelsBySport[sportRaw])
            let expected = try XCTUnwrap(sample["values"] as? [NSNumber]).map(\.doubleValue)
            let actual = flatten(ReplayMotionGraph.sample(sport: sport, pose: pose))
            XCTAssertEqual(
                Set(actual.keys), Set(channels),
                "public channel shape drifted for \(sportRaw) phase \(phaseIndex)"
            )
            XCTAssertEqual(expected.count, channels.count)
            for (index, key) in channels.enumerated() {
                let actualValue = try XCTUnwrap(actual[key])
                XCTAssertEqual(
                    actualValue,
                    expected[index],
                    accuracy: 1e-10,
                    "\(sportRaw) \(key), phase \(phaseIndex)"
                )
            }
        }
        XCTAssertEqual(counts["rower"], 129)
        XCTAssertEqual(counts["skierg"], 129)
        XCTAssertEqual(counts["bike"], 129)
    }

    private func fixtureRoot() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "replay-current-main-motion",
            withExtension: "json"
        ))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func makePose(from source: [String: Any]) throws -> ReplayStrokePose {
        func double(_ name: String) throws -> Double {
            try XCTUnwrap((source[name] as? NSNumber)?.doubleValue, "Missing \(name)")
        }
        func integer(_ name: String) throws -> Int {
            try XCTUnwrap((source[name] as? NSNumber)?.intValue, "Missing \(name)")
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

    private func flatten(_ graph: ReplayMotionGraph) -> [String: Double] {
        var output: [String: Double] = [:]
        switch graph {
        case .rower(let graph):
            append(graph.timing, at: "timing", into: &output)
            append(graph.body.seatTravel, at: "body.seatTravel", into: &output)
            append(graph.body.pelvisTravel, at: "body.pelvisTravel", into: &output)
            append(graph.body.legExtension, at: "body.legExtension", into: &output)
            append(graph.body.torsoSwing, at: "body.torsoSwing", into: &output)
            append(graph.body.spineHinge, at: "body.spineHinge", into: &output)
            append(graph.body.torsoReach, at: "body.torsoReach", into: &output)
            append(graph.body.armDraw, at: "body.armDraw", into: &output)
            append(graph.body.shoulderSet, at: "body.shoulderSet", into: &output)
            append(graph.body.handleTravel, at: "body.handleTravel", into: &output)
            append(graph.body.headBob, at: "body.headBob", into: &output)
            append(graph.contacts.footPressure, at: "contacts.footPressure", into: &output)
            append(graph.contacts.handleGrip, at: "contacts.handleGrip", into: &output)
            append(graph.contacts.bladeWater, at: "contacts.bladeWater", into: &output)
            append(graph.contacts.bladeFeather, at: "contacts.bladeFeather", into: &output)
            append(graph.contacts.oarlockLoad, at: "contacts.oarlockLoad", into: &output)
            append(graph.accents.surge, at: "accents.surge", into: &output)
            append(graph.accents.vertical, at: "accents.vertical", into: &output)
        case .skierg(let graph):
            append(graph.timing, at: "timing", into: &output)
            append(graph.body.armPress, at: "body.armPress", into: &output)
            append(graph.body.shoulderDrop, at: "body.shoulderDrop", into: &output)
            append(graph.body.hipHinge, at: "body.hipHinge", into: &output)
            append(graph.body.pelvisHinge, at: "body.pelvisHinge", into: &output)
            append(graph.body.kneeFlex, at: "body.kneeFlex", into: &output)
            append(graph.body.poleSweep, at: "body.poleSweep", into: &output)
            append(graph.body.elbowLoad, at: "body.elbowLoad", into: &output)
            append(graph.body.armExtension, at: "body.armExtension", into: &output)
            append(graph.body.poleLift, at: "body.poleLift", into: &output)
            append(graph.body.poleFlight, at: "body.poleFlight", into: &output)
            append(graph.body.reach, at: "body.reach", into: &output)
            append(graph.body.torsoCompression, at: "body.torsoCompression", into: &output)
            append(graph.body.spineHinge, at: "body.spineHinge", into: &output)
            append(graph.body.headRise, at: "body.headRise", into: &output)
            append(graph.contacts.poleGrip, at: "contacts.poleGrip", into: &output)
            append(graph.contacts.polePlant, at: "contacts.polePlant", into: &output)
            append(graph.contacts.poleLoad, at: "contacts.poleLoad", into: &output)
            append(graph.contacts.footPressure, at: "contacts.footPressure", into: &output)
            append(graph.accents.surge, at: "accents.surge", into: &output)
            append(graph.accents.rebound, at: "accents.rebound", into: &output)
        case .bike(let graph):
            append(graph.timing, at: "timing", into: &output)
            append(graph.crank, at: "crank", into: &output)
            append(graph.body.torsoSway, at: "body.torsoSway", into: &output)
            append(graph.body.hipRock, at: "body.hipRock", into: &output)
            append(graph.body.pelvisRock, at: "body.pelvisRock", into: &output)
            append(graph.body.spineLean, at: "body.spineLean", into: &output)
            append(graph.body.shoulderCounterRotation, at: "body.shoulderCounterRotation", into: &output)
            append(graph.body.headStabilization, at: "body.headStabilization", into: &output)
            append(graph.leftPedal, at: "leftPedal", into: &output)
            append(graph.rightPedal, at: "rightPedal", into: &output)
            append(graph.contacts.handlebarGrip, at: "contacts.handlebarGrip", into: &output)
            append(graph.contacts.saddleContact, at: "contacts.saddleContact", into: &output)
        }
        return output
    }

    private func append(_ timing: ReplayMotionTiming, at path: String, into output: inout [String: Double]) {
        output["\(path).cycleIndex"] = Double(timing.cycleIndex)
        output["\(path).cycle"] = timing.cycle
        output["\(path).phase"] = timing.phase
        output["\(path).secondsPerCycle"] = timing.secondsPerCycle
        output["\(path).phaseVelocity"] = timing.phaseVelocity
        output["\(path).phaseAcceleration"] = timing.phaseAcceleration
        output["\(path).driveFraction"] = timing.driveFraction
        output["\(path).driveProgress"] = timing.driveProgress
        output["\(path).recoveryProgress"] = timing.recoveryProgress
    }

    private func append(_ channel: ReplayMotionChannel, at path: String, into output: inout [String: Double]) {
        output["\(path).value"] = channel.value
        output["\(path).velocity"] = channel.velocity
        output["\(path).acceleration"] = channel.acceleration
    }

    private func append(_ circular: ReplayCircularMotion, at path: String, into output: inout [String: Double]) {
        output["\(path).angle"] = circular.angle
        output["\(path).sin"] = circular.sin
        output["\(path).cos"] = circular.cos
        output["\(path).angularVelocity"] = circular.angularVelocity
        output["\(path).angularAcceleration"] = circular.angularAcceleration
    }

    private func append(_ pedal: ReplayPedalMotion, at path: String, into output: inout [String: Double]) {
        append(pedal.rotation, at: "\(path).rotation", into: &output)
        append(pedal.legExtension, at: "\(path).legExtension", into: &output)
        append(pedal.kneeLift, at: "\(path).kneeLift", into: &output)
        append(pedal.ankleFlex, at: "\(path).ankleFlex", into: &output)
        append(pedal.drive, at: "\(path).drive", into: &output)
        append(pedal.pedalLock, at: "\(path).pedalLock", into: &output)
    }
}
