import Foundation

#if compiler(<5.10)
extension NSLock {
    /// Backport of Foundation's lock-scoped helper for Swift toolchains that
    /// predate the standard `withLock` API.
    @inlinable
    public func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}
#endif
