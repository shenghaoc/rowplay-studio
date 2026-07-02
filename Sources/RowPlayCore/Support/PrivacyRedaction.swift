import Foundation

/// Concept2 privacy level guard for share links.
///
/// Mirrors `src/lib/privacy.ts` from the web app. A public share link is allowed
/// ONLY when the Concept2 `privacy` value is exactly `"everyone"`. Narrower levels
/// and any absent or unrecognised value are treated as non-public.
public enum PrivacyRedaction {
    private static let publicLevel = "everyone"

    /// Whether a workout may be exposed through a public share link.
    ///
    /// Fail closed: returns `true` only when `privacy` is `"everyone"` (case-insensitive, trimmed).
    public static func isPubliclyShareable(privacy: String?) -> Bool {
        guard let value = privacy?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return false
        }
        return value == publicLevel
    }
}
