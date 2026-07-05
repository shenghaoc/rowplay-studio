import Foundation
import SQLite3

/// Schema migration logic for the SQLite workout cache.
///
/// Uses `PRAGMA user_version` for version tracking. The initial schema (v1)
/// stores workout summaries plus full `WorkoutDetail` JSON in a single table.
enum Migration {
    /// The current schema version.
    static let currentVersion: Int32 = 1

    private static let summaryColumns: [(name: String, definition: String)] = [
        ("stroke_rate", "stroke_rate REAL"),
        ("stroke_count", "stroke_count INTEGER"),
        ("heart_rate_avg", "heart_rate_avg INTEGER"),
        ("calories_total", "calories_total INTEGER"),
        ("watt_minutes", "watt_minutes REAL"),
        ("drag_factor", "drag_factor INTEGER"),
        ("comments", "comments TEXT"),
        ("source", "source TEXT"),
        ("verified", "verified INTEGER NOT NULL DEFAULT 1"),
        ("has_stroke_data", "has_stroke_data INTEGER NOT NULL DEFAULT 0"),
        ("is_interval", "is_interval INTEGER NOT NULL DEFAULT 0")
    ]

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
                stroke_rate REAL,
                stroke_count INTEGER,
                heart_rate_avg INTEGER,
                calories_total INTEGER,
                watt_minutes REAL,
                drag_factor INTEGER,
                comments TEXT,
                source TEXT,
                verified INTEGER NOT NULL DEFAULT 1,
                has_stroke_data INTEGER NOT NULL DEFAULT 0,
                is_interval INTEGER NOT NULL DEFAULT 0,
                detail_json TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            """

        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw WorkoutCacheError.migrationFailed("CREATE TABLE failed: \(msg)")
        }

        try addMissingSummaryColumns(db: db)

        let indexSQL = "CREATE INDEX IF NOT EXISTS idx_workouts_date ON workouts (date DESC);"
        guard sqlite3_exec(db, indexSQL, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw WorkoutCacheError.migrationFailed("CREATE INDEX failed: \(msg)")
        }

        let pragmaSQL = "PRAGMA user_version = \(currentVersion);"
        guard sqlite3_exec(db, pragmaSQL, nil, nil, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw WorkoutCacheError.migrationFailed("PRAGMA user_version failed: \(msg)")
        }
    }

    private static func addMissingSummaryColumns(db: OpaquePointer?) throws {
        let existing = try existingColumnNames(db: db)
        for column in summaryColumns where !existing.contains(column.name) {
            let alterSQL = "ALTER TABLE workouts ADD COLUMN \(column.definition);"
            guard sqlite3_exec(db, alterSQL, nil, nil, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw WorkoutCacheError.migrationFailed("ALTER TABLE add \(column.name) failed: \(msg)")
            }
        }
    }

    private static func existingColumnNames(db: OpaquePointer?) throws -> Set<String> {
        let sql = "PRAGMA table_info(workouts);"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw WorkoutCacheError.migrationFailed("PRAGMA table_info failed: \(msg)")
        }

        var columns = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(stmt, 1) else { continue }
            columns.insert(String(cString: cString))
        }
        return columns
    }
}
