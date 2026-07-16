import Foundation

/// Path helpers used by rival import surfaces that must not depend on
/// Foundation `URL` parsing of untrusted display strings.
enum ReplayPathUtilities: Sendable {
    /// Returns the last path component, accepting mixed POSIX and Windows
    /// separators and ignoring a trailing separator run.
    ///
    /// Sequential per-separator scans are incorrect for values such as
    /// `#"C:\Users\me/exports\rival.csv"#`, which must resolve to `rival.csv`.
    static func lastPathComponent(_ path: String) -> String {
        let separators: Set<Character> = ["/", "\\"]
        var end = path.endIndex
        while end > path.startIndex {
            let previous = path.index(before: end)
            guard separators.contains(path[previous]) else { break }
            end = previous
        }
        let trimmed = path[..<end]
        if let lastSeparator = trimmed.lastIndex(where: { separators.contains($0) }) {
            return String(trimmed[trimmed.index(after: lastSeparator)...])
        }
        return String(trimmed)
    }
}
