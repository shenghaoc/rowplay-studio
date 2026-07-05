import Foundation
import SQLite3

/// Schema migration logic for the SQLite workout cache.
///
/// Uses `PRAGMA user_version` for version tracking. The initial schema (v1)
/// stores workout summaries plus full `WorkoutDetail` JSON in a single table.
enum Migration {
    /// The current schema version.
    static let currentVersion: Int32 = 1

    /// Run all pending migrations on the given database handle.
    ///
    /// This method is idempotent: calling it multiple times on the same
    /// database is safe and will not fail or duplicate data.
    ///
    /// - Parameter db: An open SQLite3 database handle.
    /// - Throws: `WorkoutCacheError.migrationFailed` if any SQL fails.
    static func run(db: OpaquePointer?) throws {
        let createSQL = """
            CREATE TABLE IF NOT EXISTS workouts (
                id INTEGER PRIMARY KEY,
                sport TEXT NOT NULL,
                date REAL NOT NULL,
                workout_type TEXT NOT NULL,
                distance REAL NOT NULL,
                time REAL NOT NULL,
                pace REAL NOT NULL,
                detail_json TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            """

        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw WorkoutCacheError.migrationFailed("CREATE TABLE failed: \(msg)")
        }

        let pragmaSQL = "PRAGMA user_version = \(currentVersion);"
        guard sqlite3_exec(db, pragmaSQL, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw WorkoutCacheError.migrationFailed("PRAGMA user_version failed: \(msg)")
        }
    }
}
