import Foundation
import SQLite3

/// SQLite-backed implementation of ``WorkoutCache``.
///
/// Stores workout summaries and full `WorkoutDetail` JSON in a local SQLite
/// database. The schema uses `PRAGMA user_version` for migration tracking;
/// call ``migrate()`` after opening to ensure the schema exists.
///
/// All database access is serialized through an internal dispatch queue,
/// making this type safe to use from any thread.
public final class SQLiteWorkoutCache: WorkoutCache, @unchecked Sendable {
    private let dbPath: String
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.rowplay-studio.sqlite-workout-cache")
    private let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Open (or create) a SQLite database at the given path.
    ///
    /// The database is **not** automatically migrated. Call ``migrate()``
    /// before using any other method to ensure the schema exists.
    ///
    /// - Parameter path: File path for the SQLite database.
    /// - Throws: ``WorkoutCacheError/openFailed(_:)`` if the database cannot be opened.
    public init(path: String) throws {
        self.dbPath = path

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw WorkoutCacheError.openFailed("sqlite3_open_v2 failed (\(rc)): \(msg)")
        }
    }

    deinit {
        sqlite3_close_v2(db)
    }

    // MARK: - Migration

    /// Create the schema if it does not exist and set `user_version` to 1.
    ///
    /// This method is idempotent and safe to call multiple times.
    /// - Throws: ``WorkoutCacheError/migrationFailed(_:)`` if migration SQL fails.
    public func migrate() throws {
        try queue.sync {
            try Migration.run(db: db)
        }
    }

    // MARK: - WorkoutCache

    public func save(details: [WorkoutDetail]) async throws {
        try await withDatabase { [self] in
            guard !details.isEmpty else { return }

            try execute(sql: "BEGIN TRANSACTION;", context: "begin transaction save details")
            var transactionIsOpen = true
            defer {
                if transactionIsOpen {
                    sqlite3_exec(db, "ROLLBACK TRANSACTION;", nil, nil, nil)
                }
            }

            let sql = """
                INSERT OR REPLACE INTO workouts (id, sport, date, workout_type, distance, time, pace, detail_json, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare save details: \(errmsg)")
            }

            let now = Date().timeIntervalSince1970

            for detail in details {
                let data: Data
                do {
                    data = try encoder.encode(detail)
                } catch {
                    throw WorkoutCacheError.encodingFailed("Failed to encode detail \(detail.workout.id)")
                }
                guard let json = String(data: data, encoding: .utf8) else {
                    throw WorkoutCacheError.encodingFailed("UTF-8 conversion failed for detail \(detail.workout.id)")
                }

                let w = detail.workout
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_int64(stmt, 1, sqlite3_int64(w.id))
                sqlite3_bind_text(stmt, 2, w.sport.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 3, w.date.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 4, w.workoutType, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 5, w.distance)
                sqlite3_bind_double(stmt, 6, w.time)
                sqlite3_bind_double(stmt, 7, w.pace)
                sqlite3_bind_text(stmt, 8, json, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 9, now)

                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw WorkoutCacheError.queryFailed("insert save details: \(errmsg)")
                }
            }

            try execute(sql: "COMMIT TRANSACTION;", context: "commit transaction save details")
            transactionIsOpen = false
        }
    }

    public func saveWorkouts(_ workouts: [Workout]) async throws {
        try await withDatabase { [self] in
            guard !workouts.isEmpty else { return }

            try execute(sql: "BEGIN TRANSACTION;", context: "begin transaction saveWorkouts")
            var transactionIsOpen = true
            defer {
                if transactionIsOpen {
                    sqlite3_exec(db, "ROLLBACK TRANSACTION;", nil, nil, nil)
                }
            }

            let sql = """
                INSERT OR REPLACE INTO workouts (id, sport, date, workout_type, distance, time, pace, detail_json, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            var selectStmt: OpaquePointer?
            defer { sqlite3_finalize(selectStmt) }
            let selectSQL = "SELECT detail_json FROM workouts WHERE id = ?;"
            guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare existing detail saveWorkouts: \(errmsg)")
            }

            var insertStmt: OpaquePointer?
            defer { sqlite3_finalize(insertStmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &insertStmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare saveWorkouts: \(errmsg)")
            }

            let now = Date().timeIntervalSince1970

            for workout in workouts {
                let detail = try detailForSummary(workout, using: selectStmt)
                let json = try jsonString(for: detail, context: "workout \(workout.id)")

                sqlite3_reset(insertStmt)
                sqlite3_clear_bindings(insertStmt)
                sqlite3_bind_int64(insertStmt, 1, sqlite3_int64(workout.id))
                sqlite3_bind_text(insertStmt, 2, workout.sport.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(insertStmt, 3, workout.date.timeIntervalSince1970)
                sqlite3_bind_text(insertStmt, 4, workout.workoutType, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(insertStmt, 5, workout.distance)
                sqlite3_bind_double(insertStmt, 6, workout.time)
                sqlite3_bind_double(insertStmt, 7, workout.pace)
                sqlite3_bind_text(insertStmt, 8, json, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(insertStmt, 9, now)

                guard sqlite3_step(insertStmt) == SQLITE_DONE else {
                    throw WorkoutCacheError.queryFailed("insert saveWorkouts: \(errmsg)")
                }
            }

            try execute(sql: "COMMIT TRANSACTION;", context: "commit transaction saveWorkouts")
            transactionIsOpen = false
        }
    }

    public func save(detail: WorkoutDetail) async throws {
        try await withDatabase { [self] in
            let sql = """
                INSERT OR REPLACE INTO workouts (id, sport, date, workout_type, distance, time, pace, detail_json, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare saveDetail: \(errmsg)")
            }

            let json = try jsonString(for: detail, context: "detail \(detail.workout.id)")

            let w = detail.workout
            sqlite3_bind_int64(stmt, 1, sqlite3_int64(w.id))
            sqlite3_bind_text(stmt, 2, w.sport.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, w.date.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 4, w.workoutType, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 5, w.distance)
            sqlite3_bind_double(stmt, 6, w.time)
            sqlite3_bind_double(stmt, 7, w.pace)
            sqlite3_bind_text(stmt, 8, json, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 9, Date().timeIntervalSince1970)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw WorkoutCacheError.queryFailed("insert saveDetail: \(errmsg)")
            }
        }
    }

    public func loadAllWorkouts() async throws -> [Workout] {
        try await withDatabase { [self] in
            let sql = "SELECT detail_json FROM workouts ORDER BY date DESC;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare loadAllWorkouts: \(errmsg)")
            }

            var results: [Workout] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE {
                    break
                }
                guard rc == SQLITE_ROW else {
                    throw WorkoutCacheError.queryFailed("step loadAllWorkouts: \(errmsg)")
                }
                let detail = try decodeDetail(from: stmt, column: 0, context: "workout list row")
                results.append(detail.workout)
            }
            return results
        }
    }

    public func detail(id: Workout.ID) async throws -> WorkoutDetail? {
        try await withDatabase { [self] in
            let sql = "SELECT detail_json FROM workouts WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare loadWorkout: \(errmsg)")
            }

            sqlite3_bind_int64(stmt, 1, sqlite3_int64(id))

            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE {
                return nil
            }
            guard rc == SQLITE_ROW else {
                throw WorkoutCacheError.queryFailed("step loadWorkout \(id): \(errmsg)")
            }
            return try decodeDetail(from: stmt, column: 0, context: "workout \(id)")
        }
    }

    public func delete(id: Workout.ID) async throws {
        try await withDatabase { [self] in
            let sql = "DELETE FROM workouts WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare delete: \(errmsg)")
            }

            sqlite3_bind_int64(stmt, 1, sqlite3_int64(id))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw WorkoutCacheError.queryFailed("execute delete: \(errmsg)")
            }
        }
    }

    public func listWorkouts() async throws -> [Workout] {
        try await loadAllWorkouts()
    }

    public func deleteAll() async throws {
        try await withDatabase { [self] in
            let sql = "DELETE FROM workouts;"
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("deleteAll: \(errmsg)")
            }
        }
    }

    // MARK: - Internal

    /// Run a raw SQL query that returns a single integer value.
    /// Used by tests to verify `PRAGMA user_version`.
    func userVersion() throws -> Int32 {
        try queue.sync {
            let sql = "PRAGMA user_version;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare userVersion: \(errmsg)")
            }

            guard sqlite3_step(stmt) == SQLITE_ROW else {
                return 0
            }
            return sqlite3_column_int(stmt, 0)
        }
    }

    // MARK: - Private

    private var errmsg: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no db handle"
    }

    private func withDatabase<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func execute(sql: String, context: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("\(context): \(errmsg)")
        }
    }

    private func jsonString(for detail: WorkoutDetail, context: String) throws -> String {
        let data: Data
        do {
            data = try encoder.encode(detail)
        } catch {
            throw WorkoutCacheError.encodingFailed("Failed to encode \(context)")
        }
        guard let json = String(data: data, encoding: .utf8) else {
            throw WorkoutCacheError.encodingFailed("UTF-8 conversion failed for \(context)")
        }
        return json
    }

    private func detailForSummary(_ workout: Workout, using stmt: OpaquePointer?) throws -> WorkoutDetail {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        sqlite3_bind_int64(stmt, 1, sqlite3_int64(workout.id))

        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW {
            var existing = try decodeDetail(from: stmt, column: 0, context: "existing workout \(workout.id)")
            existing.workout = workout
            return existing
        }
        if rc == SQLITE_DONE {
            return WorkoutDetail(workout: workout, strokes: [], splits: [])
        }
        throw WorkoutCacheError.queryFailed("select existing detail saveWorkouts \(workout.id): \(errmsg)")
    }

    private func decodeDetail(from stmt: OpaquePointer?, column: Int32, context: String) throws -> WorkoutDetail {
        guard let bytes = sqlite3_column_text(stmt, column) else {
            throw WorkoutCacheError.decodingFailed("NULL detail_json for \(context)")
        }
        let length = sqlite3_column_bytes(stmt, column)
        let data = Data(bytes: bytes, count: Int(length))
        do {
            return try decoder.decode(WorkoutDetail.self, from: data)
        } catch {
            throw WorkoutCacheError.decodingFailed("JSON decode failed for \(context)")
        }
    }
}
