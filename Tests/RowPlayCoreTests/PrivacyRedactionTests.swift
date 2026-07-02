import XCTest
@testable import RowPlayCore

final class PrivacyRedactionTests: XCTestCase {
    func testEveryoneIsShareable() {
        XCTAssertTrue(PrivacyRedaction.isPubliclyShareable(privacy: "everyone"))
    }

    func testEveryoneIsCaseInsensitive() {
        XCTAssertTrue(PrivacyRedaction.isPubliclyShareable(privacy: "Everyone"))
        XCTAssertTrue(PrivacyRedaction.isPubliclyShareable(privacy: "EVERYONE"))
    }

    func testEveryoneTrimsWhitespace() {
        XCTAssertTrue(PrivacyRedaction.isPubliclyShareable(privacy: "  everyone  "))
    }

    func testPrivateIsNotShareable() {
        XCTAssertFalse(PrivacyRedaction.isPubliclyShareable(privacy: "private"))
    }

    func testLoggedInIsNotShareable() {
        XCTAssertFalse(PrivacyRedaction.isPubliclyShareable(privacy: "logged_in"))
    }

    func testPartnersIsNotShareable() {
        XCTAssertFalse(PrivacyRedaction.isPubliclyShareable(privacy: "partners"))
    }

    func testNilIsNotShareable() {
        XCTAssertFalse(PrivacyRedaction.isPubliclyShareable(privacy: nil))
    }

    func testGarbageIsNotShareable() {
        XCTAssertFalse(PrivacyRedaction.isPubliclyShareable(privacy: "some_random_value"))
    }

    func testEmptyStringIsNotShareable() {
        XCTAssertFalse(PrivacyRedaction.isPubliclyShareable(privacy: ""))
    }
}
