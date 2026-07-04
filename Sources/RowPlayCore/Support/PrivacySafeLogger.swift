import Foundation
import os

/// Redaction marker substituted for sensitive content.
public let redactedPlaceholder = "[REDACTED]"

/// Regex-based patterns that match personally sensitive data.
///
/// Applied sequentially before logging. Mirrors the web app's `logger.ts`
/// patterns adapted for Swift's regex engine.
private let sensitivePatterns: [NSRegularExpression] = {
    let patternStrings: [String] = [
        // Concept2 API token: 32+ character hex string
        #"\b[a-f0-9]{32,}\b"#,
        // Authorization: Bearer ... header
        #"Authorization:\s*Bearer\s+\S+"#,
        // Cookie headers
        #"(Cookie|Set-Cookie):\s*[^\n]+"#,
        // Generic token values in JSON: "token": "..." — captures the value portion
        #""token"\s*:\s*"[^"]+""#,
        // Query/form credential keys: token=..., access_token=...
        #"\b(token|access_token)\s*=\s*[^\s&]+"#,
        // Full workout payloads (JSON object > 100 chars, non-greedy nested)
        #"\{(?:[^{}]|\{[^{}]*\}){100,}\}"#,
    ]
    return patternStrings.compactMap { pattern in
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}()

/// Redact sensitive content from a string.
///
/// Applies all known sensitive patterns, replacing matches with `[REDACTED]`.
/// Idempotent — safe to call on already-redacted strings.
///
/// - Parameter value: The value to redact. Non-string values are converted via `String(describing:)`.
/// - Returns: The redacted string.
public func redact(_ value: Any) -> String {
    let input: String
    if let string = value as? String {
        input = string
    } else if let error = value as? Error {
        input = error.localizedDescription
    } else {
        input = String(describing: value)
    }

    var result = input
    for pattern in sensitivePatterns {
        let range = NSRange(result.startIndex..., in: result)
        result = pattern.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: redactedPlaceholder
        )
    }
    return result
}

func formatPrivacySafeLogMessage(_ message: String, args: [Any]) -> String {
    let redactedMessage = redact(message)
    let redactedArgs = args.map { redact($0) }
    if redactedArgs.isEmpty {
        return redactedMessage
    }
    return ([redactedMessage] + redactedArgs).joined(separator: " ")
}

/// Privacy-safe logger wrapping `os.Logger`.
///
/// Redacts the main message and all arguments before emitting to the system log.
///
/// Mirrors the web app's `createLogger(console)` pattern.
public struct PrivacySafeLogger {
    private let logger: os.Logger

    /// Create a logger for the specified subsystem and category.
    ///
    /// - Parameters:
    ///   - subsystem: The app's bundle identifier or subsystem string.
    ///   - category: The log category (e.g., "sync", "token", "cache").
    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.rowplay-studio", category: String) {
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }

    /// Log an error message with redacted arguments.
    public func error(_ message: String, _ args: Any...) {
        logger.error("\(formatPrivacySafeLogMessage(message, args: args), privacy: .public)")
    }

    /// Log a warning message with redacted arguments.
    public func warn(_ message: String, _ args: Any...) {
        logger.warning("\(formatPrivacySafeLogMessage(message, args: args), privacy: .public)")
    }
}
