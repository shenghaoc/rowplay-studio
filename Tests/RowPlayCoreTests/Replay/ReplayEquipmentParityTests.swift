import Foundation
import XCTest
@testable import RowPlayCore

final class ReplayEquipmentParityTests: XCTestCase {
    func testPinnedEquipmentDimensionsMatchPortableContracts() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "replay-current-main-equipment",
            withExtension: "json"
        ))
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        XCTAssertEqual(root["schema"] as? String, "rowplay.replay.current-main.equipment-parity.v1")
        XCTAssertEqual(
            root["sourceCommit"] as? String,
            "4d96480e7c6fb382f800555bd3aa463d9fe5b1a6"
        )

        let row = try XCTUnwrap(root["row"] as? [String: Any])
        let rowGrip = try XCTUnwrap(row["scullGrip"] as? [String: NSNumber])
        XCTAssertEqual(rowGrip["radius"]?.doubleValue, ReplayRowGripContract.scullGrip.radius)
        XCTAssertEqual(rowGrip["length"]?.doubleValue, ReplayRowGripContract.scullGrip.length)
        XCTAssertEqual(
            rowGrip["anchorFromEnd"]?.doubleValue,
            ReplayRowGripContract.scullGrip.anchorFromEnd
        )

        let ski = try XCTUnwrap(root["ski"] as? [String: Any])
        XCTAssertEqual(
            (ski["poleGripRadius"] as? NSNumber)?.doubleValue,
            ReplaySkiGripContract.poleGripRadius
        )

        let bike = try XCTUnwrap(root["bike"] as? [String: Any])
        let rig = try XCTUnwrap(bike["rig"] as? [String: Any])
        XCTAssertEqual(
            (rig["wheelRadius"] as? NSNumber)?.doubleValue,
            ReplayBikeGripContract.wheelRadius
        )
        XCTAssertEqual(
            (rig["saddlePadHalfHeight"] as? NSNumber)?.doubleValue,
            ReplayBikeGripContract.saddlePadHalfHeight
        )
    }
}
