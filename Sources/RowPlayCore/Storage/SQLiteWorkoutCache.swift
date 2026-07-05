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
    private var db: OpaquePointer?
    private var hasMigrated = false
    private let queue = DispatchQueue(label: "com.rowplay-studio.sqlite-workout-cache")
    private let logger = PrivacySafeLogger(category: "sqlite-cache")
    private static let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
    private static let upsertWorkoutSQL = """
        INSERT OR REPLACE INTO workouts (
            id, sport, date, workout_type, distance, time, pace,
            stroke_rate, stroke_count, heart_rate_avg, calories_total,
            watt_minutes, drag_factor, comments, source, verified,
            has_stroke_data, is_interval, detail_json, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

    /// Column indices for the summary SELECT in `listWorkouts()`.
    private enum Column {
        static let id: Int32 = 0
        static let sport: Int32 = 1
        static let date: Int32 = 2
        static let workoutType: Int32 = 3
        static let distance: Int32 = 4
        static let time: Int32 = 5
        static let pace: Int32 = 6
        static let strokeRate: Int32 = 7
        static let strokeCount: Int32 = 8
        static let heartRateAvg: Int32 = 9
        static let caloriesTotal: Int32 = 10
        static let wattMinutes: Int32 = 11
        static let dragFactor: Int32 = 12
        static let comments: Int32 = 13
        static let source: Int32 = 14
        static let verified: Int32 = 15
        static let hasStrokeData: Int32 = 16
        static let isInterval: Int32 = 17
    }

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
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close_v2(db)
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
    /// It is a synchronous setup step; call it before handing the cache to
    /// async workflows. Calling it reentrantly from cache internals would
    /// deadlock on the serial database queue.
    /// - Throws: ``WorkoutCacheError/migrationFailed(_:)`` if migration SQL fails.
    public func migrate() throws {
        try queue.sync {
            try Migration.run(db: db)
            hasMigrated = true
        }
    }

    // MARK: - WorkoutCache

    public func save(details: [WorkoutDetail]) async throws {
        try await withDatabase { [self] in
            try ensureMigrated()
            guard !details.isEmpty else { return }

            try execute(sql: "BEGIN TRANSACTION;", context: "begin transaction save details")
            var transactionIsOpen = true
            defer {
                if transactionIsOpen {
                    rollbackOrLog()
                }
            }

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, Self.upsertWorkoutSQL, -1, &stmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare save details: \(errmsg)")
            }

            let now = Date().timeIntervalSince1970

            for detail in details {
                let json = try jsonString(for: detail, context: "detail \(detail.workout.id)")
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                try bind(workout: detail.workout, detailJSON: json, updatedAt: now, to: stmt)

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
            try ensureMigrated()
            guard !workouts.isEmpty else { return }

            try execute(sql: "BEGIN TRANSACTION;", context: "begin transaction saveWorkouts")
            var transactionIsOpen = true
            defer {
                if transactionIsOpen {
                    rollbackOrLog()
                }
            }

            var selectStmt: OpaquePointer?
            defer { sqlite3_finalize(selectStmt) }
            let selectSQL = "SELECT detail_json FROM workouts WHERE id = ?;"
            guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare existing detail saveWorkouts: \(errmsg)")
            }

            var insertStmt: OpaquePointer?
            defer { sqlite3_finalize(insertStmt) }

            guard sqlite3_prepare_v2(db, Self.upsertWorkoutSQL, -1, &insertStmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare saveWorkouts: \(errmsg)")
            }

            let now = Date().timeIntervalSince1970

            for workout in workouts {
                let detail = try detailForSummary(workout, using: selectStmt)
                let json = try jsonString(for: detail, context: "workout \(workout.id)")

                sqlite3_reset(insertStmt)
                sqlite3_clear_bindings(insertStmt)
                try bind(workout: workout, detailJSON: json, updatedAt: now, to: insertStmt)

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
            try ensureMigrated()

            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, Self.upsertWorkoutSQL, -1, &stmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare saveDetail: \(errmsg)")
            }

            let json = try jsonString(for: detail, context: "detail \(detail.workout.id)")
            try bind(workout: detail.workout, detailJSON: json, updatedAt: Date().timeIntervalSince1970, to: stmt)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw WorkoutCacheError.queryFailed("insert saveDetail: \(errmsg)")
            }
        }
    }

    public func listWorkouts() async throws -> [Workout] {
        try await withDatabase { [self] in
            try ensureMigrated()

            let sql = """
                SELECT id, sport, date, workout_type, distance, time, pace,
                    stroke_rate, stroke_count, heart_rate_avg, calories_total,
                    watt_minutes, drag_factor, comments, source, verified,
                    has_stroke_data, is_interval
                FROM workouts
                ORDER BY date DESC;
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare listWorkouts: \(errmsg)")
            }

            var results: [Workout] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE {
                    break
                }
                guard rc == SQLITE_ROW else {
                    throw WorkoutCacheError.queryFailed("step listWorkouts: \(errmsg)")
                }
                results.append(try workout(from: stmt))
            }
            return results
        }
    }

    public func detail(id: Workout.ID) async throws -> WorkoutDetail? {
        try await withDatabase { [self] in
            try ensureMigrated()
            let sql = "SELECT detail_json FROM workouts WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare loadWorkout: \(errmsg)")
            }

            guard sqlite3_bind_int64(stmt, 1, sqlite3_int64(id)) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("bind detail id \(id): \(errmsg)")
            }

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
            try ensureMigrated()
            let sql = "DELETE FROM workouts WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("prepare delete: \(errmsg)")
            }

            guard sqlite3_bind_int64(stmt, 1, sqlite3_int64(id)) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("bind delete id \(id): \(errmsg)")
            }

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw WorkoutCacheError.queryFailed("execute delete: \(errmsg)")
            }
        }
    }

    public func deleteAll() async throws {
        try await withDatabase { [self] in
            try ensureMigrated()

            try execute(sql: "BEGIN TRANSACTION;", context: "begin transaction deleteAll")
            var transactionIsOpen = true
            defer {
                if transactionIsOpen {
                    rollbackOrLog()
                }
            }

            let sql = "DELETE FROM workouts;"
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw WorkoutCacheError.queryFailed("deleteAll: \(errmsg)")
            }

            try execute(sql: "COMMIT TRANSACTION;", context: "commit transaction deleteAll")
            transactionIsOpen = false
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

            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                return sqlite3_column_int(stmt, 0)
            }
            if rc == SQLITE_DONE {
                return 0
            }
            throw WorkoutCacheError.queryFailed("step userVersion: \(errmsg)")
        }
    }

    // MARK: - Private

    private var errmsg: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no db handle"
    }

    private func withDatabase<T>(_ operation: @Sendable @escaping () throws -> T) async throws -> T {
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

    /// Throw if `migrate()` has not been called yet.
    private func ensureMigrated() throws {
        guard hasMigrated else {
            throw WorkoutCacheError.migrationFailed("cache not migrated: call migrate() before using the cache")
        }
    }

    /// Attempt a ROLLBACK; log the failure if it cannot be thrown.
    private func rollbackOrLog() {
        let rc = sqlite3_exec(db, "ROLLBACK TRANSACTION;", nil, nil, nil)
        if rc != SQLITE_OK {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            logger.error("ROLLBACK failed rc=\(rc)", msg)
        }
    }

    private func jsonString(for detail: WorkoutDetail, context: String) throws -> String {
        let data: Data
        do {
            data = try encoder.encode(detail)
        } catch {
            throw WorkoutCacheError.encodingFailed("Failed to encode \(context): \(error)")
        }
        guard let json = String(data: data, encoding: .utf8) else {
            throw WorkoutCacheError.encodingFailed("UTF-8 conversion failed for \(context)")
        }
        return json
    }

    private func bind(workout: Workout, detailJSON: String, updatedAt: TimeInterval, to stmt: OpaquePointer?) throws {
        var rc = sqlite3_bind_int64(stmt, 1, sqlite3_int64(workout.id))
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[1] id: \(errmsg)")
        }
        rc = sqlite3_bind_text(stmt, 2, workout.sport.rawValue, -1, Self.SQLITE_TRANSIENT)
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[2] sport: \(errmsg)")
        }
        rc = sqlite3_bind_double(stmt, 3, workout.date.timeIntervalSince1970)
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[3] date: \(errmsg)")
        }
        rc = sqlite3_bind_text(stmt, 4, workout.workoutType, -1, Self.SQLITE_TRANSIENT)
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[4] workoutType: \(errmsg)")
        }
        rc = sqlite3_bind_double(stmt, 5, workout.distance)
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[5] distance: \(errmsg)")
        }
        rc = sqlite3_bind_double(stmt, 6, workout.time)
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[6] time: \(errmsg)")
        }
        rc = sqlite3_bind_double(stmt, 7, workout.pace)
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[7] pace: \(errmsg)")
        }
        try bindOptional(workout.strokeRate, to: stmt, index: 8, name: "strokeRate")
        try bindOptional(workout.strokeCount, to: stmt, index: 9, name: "strokeCount")
        try bindOptional(workout.heartRateAvg, to: stmt, index: 10, name: "heartRateAvg")
        try bindOptional(workout.caloriesTotal, to: stmt, index: 11, name: "caloriesTotal")
        try bindOptional(workout.wattMinutes, to: stmt, index: 12, name: "wattMinutes")
        try bindOptional(workout.dragFactor, to: stmt, index: 13, name: "dragFactor")
        try bindOptional(workout.comments, to: stmt, index: 14, name: "comments")
        try bindOptional(workout.source, to: stmt, index: 15, name: "source")
        rc = sqlite3_bind_int(stmt, 16, workout.verified ? 1 : 0)
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[16] verified: \(errmsg)")
        }
        rc = sqlite3_bind_int(stmt, 17, workout.hasStrokeData ? 1 : 0)
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[17] hasStrokeData: \(errmsg)")
        }
        rc = sqlite3_bind_int(stmt, 18, workout.isInterval ? 1 : 0)
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[18] isInterval: \(errmsg)")
        }
        rc = sqlite3_bind_text(stmt, 19, detailJSON, -1, Self.SQLITE_TRANSIENT)
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[19] detail_json: \(errmsg)")
        }
        rc = sqlite3_bind_double(stmt, 20, updatedAt)
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[20] updated_at: \(errmsg)")
        }
    }

    private func bindOptional(_ value: Double?, to stmt: OpaquePointer?, index: Int32, name: String) throws {
        let rc: Int32
        if let value {
            rc = sqlite3_bind_double(stmt, index, value)
        } else {
            rc = sqlite3_bind_null(stmt, index)
        }
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[\(index)] \(name): \(errmsg)")
        }
    }

    private func bindOptional(_ value: Int?, to stmt: OpaquePointer?, index: Int32, name: String) throws {
        let rc: Int32
        if let value {
            rc = sqlite3_bind_int64(stmt, index, sqlite3_int64(value))
        } else {
            rc = sqlite3_bind_null(stmt, index)
        }
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[\(index)] \(name): \(errmsg)")
        }
    }

    private func bindOptional(_ value: String?, to stmt: OpaquePointer?, index: Int32, name: String) throws {
        let rc: Int32
        if let value {
            rc = sqlite3_bind_text(stmt, index, value, -1, Self.SQLITE_TRANSIENT)
        } else {
            rc = sqlite3_bind_null(stmt, index)
        }
        guard rc == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind[\(index)] \(name): \(errmsg)")
        }
    }

    private func detailForSummary(_ workout: Workout, using stmt: OpaquePointer?) throws -> WorkoutDetail {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        guard sqlite3_bind_int64(stmt, 1, sqlite3_int64(workout.id)) == SQLITE_OK else {
            throw WorkoutCacheError.queryFailed("bind detailForSummary id \(workout.id): \(errmsg)")
        }

        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW {
            // If the stored detail_json is corrupt, fall back to an empty detail
            // so the batch can continue; summary columns are still valid.
            var existing: WorkoutDetail
            do {
                existing = try decodeDetail(from: stmt, column: 0, context: "existing workout \(workout.id)")
            } catch {
                existing = WorkoutDetail(workout: workout, strokes: [], splits: [])
            }
            // Keep cached strokes/splits while refreshing the embedded summary.
            existing.workout = workout
            return existing
        }
        if rc == SQLITE_DONE {
            return WorkoutDetail(workout: workout, strokes: [], splits: [])
        }
        throw WorkoutCacheError.queryFailed("select existing detail saveWorkouts \(workout.id): \(errmsg)")
    }

    private func workout(from stmt: OpaquePointer?) throws -> Workout {
        let rawSport = try stringColumn(stmt, Column.sport, context: "workout sport")
        guard let sport = Sport(rawValue: rawSport) else {
            throw WorkoutCacheError.decodingFailed("Invalid sport \(rawSport)")
        }

        return Workout(
            id: Int(sqlite3_column_int64(stmt, Column.id)),
            date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, Column.date)),
            sport: sport,
            distance: sqlite3_column_double(stmt, Column.distance),
            time: sqlite3_column_double(stmt, Column.time),
            pace: sqlite3_column_double(stmt, Column.pace),
            strokeRate: optionalDoubleColumn(stmt, Column.strokeRate),
            strokeCount: optionalIntColumn(stmt, Column.strokeCount),
            heartRateAvg: optionalIntColumn(stmt, Column.heartRateAvg),
            caloriesTotal: optionalIntColumn(stmt, Column.caloriesTotal),
            wattMinutes: optionalDoubleColumn(stmt, Column.wattMinutes),
            dragFactor: optionalIntColumn(stmt, Column.dragFactor),
            workoutType: try stringColumn(stmt, Column.workoutType, context: "workout type"),
            comments: try optionalStringColumn(stmt, Column.comments),
            source: try optionalStringColumn(stmt, Column.source),
            verified: sqlite3_column_int(stmt, Column.verified) != 0,
            hasStrokeData: sqlite3_column_int(stmt, Column.hasStrokeData) != 0,
            isInterval: sqlite3_column_int(stmt, Column.isInterval) != 0
        )
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
            throw WorkoutCacheError.decodingFailed("JSON decode failed for \(context): \(error)")
        }
    }

    private func stringColumn(_ stmt: OpaquePointer?, _ column: Int32, context: String) throws -> String {
        guard let bytes = sqlite3_column_text(stmt, column) else {
            throw WorkoutCacheError.decodingFailed("NULL \(context)")
        }
        let length = sqlite3_column_bytes(stmt, column)
        let buffer = UnsafeBufferPointer(start: bytes, count: Int(length))
        return String(decoding: buffer, as: UTF8.self)
    }

    private func optionalStringColumn(_ stmt: OpaquePointer?, _ column: Int32) throws -> String? {
        guard sqlite3_column_type(stmt, column) != SQLITE_NULL else {
            return nil
        }
        return try stringColumn(stmt, column, context: "optional text column \(column)")
    }

    private func optionalDoubleColumn(_ stmt: OpaquePointer?, _ column: Int32) -> Double? {
        sqlite3_column_type(stmt, column) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, column)
    }

    private func optionalIntColumn(_ stmt: OpaquePointer?, _ column: Int32) -> Int? {
        sqlite3_column_type(stmt, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, column))
    }
}
