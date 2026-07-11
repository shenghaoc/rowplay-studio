import Foundation
#if canImport(os)
import os
#endif

/// Redaction marker substituted for sensitive content.
public let redactedPlaceholder = "[REDACTED]"

private struct RedactionRule {
    let regex: NSRegularExpression
    let replacement: String
}

/// Regex-based patterns that match personally sensitive data.
///
/// Applied sequentially before logging. Mirrors the web app's `logger.ts`
/// patterns adapted for Swift's regex engine.
private let sensitivePatterns: [RedactionRule] = {
    let patternSpecs: [(pattern: String, replacement: String)] = [
        // Concept2 API token: 32+ character hex string
        (#"\b[a-f0-9]{32,}\b"#, redactedPlaceholder),
        // Authorization: Bearer ... header
        (#"Authorization:\s*Bearer\s+\S+"#, redactedPlaceholder),
        // Cookie headers
        (#"(Cookie|Set-Cookie):\s*[^\n]+"#, "$1: \(redactedPlaceholder)"),
        // Generic token values in JSON: preserve the key and replace only the value.
        (#"("(?:token|access_token|refresh_token|id_token|client_secret|password)"\s*:\s*")(?:\\.|[^"\\])*(")"#, "$1\(redactedPlaceholder)$2"),
        // Query/form credential keys: token=..., access_token=...
        (#"\b(token|access_token|refresh_token|id_token|client_secret|password)\s*=\s*[^\s&]+"#, "$1=\(redactedPlaceholder)"),
        // Full workout payloads (JSON object or array > 100 chars, shallow nested)
        (#"\{(?:[^{}]|\{[^{}]*\}){100,}\}"#, redactedPlaceholder),
        (#"\[(?:[^\[\]]|\[[^\[\]]*\]){100,}\]"#, redactedPlaceholder),
    ]
    return patternSpecs.compactMap { spec in
        guard let regex = try? NSRegularExpression(pattern: spec.pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return RedactionRule(regex: regex, replacement: spec.replacement)
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
        input = String(describing: error)
    } else {
        input = String(describing: value)
    }

    var result = input
    for rule in sensitivePatterns {
        let range = NSRange(result.startIndex..., in: result)
        result = rule.regex.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: rule.replacement
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
public struct PrivacySafeLogger: Sendable {
    private let subsystem: String
    private let category: String

    /// Create a logger for the specified subsystem and category.
    ///
    /// - Parameters:
    ///   - subsystem: The app's bundle identifier or subsystem string.
    ///   - category: The log category (e.g., "sync", "token", "cache").
    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.rowplay-studio", category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    /// Log an error message with redacted arguments.
    public func error(_ message: String, _ args: Any...) {
        let formatted = formatPrivacySafeLogMessage(message, args: args)
        #if canImport(os)
        let logger = os.Logger(subsystem: subsystem, category: category)
        logger.error("\(formatted, privacy: .public)")
        #else
        print("[ERROR] [\(category)] \(formatted)")
        #endif
    }

    /// Log a warning message with redacted arguments.
    public func warn(_ message: String, _ args: Any...) {
        let formatted = formatPrivacySafeLogMessage(message, args: args)
        #if canImport(os)
        let logger = os.Logger(subsystem: subsystem, category: category)
        logger.warning("\(formatted, privacy: .public)")
        #else
        print("[WARN] [\(category)] \(formatted)")
        #endif
    }
}
