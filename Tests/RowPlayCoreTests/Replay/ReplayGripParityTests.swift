import Foundation
import XCTest
@testable import RowPlayCore

final class ReplayGripParityTests: XCTestCase {
    func testCurrentMainGripGeometryAndClosureParityForEverySportAndHand() throws {
        let root = try fixtureRoot()
        XCTAssertEqual(root["schema"] as? String, "rowplay.replay.current-main.grip-parity.v1")
        XCTAssertEqual(
            root["sourceCommit"] as? String,
            "4d96480e7c6fb382f800555bd3aa463d9fe5b1a6"
        )
        XCTAssertEqual(try number(root["sampleCount"]), 6)

        let channel = try dictionary(root["channel"])
        assertVector(
            ReplayGripGeometry.handCurlAxisRight,
            equals: try vector(channel["handCurlAxis"])
        )
        assertVector(
            ReplayGripGeometry.handFistCentre,
            equals: try vector(channel["handFistCentre"])
        )
        XCTAssertEqual(
            ReplayGripGeometry.handFistRadius,
            try number(channel["handFistRadius"]),
            accuracy: 1e-12
        )
        XCTAssertEqual(
            ReplayGripGeometry.handFistReferenceGripRadius,
            try number(channel["handFistReferenceGripRadius"]),
            accuracy: 1e-12
        )
        XCTAssertEqual(
            ReplayHandClosure.defaultDigitFlesh,
            try number(channel["defaultDigitFlesh"]),
            accuracy: 1e-12
        )

        let hands = try dictionary(root["hands"])
        let closures = try dictionary(root["closures"])
        let helperFixtures = try array(root["helpers"])
        var localTransforms: [String: (translation: SIMD3<Double>, rotation: ReplayQuaternion)] = [:]
        var parentNames: [String: String] = [:]
        for rawHelper in helperFixtures {
            let helper = try dictionary(rawHelper)
            let name = try string(helper["name"])
            localTransforms[name] = (
                try vector(helper["translation"]),
                try quaternion(helper["rotationQuaternion"])
            )
            parentNames[name] = try string(helper["parent"])
        }
        var consumedHelpers: Set<String> = []
        for side in ReplayHandSide.allCases {
            let sideKey = side == .left ? "left" : "right"
            let hand = try dictionary(hands[sideKey])
            let expectedChains = try makeChains(from: hand)
            let chains = ReplayHandDigitChain.collect(
                side: side,
                handBoneName: try string(hand["handBone"]),
                restLocalTransform: { localTransforms[$0] },
                parentName: { parentNames[$0] }
            )
            try assertChains(chains, equalTo: expectedChains, context: sideKey)
            XCTAssertEqual(chains.count, ReplayHandDigit.allCases.count)
            for chain in chains {
                consumedHelpers.formUnion(chain.joints.map(\.helper))
                if let cupNode = chain.cupNode {
                    consumedHelpers.insert(cupNode.helper)
                }
            }

            let perSide = try dictionary(try dictionary(channel["perSide"])[sideKey])
            assertVector(
                ReplayGripGeometry.handCurlAxis(side: side),
                equals: try vector(perSide["curlAxis"])
            )
            assertVector(
                ReplayGripGeometry.handCurlAxisThumbward(side: side),
                equals: try vector(perSide["curlAxisThumbward"])
            )
            assertVector(
                ReplayGripGeometry.handLongAxis(side: side),
                equals: try vector(perSide["longAxis"])
            )
            assertVector(
                ReplayGripGeometry.handPalmNormalOut(side: side),
                equals: try vector(perSide["palmNormalOut"])
            )

            for sportName in ["rower", "skierg", "bike"] {
                let closureFixture = try dictionary(closures[sportName])
                let options = closureOptions(for: sportName, side: side)
                try assertOptions(options, equalTo: try dictionary(closureFixture["options"]))
                let actual = try XCTUnwrap(
                    ReplayHandClosure.solve(chains: chains, options: options)
                )
                try assertClosure(
                    actual,
                    equalTo: try dictionary(closureFixture[sideKey]),
                    context: "\(sportName) \(sideKey)"
                )
            }
        }

        let helpers = try helperFixtures.map {
            try string(try dictionary($0)["name"])
        }
        XCTAssertEqual(consumedHelpers, Set(helpers))
    }

    func testClosureRejectsNonThreeJointChainsWithoutTrapping() {
        let joint = ReplayHandDigitJoint(
            helper: "joint",
            position: SIMD3(0, 0, 0),
            quaternion: .identity
        )
        let malformed = ReplayHandDigitChain(
            digit: .index,
            joints: [joint, joint, joint, joint],
            tipLength: 0.01,
            cupNode: nil
        )
        let closure = ReplayHandClosure.solve(
            chains: [malformed],
            options: ReplayRowGripContract.gripClosureOptions(side: .left)
        )
        XCTAssertNil(closure)
        let tooShort = ReplayHandDigitChain(
            digit: .index,
            joints: [joint, joint],
            tipLength: 0.01,
            cupNode: nil
        )
        XCTAssertNil(ReplayHandClosure.solve(
            chains: [tooShort],
            options: ReplayRowGripContract.gripClosureOptions(side: .left)
        ))
        XCTAssertNil(ReplayHandClosure.solve(
            chains: [],
            options: ReplayRowGripContract.gripClosureOptions(side: .left)
        ))
    }

    private func assertChains(
        _ actual: [ReplayHandDigitChain],
        equalTo expected: [ReplayHandDigitChain],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(actual.count, expected.count, context, file: file, line: line)
        for (actualChain, expectedChain) in zip(actual, expected) {
            XCTAssertEqual(actualChain.digit, expectedChain.digit, context, file: file, line: line)
            XCTAssertEqual(actualChain.tipLength, expectedChain.tipLength, accuracy: 1e-9, context, file: file, line: line)
            XCTAssertEqual(actualChain.joints.count, expectedChain.joints.count, context, file: file, line: line)
            for (actualJoint, expectedJoint) in zip(actualChain.joints, expectedChain.joints) {
                assertJoint(actualJoint, equals: expectedJoint, context: context, file: file, line: line)
            }
            if let expectedCup = expectedChain.cupNode {
                assertJoint(
                    try XCTUnwrap(actualChain.cupNode),
                    equals: expectedCup,
                    context: context,
                    file: file,
                    line: line
                )
            } else {
                XCTAssertNil(actualChain.cupNode, context, file: file, line: line)
            }
        }
    }

    private func assertJoint(
        _ actual: ReplayHandDigitJoint,
        equals expected: ReplayHandDigitJoint,
        context: String,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.helper, expected.helper, context, file: file, line: line)
        assertVector(actual.position, equals: expected.position, accuracy: 1e-9, context: context, file: file, line: line)
        XCTAssertEqual(actual.quaternion.x, expected.quaternion.x, accuracy: 1e-9, context, file: file, line: line)
        XCTAssertEqual(actual.quaternion.y, expected.quaternion.y, accuracy: 1e-9, context, file: file, line: line)
        XCTAssertEqual(actual.quaternion.z, expected.quaternion.z, accuracy: 1e-9, context, file: file, line: line)
        XCTAssertEqual(actual.quaternion.w, expected.quaternion.w, accuracy: 1e-9, context, file: file, line: line)
    }

    private func closureOptions(
        for sport: String,
        side: ReplayHandSide
    ) -> ReplayHandGripClosureOptions {
        switch sport {
        case "rower": ReplayRowGripContract.gripClosureOptions(side: side)
        case "skierg": ReplaySkiGripContract.gripClosureOptions(side: side)
        default: ReplayBikeGripContract.gripClosureOptions(side: side)
        }
    }

    private func assertOptions(
        _ actual: ReplayHandGripClosureOptions,
        equalTo expected: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(actual.surface.radius, try number(expected["radius"]), accuracy: 1e-12, file: file, line: line)
        if let expectedEnd = optionalNumber(expected["thumbEndAxial"]) {
            XCTAssertEqual(
                try XCTUnwrap(actual.surface.thumbEndAxial),
                expectedEnd,
                accuracy: 1e-12,
                file: file,
                line: line
            )
        } else {
            XCTAssertNil(actual.surface.thumbEndAxial, file: file, line: line)
        }
        XCTAssertEqual(actual.thumbOppose, try number(expected["thumbOppose"]), accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(actual.wrapFingerStages, try bool(expected["wrapFingerStages"]), file: file, line: line)
    }

    private func assertClosure(
        _ actual: ReplayHandGripClosure,
        equalTo expected: [String: Any],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let expectedPoses = try array(expected["poses"])
        XCTAssertEqual(actual.poses.count, expectedPoses.count, context, file: file, line: line)
        for (actualPose, rawExpected) in zip(actual.poses, expectedPoses) {
            let expectedPose = try dictionary(rawExpected)
            XCTAssertEqual(actualPose.helper, try string(expectedPose["helper"]), context, file: file, line: line)
            XCTAssertEqual(actualPose.flex, try number(expectedPose["flex"]), accuracy: 1e-8, context, file: file, line: line)
            XCTAssertEqual(actualPose.oppose, try number(expectedPose["oppose"]), accuracy: 1e-8, context, file: file, line: line)
        }

        let expectedContacts = try array(expected["contacts"])
        XCTAssertEqual(actual.contacts.count, expectedContacts.count, context, file: file, line: line)
        for (actualContact, rawExpected) in zip(actual.contacts, expectedContacts) {
            let expectedContact = try dictionary(rawExpected)
            XCTAssertEqual(actualContact.digit.rawValue, try string(expectedContact["digit"]), context, file: file, line: line)
            XCTAssertEqual(
                actualContact.surfaceDistance,
                try number(expectedContact["surfaceDistance"]),
                accuracy: 1e-8,
                context,
                file: file,
                line: line
            )
            if let expectedSegment = optionalNumber(expectedContact["segmentSurfaceDistance"]) {
                XCTAssertEqual(
                    try XCTUnwrap(actualContact.segmentSurfaceDistance),
                    expectedSegment,
                    accuracy: 1e-8,
                    context,
                    file: file,
                    line: line
                )
            } else {
                XCTAssertNil(actualContact.segmentSurfaceDistance, context, file: file, line: line)
            }
            XCTAssertEqual(actualContact.contact, try bool(expectedContact["contact"]), context, file: file, line: line)
            assertVector(
                actualContact.tip,
                equals: try vector(expectedContact["tip"]),
                accuracy: 1e-8,
                context: context,
                file: file,
                line: line
            )
        }
    }

    private func makeChains(from hand: [String: Any]) throws -> [ReplayHandDigitChain] {
        try array(hand["chains"]).map { rawChain in
            let chain = try dictionary(rawChain)
            let cupNode = try optionalJoint(chain["cupNode"])
            return ReplayHandDigitChain(
                digit: try XCTUnwrap(ReplayHandDigit(rawValue: try string(chain["digit"]))),
                joints: try array(chain["joints"]).map { try joint($0) },
                tipLength: try number(chain["tipLength"]),
                cupNode: cupNode
            )
        }
    }

    private func optionalJoint(_ value: Any?) throws -> ReplayHandDigitJoint? {
        if value == nil || value is NSNull { return nil }
        return try joint(value)
    }

    private func joint(_ value: Any?) throws -> ReplayHandDigitJoint {
        let source = try dictionary(value)
        return ReplayHandDigitJoint(
            helper: try string(source["helper"]),
            position: try vector(source["position"]),
            quaternion: try quaternion(source["quaternion"])
        )
    }

    private func quaternion(_ value: Any?) throws -> ReplayQuaternion {
        let values = try array(value).map { try number($0) }
        guard values.count == 4 else { throw FixtureError.invalidShape }
        return ReplayQuaternion(x: values[0], y: values[1], z: values[2], w: values[3])
    }

    private func vector(_ value: Any?) throws -> SIMD3<Double> {
        if let source = value as? [String: Any] {
            return SIMD3(
                try number(source["x"]),
                try number(source["y"]),
                try number(source["z"])
            )
        }
        let values = try array(value).map { try number($0) }
        guard values.count == 3 else { throw FixtureError.invalidShape }
        return SIMD3(values[0], values[1], values[2])
    }

    private func assertVector(
        _ actual: SIMD3<Double>,
        equals expected: SIMD3<Double>,
        accuracy: Double = 1e-12,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, context, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, context, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: accuracy, context, file: file, line: line)
    }

    private func fixtureRoot() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "replay-current-main-grips",
            withExtension: "json"
        ))
        return try dictionary(try JSONSerialization.jsonObject(with: Data(contentsOf: url)))
    }

    private func dictionary(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw FixtureError.invalidShape }
        return value
    }

    private func array(_ value: Any?) throws -> [Any] {
        guard let value = value as? [Any] else { throw FixtureError.invalidShape }
        return value
    }

    private func string(_ value: Any?) throws -> String {
        guard let value = value as? String else { throw FixtureError.invalidShape }
        return value
    }

    private func bool(_ value: Any?) throws -> Bool {
        guard let value = value as? Bool else { throw FixtureError.invalidShape }
        return value
    }

    private func number(_ value: Any?) throws -> Double {
        guard let value = value as? NSNumber else { throw FixtureError.invalidShape }
        return value.doubleValue
    }

    private func optionalNumber(_ value: Any?) -> Double? {
        guard !(value is NSNull) else { return nil }
        return (value as? NSNumber)?.doubleValue
    }

    private enum FixtureError: Error {
        case invalidShape
    }
}
