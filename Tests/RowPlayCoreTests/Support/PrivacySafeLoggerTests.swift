import XCTest
@testable import RowPlayCore

final class PrivacySafeLoggerTests: XCTestCase {
    // MARK: - redact() — hex tokens

    func testRedactsHexToken() {
        let input = "Token is abcdef1234567890abcdef1234567890 here"
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("abcdef1234567890abcdef1234567890"))
    }

    func testRedactsLongerHexToken() {
        let input = "abcdef1234567890abcdef1234567890abcdef"
        let result = redact(input)
        XCTAssertEqual(result, "[REDACTED]")
    }

    func testDoesNotRedactShortHex() {
        let input = "abc123"
        let result = redact(input)
        XCTAssertEqual(result, input, "Short hex strings should not be redacted")
    }

    // MARK: - redact() — Bearer headers

    func testRedactsBearerHeader() {
        let input = "Authorization: Bearer abcdef1234567890abcdef1234567890"
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("Bearer"))
    }

    func testRedactsBearerHeaderCaseInsensitive() {
        let input = "authorization: bearer mytokenvalue"
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
    }

    // MARK: - redact() — token JSON values

    func testRedactsTokenJsonValue() {
        let input = #"{"token": "super-secret-value-12345"}"#
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("super-secret-value-12345"))
        XCTAssertEqual(result, #"{"token": "[REDACTED]"}"#)
    }

    func testRedactsAccessTokenJsonValue() {
        let input = #"{"access_token": "super-secret-value-12345"}"#
        let result = redact(input)
        XCTAssertEqual(result, #"{"access_token": "[REDACTED]"}"#)
    }

    func testRedactsRefreshTokenJsonValue() {
        let input = #"{"refresh_token": "refresh-12345"}"#
        let result = redact(input)
        XCTAssertEqual(result, #"{"refresh_token": "[REDACTED]"}"#)
    }

    func testRedactsClientSecretJsonValue() {
        let input = #"{"client_secret": "secret-abc"}"#
        let result = redact(input)
        XCTAssertEqual(result, #"{"client_secret": "[REDACTED]"}"#)
    }

    func testRedactsIdTokenJsonValue() {
        let input = #"{"id_token": "eyJhbGciOiJSUzI1NiJ9"}"#
        let result = redact(input)
        XCTAssertEqual(result, #"{"id_token": "[REDACTED]"}"#)
    }

    func testRedactsPasswordJsonValue() {
        let input = #"{"password": "hunter2"}"#
        let result = redact(input)
        XCTAssertEqual(result, #"{"password": "[REDACTED]"}"#)
    }

    func testRedactsEscapedJsonSecretValue() {
        let input = #"{"password": "abc\"def", "safe": "visible"}"#
        let result = redact(input)
        XCTAssertEqual(result, #"{"password": "[REDACTED]", "safe": "visible"}"#)
        XCTAssertFalse(result.contains("abc"))
        XCTAssertFalse(result.contains("def"))
    }

    // MARK: - redact() — large JSON blobs

    func testRedactsLargeJsonBlob() {
        let payload = String(repeating: "x", count: 200)
        let input = "{\"\(payload)\": \"value\"}"
        let result = redact(input)
        XCTAssertEqual(result, "[REDACTED]")
    }

    func testRedactsLargeJsonArrayBlob() {
        let payload = (0..<20).map { #"{"id": \#($0), "name": "workout-\#($0)"}"# }.joined(separator: ",")
        let input = "[\(payload)]"
        XCTAssertGreaterThan(input.count, 100)
        let result = redact(input)
        XCTAssertEqual(result, "[REDACTED]")
    }

    func testDoesNotRedactSmallJson() {
        let input = #"{"key": "value"}"#
        let result = redact(input)
        XCTAssertEqual(result, input, "Small JSON objects should not be redacted")
    }

    // MARK: - redact() — Cookie headers

    func testRedactsCookieHeader() {
        let input = "Cookie: session_id=abcdef1234567890abcdef1234567890"
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("session_id=abcdef1234567890abcdef1234567890"))
    }

    func testRedactsSetCookieHeader() {
        let input = "Set-Cookie: auth_token=supersecretvalue123; Path=/"
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("supersecretvalue123"))
    }

    // MARK: - redact() — token= query/form credentials

    func testRedactsTokenQueryParameter() {
        let input = "https://api.example.com/callback?token=abcdef1234567890&state=xyz"
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("abcdef1234567890"))
    }

    func testRedactsAccessTokenQueryParameter() {
        let input = "access_token=supersecrettokenvalue12345"
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("supersecrettokenvalue12345"))
    }

    func testRedactsRefreshTokenQueryParameter() {
        let input = "refresh_token=refresh-abc12345"
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("refresh-abc12345"))
    }

    func testRedactsClientSecretQueryParameter() {
        let input = "client_secret=secret-value-xyz"
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("secret-value-xyz"))
    }

    func testRedactsIdTokenQueryParameter() {
        let input = "id_token=eyJhbGciOiJSUzI1NiJ9.payload"
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("eyJhbGciOiJSUzI1NiJ9.payload"))
    }

    func testRedactsPasswordQueryParameter() {
        let input = "password=hunter2"
        let result = redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("hunter2"))
    }

    // MARK: - redact() — idempotency

    func testRedactIsIdempotent() {
        let input = "Token: abcdef1234567890abcdef1234567890"
        let once = redact(input)
        let twice = redact(once)
        XCTAssertEqual(once, twice, "Redacting already-redacted text should be stable")
    }

    func testRedactAlreadyRedactedPlaceholder() {
        let result = redact("[REDACTED]")
        XCTAssertEqual(result, "[REDACTED]")
    }

    func testRedactsOversizeString() {
        let longString = String(repeating: "z", count: 16385)
        let result = redact(longString)
        let expected = String(repeating: "z", count: 16384) + " [TRUNCATED]"
        XCTAssertEqual(result, expected)
    }

    // MARK: - redact() — non-string values

    func testRedactsErrorDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Authorization: Bearer abcdef1234567890abcdef1234567890"
        ])
        let result = redact(error)
        XCTAssertTrue(result.contains("[REDACTED]"))
    }

    func testRedactsArbitraryValue() {
        let result = redact(42)
        XCTAssertEqual(result, "42")
    }

    // MARK: - redact() — clean strings pass through

    func testCleanStringPassesThrough() {
        let input = "Normal log message with no secrets"
        let result = redact(input)
        XCTAssertEqual(result, input)
    }

    // MARK: - redact() — multiple patterns in one string

    func testRedactsMultipleSensitiveValues() {
        let input = "Token abcdef1234567890abcdef1234567890 and Authorization: Bearer 1234567890abcdef1234567890abcdef"
        let result = redact(input)
        XCTAssertFalse(result.contains("abcdef1234567890abcdef1234567890"))
        XCTAssertFalse(result.contains("1234567890abcdef1234567890abcdef"))
        let redactedCount = result.components(separatedBy: "[REDACTED]").count - 1
        XCTAssertGreaterThanOrEqual(redactedCount, 2, "Should have at least 2 redacted markers")
    }

    // MARK: - PrivacySafeLogger (smoke test — no crash)

    func testLoggerMessageFormattingRedactsInterpolatedMessage() {
        let result = formatPrivacySafeLogMessage(
            "Sync failed: Authorization: Bearer abcdef1234567890abcdef1234567890",
            args: []
        )
        XCTAssertFalse(result.contains("abcdef1234567890abcdef1234567890"))
        XCTAssertTrue(result.contains("[REDACTED]"))
    }

    func testLoggerMessageFormattingRedactsArguments() {
        let result = formatPrivacySafeLogMessage(
            "Token value:",
            args: ["abcdef1234567890abcdef1234567890"]
        )
        XCTAssertFalse(result.contains("abcdef1234567890abcdef1234567890"))
        XCTAssertTrue(result.contains("[REDACTED]"))
    }

    func testLoggerCreationDoesNotCrash() {
        let logger = PrivacySafeLogger(category: "test")
        logger.error("test message")
        logger.warn("test warning")
    }

    func testLoggerRedactsArguments() {
        // PrivacySafeLogger outputs to os.Logger which we can't easily capture,
        // but we can verify it doesn't crash with sensitive arguments.
        let logger = PrivacySafeLogger(category: "test")
        logger.error("Token value:", "abcdef1234567890abcdef1234567890")
        logger.warn("Auth header:", "Authorization: Bearer abcdef1234567890abcdef1234567890")
    }
}
