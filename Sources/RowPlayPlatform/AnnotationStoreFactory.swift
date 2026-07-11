import Foundation
import RowPlayCore

/// Factory that creates the production ``AnnotationStore`` backed by SQLite.
///
/// Creates `Application Support/RowPlayStudio/annotations.sqlite` and returns
/// a ``SQLiteAnnotationStore``. If the database cannot be opened or migrated,
/// it logs through ``PrivacySafeLogger`` and returns an
/// ``UnavailableAnnotationStore``.
public enum AnnotationStoreFactory: Sendable {
    private static let logger = PrivacySafeLogger(category: "annotation-store")

    /// Create the production annotation store.
    ///
    /// - Returns: A ``SQLiteAnnotationStore`` on success, or an
    ///   ``UnavailableAnnotationStore`` if the database cannot be opened.
    public static func makeDefault() -> any AnnotationStore {
        do {
            let path = try defaultDatabasePath()
            return try SQLiteAnnotationStore(path: path)
        } catch {
            logger.error("Failed to open annotation store: \(redact(error))")
            return UnavailableAnnotationStore()
        }
    }

    /// Resolve the default database path under Application Support.
    nonisolated public static func defaultDatabasePath(fileManager: FileManager = .default) throws -> String {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("RowPlayStudio", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("annotations.sqlite").path
    }
}
