import Foundation

/// Parse and format user-entered `/500m` pace strings.
///
/// Ported from the web app's `src/lib/paceInput.ts`.
public enum PaceInput: Sendable {
    private static let maxRawInputUTF16Length = 64
    private static let maxTrimmedInputUTF16Length = 20

    private static let clockRegex = try! NSRegularExpression(
        pattern: #"^(\d+):([0-5]?\d(?:\.\d+)?)$"#
    )
    private static let bareRegex = try! NSRegularExpression(
        pattern: #"^(\d+(?:\.\d+)?)$"#
    )

    /// Parse a `M:SS` or bare numeric string to positive seconds.
    /// Returns `nil` for invalid or non-positive input.
    public static func parsePaceInput(_ raw: String) -> TimeInterval? {
        guard raw.utf16.count <= maxRawInputUTF16Length else { return nil }

        let s = raw.trimmingCharacters(in: .whitespaces)

        // Bound regex input; utf16.count matches NSRegularExpression's UTF-16 basis.
        guard s.utf16.count <= maxTrimmedInputUTF16Length else { return nil }

        let range = NSRange(s.startIndex..<s.endIndex, in: s)

        if let match = clockRegex.firstMatch(in: s, range: range) {
            guard let minuteRange = Range(match.range(at: 1), in: s),
                  let secondRange = Range(match.range(at: 2), in: s),
                  let minutes = Int(s[minuteRange]),
                  let seconds = Double(s[secondRange]) else {
                return nil
            }
            let total = Double(minutes) * 60 + seconds
            return total > 0 && total.isFinite ? total : nil
        }

        guard let match = bareRegex.firstMatch(in: s, range: range),
              let valueRange = Range(match.range(at: 1), in: s),
              let value = Double(s[valueRange]),
              value > 0,
              value.isFinite else {
            return nil
        }
        return value
    }

    /// Format positive seconds as canonical `M:SS` for display.
    /// Returns empty string for non-positive, non-finite, or unrepresentable input.
    public static func formatPaceInput(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite,
              seconds > 0,
              let whole = Int(exactly: seconds.rounded()) else {
            return ""
        }
        let m = whole / 60
        let sec = whole % 60
        return "\(m):\(String(format: "%02d", sec))"
    }
}
