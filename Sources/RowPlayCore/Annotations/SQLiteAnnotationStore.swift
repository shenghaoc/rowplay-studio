import Foundation
import SQLite3

/// SQLite-backed implementation of ``AnnotationStore``.
///
/// Stores annotations in a dedicated `annotations.sqlite` database, separate
/// from the workout cache. The database is opened and migrated automatically
/// on initialization — unlike ``SQLiteWorkoutCache`` which requires an explicit
/// ``SQLiteWorkoutCache/migrate()`` call — so ``AnnotationStore`` callers need
/// no migration method.
///
/// All database access is serialized through an internal dispatch queue,
/// making this type safe to use from any thread.
public final class SQLiteAnnotationStore: AnnotationStore, @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.rowplay-studio.sqlite-annotation-store")
    private static let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    /// Open (or create) the annotation database at the given path and run
    /// migrations automatically.
    ///
    /// - Parameter path: File path for the SQLite database.
    /// - Throws: ``AnnotationError/storageFailed`` if the database cannot
    ///   be opened or migrated.
    public init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK else {
            sqlite3_close_v2(db)
            db = nil
            throw AnnotationError.storageFailed("sqlite3_open_v2 failed (\(rc))")
        }

        do {
            try migrate()
        } catch {
            sqlite3_close_v2(db)
            db = nil
            throw error
        }
    }

    deinit {
        sqlite3_close_v2(db)
    }

    // MARK: - Migration

    private static let currentVersion: Int32 = 1

    /// Run schema migration idempotently. Uses `PRAGMA user_version` for
    /// version tracking.
    private func migrate() throws {
        try queue.sync {
            let version = try userVersion()
            guard version < Self.currentVersion else { return }

            guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
                throw AnnotationError.storageFailed("migration: BEGIN failed")
            }
            var transactionOpen = true
            defer {
                if transactionOpen {
                    sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                }
            }

            let createSQL = """
                CREATE TABLE IF NOT EXISTS annotations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    workout_id INTEGER NOT NULL,
                    timestamp REAL NOT NULL,
                    text TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                );
                """
            guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
                throw AnnotationError.storageFailed("migration: CREATE TABLE failed")
            }

            let indexSQL = """
                CREATE INDEX IF NOT EXISTS idx_annotations_workout_timestamp
                    ON annotations (workout_id, timestamp, id);
                """
            guard sqlite3_exec(db, indexSQL, nil, nil, nil) == SQLITE_OK else {
                throw AnnotationError.storageFailed("migration: CREATE INDEX failed")
            }

            let pragmaSQL = "PRAGMA user_version = \(Self.currentVersion);"
            guard sqlite3_exec(db, pragmaSQL, nil, nil, nil) == SQLITE_OK else {
                throw AnnotationError.storageFailed("migration: PRAGMA user_version failed")
            }

            guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw AnnotationError.storageFailed("migration: COMMIT failed")
            }
            transactionOpen = false
        }
    }

    private func userVersion() throws -> Int32 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK else {
            throw AnnotationError.storageFailed("prepare user_version failed")
        }
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW {
            return sqlite3_column_int(stmt, 0)
        }
        guard rc == SQLITE_DONE else {
            throw AnnotationError.storageFailed("step user_version failed (\(rc))")
        }
        return 0
    }

    // MARK: - AnnotationStore

    public func loadAnnotations(workoutId: Int) async throws -> [Annotation] {
        try await withDatabase { [self] in
            let sql = """
                SELECT id, timestamp, text, created_at
                FROM annotations
                WHERE workout_id = ?
                ORDER BY timestamp ASC, id ASC;
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw AnnotationError.storageFailed("prepare loadAnnotations failed")
            }
            guard sqlite3_bind_int64(stmt, 1, Int64(workoutId)) == SQLITE_OK else {
                throw AnnotationError.storageFailed("bind loadAnnotations workout_id")
            }

            var results: [Annotation] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else {
                    throw AnnotationError.storageFailed("step loadAnnotations failed")
                }
                let id = Int(sqlite3_column_int64(stmt, 0))
                let timestamp = sqlite3_column_double(stmt, 1)
                let text = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let createdAt = Int64(sqlite3_column_int64(stmt, 3))
                results.append(Annotation(id: id, timestamp: timestamp, text: text, createdAt: createdAt))
            }
            return results
        }
    }

    public func saveAnnotation(workoutId: Int, _ annotation: Annotation) async throws -> Annotation {
        let normalized = try annotation.normalizedForSave()

        return try await withDatabase { [self] in
            if normalized.id == 0 {
                return try insert(workoutId: workoutId, annotation: normalized)
            } else {
                return try update(workoutId: workoutId, annotation: normalized)
            }
        }
    }

    public func deleteAnnotation(workoutId: Int, id: Int) async throws {
        try await withDatabase { [self] in
            let sql = "DELETE FROM annotations WHERE workout_id = ? AND id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw AnnotationError.storageFailed("prepare deleteAnnotation failed")
            }
            guard sqlite3_bind_int64(stmt, 1, Int64(workoutId)) == SQLITE_OK else {
                throw AnnotationError.storageFailed("bind deleteAnnotation workout_id")
            }
            guard sqlite3_bind_int64(stmt, 2, Int64(id)) == SQLITE_OK else {
                throw AnnotationError.storageFailed("bind deleteAnnotation id")
            }

            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE else {
                throw AnnotationError.storageFailed("step deleteAnnotation failed")
            }
        }
    }

    public func deleteAll() async throws {
        try await withDatabase { [self] in
            guard sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) == SQLITE_OK else {
                throw AnnotationError.storageFailed("deleteAll: BEGIN failed")
            }
            var committed = false
            defer {
                if !committed { sqlite3_exec(db, "ROLLBACK;", nil, nil, nil) }
            }
            guard sqlite3_exec(db, "DELETE FROM annotations;", nil, nil, nil) == SQLITE_OK else {
                throw AnnotationError.storageFailed("deleteAll: DELETE failed")
            }
            guard sqlite3_exec(db, "DELETE FROM sqlite_sequence WHERE name='annotations';", nil, nil, nil) == SQLITE_OK else {
                throw AnnotationError.storageFailed("deleteAll: reset sequence failed")
            }
            guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw AnnotationError.storageFailed("deleteAll: COMMIT failed")
            }
            committed = true
        }
    }

    // MARK: - Private Helpers

    private func insert(workoutId: Int, annotation: Annotation) throws -> Annotation {
        let sql = """
            INSERT INTO annotations (workout_id, timestamp, text, created_at)
            VALUES (?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw AnnotationError.storageFailed("prepare insert failed")
        }
        guard sqlite3_bind_int64(stmt, 1, Int64(workoutId)) == SQLITE_OK else {
            throw AnnotationError.storageFailed("bind insert workout_id")
        }
        guard sqlite3_bind_double(stmt, 2, annotation.timestamp) == SQLITE_OK else {
            throw AnnotationError.storageFailed("bind insert timestamp")
        }
        guard sqlite3_bind_text(stmt, 3, annotation.text, -1, Self.SQLITE_TRANSIENT) == SQLITE_OK else {
            throw AnnotationError.storageFailed("bind insert text")
        }
        guard sqlite3_bind_int64(stmt, 4, annotation.createdAt) == SQLITE_OK else {
            throw AnnotationError.storageFailed("bind insert created_at")
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw AnnotationError.storageFailed("step insert failed")
        }

        let newId = Int(sqlite3_last_insert_rowid(db))
        return Annotation(
            id: newId,
            timestamp: annotation.timestamp,
            text: annotation.text,
            createdAt: annotation.createdAt
        )
    }

    private func update(workoutId: Int, annotation: Annotation) throws -> Annotation {
        // First verify the annotation belongs to this workout and get createdAt.
        let selectSQL = "SELECT created_at FROM annotations WHERE workout_id = ? AND id = ?;"
        var selectStmt: OpaquePointer?
        defer { sqlite3_finalize(selectStmt) }

        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
            throw AnnotationError.storageFailed("prepare update select failed")
        }
        guard sqlite3_bind_int64(selectStmt, 1, Int64(workoutId)) == SQLITE_OK else {
            throw AnnotationError.storageFailed("bind update select workout_id")
        }
        guard sqlite3_bind_int64(selectStmt, 2, Int64(annotation.id)) == SQLITE_OK else {
            throw AnnotationError.storageFailed("bind update select id")
        }

        let rc = sqlite3_step(selectStmt)
        if rc == SQLITE_DONE {
            throw AnnotationError.notFound
        }
        guard rc == SQLITE_ROW else {
            throw AnnotationError.storageFailed("step update select failed (\(rc))")
        }
        let originalCreatedAt = Int64(sqlite3_column_int64(selectStmt, 0))

        // Update the annotation preserving the original createdAt.
        let updateSQL = """
            UPDATE annotations SET timestamp = ?, text = ?
            WHERE workout_id = ? AND id = ?;
            """
        var updateStmt: OpaquePointer?
        defer { sqlite3_finalize(updateStmt) }

        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else {
            throw AnnotationError.storageFailed("prepare update failed")
        }
        guard sqlite3_bind_double(updateStmt, 1, annotation.timestamp) == SQLITE_OK else {
            throw AnnotationError.storageFailed("bind update timestamp")
        }
        guard sqlite3_bind_text(updateStmt, 2, annotation.text, -1, Self.SQLITE_TRANSIENT) == SQLITE_OK else {
            throw AnnotationError.storageFailed("bind update text")
        }
        guard sqlite3_bind_int64(updateStmt, 3, Int64(workoutId)) == SQLITE_OK else {
            throw AnnotationError.storageFailed("bind update workout_id")
        }
        guard sqlite3_bind_int64(updateStmt, 4, Int64(annotation.id)) == SQLITE_OK else {
            throw AnnotationError.storageFailed("bind update id")
        }

        guard sqlite3_step(updateStmt) == SQLITE_DONE else {
            throw AnnotationError.storageFailed("step update failed")
        }

        return Annotation(
            id: annotation.id,
            timestamp: annotation.timestamp,
            text: annotation.text,
            createdAt: originalCreatedAt
        )
    }

    /// Execute a synchronous database operation on the serial queue.
    private func withDatabase<T>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try body()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
