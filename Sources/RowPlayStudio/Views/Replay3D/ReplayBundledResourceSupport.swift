import CryptoKit
import Foundation

/// Shared, deliberately small support for immutable resources bundled with
/// the replay runtime. Domain-specific loaders retain their own validation,
/// caching, and failure policies.
enum ReplayBundledResourceSupport {
    private static let hashChunkSize = 1_048_576

    static func bundledURL(
        name: String,
        extension ext: String,
        subdirectory: String,
        bundle: Bundle = .module
    ) -> URL? {
        bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? bundle.url(forResource: name, withExtension: ext)
    }

    static func sha256Hex(of data: Data) -> String {
        hexString(SHA256.hash(data: data))
    }

    /// Hash a potentially large authored package without materializing a
    /// second full copy before RealityKit opens the same URL.
    static func sha256Hex(contentsOf url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: hashChunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hexString(hasher.finalize())
    }

    private static func hexString<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
