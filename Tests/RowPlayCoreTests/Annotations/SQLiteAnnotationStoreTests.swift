import SQLite3
import XCTest
@testable import RowPlayCore

final class SQLiteAnnotationStoreTests: XCTestCase {
    private var tempDir: URL!
    private var dbPath: String!
    private var store: SQLiteAnnotationStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteAnnotationStoreTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbPath = tempDir.appendingPathComponent("annotations.db").path
        store = try! SQLiteAnnotationStore(path: dbPath)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Init Failure

    func testInitFailsOnInvalidPath() {
        let badPath = "/nonexistent/\(UUID().uuidString)/db.sqlite"
        XCTAssertThrowsError(try SQLiteAnnotationStore(path: badPath)) { error in
            guard let annotationError = error as? AnnotationError else {
                XCTFail("Expected AnnotationError, got \(error)")
                return
            }
            if case .storageFailed = annotationError { /* expected */ } else {
                XCTFail("Expected storageFailed, got \(annotationError)")
            }
        }
    }

    // MARK: - Timestamp Validation

    func testNegativeTimestampThrows() async {
        do {
            _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: -1, text: "Valid", createdAt: 100))
            XCTFail("Expected validation error")
        } catch let error as AnnotationError {
            if case .validationFailed = error { /* expected */ } else { XCTFail("Unexpected: \(error)") }
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testNaNTimestampThrows() async {
        do {
            _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: .nan, text: "Valid", createdAt: 100))
            XCTFail("Expected validation error")
        } catch let error as AnnotationError {
            if case .validationFailed = error { /* expected */ } else { XCTFail("Unexpected: \(error)") }
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testInfinityTimestampThrows() async {
        do {
            _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: .infinity, text: "Valid", createdAt: 100))
            XCTFail("Expected validation error")
        } catch let error as AnnotationError {
            if case .validationFailed = error { /* expected */ } else { XCTFail("Unexpected: \(error)") }
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    // MARK: - Unicode / Emoji Round-Trip

    func testUnicodeEmojiRoundTrip() async throws {
        let emojiText = "💪 Row faster! 🚣 Excellent technique 中文测试"
        let saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: emojiText, createdAt: 100))
        XCTAssertEqual(saved.text, emojiText)

        store = try SQLiteAnnotationStore(path: dbPath)
        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].text, emojiText)
    }

    // MARK: - 1000-Character Boundary Through SQLite

    func testMaxLengthTextSucceedsThroughSQLite() async throws {
        let maxText = String(repeating: "a", count: 1000)
        let saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: maxText, createdAt: 100))
        XCTAssertEqual(saved.text.count, 1000)
    }

    func testTooLongTextThrowsThroughSQLite() async {
        let longText = String(repeating: "a", count: 1001)
        do {
            _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: longText, createdAt: 100))
            XCTFail("Expected validation error")
        } catch let error as AnnotationError {
            if case .validationFailed = error { /* expected */ } else { XCTFail("Unexpected: \(error)") }
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testMaxLengthTextWithWhitespaceTrimsBelow() async throws {
        let paddedText = " " + String(repeating: "b", count: 998) + " "
        let saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: paddedText, createdAt: 100))
        XCTAssertEqual(saved.text.count, 998)
    }

    // MARK: - Migration / Schema

    func testMigrationCreatesSchemaAndIndex() throws {
        let version = try querySingleInt("PRAGMA user_version;")
        XCTAssertEqual(version, 1)

        let tableNames = try queryStrings("SELECT name FROM sqlite_master WHERE type='table';", column: 0)
        XCTAssertTrue(tableNames.contains("annotations"))

        let indexNames = try queryStrings("PRAGMA index_list(annotations);", column: 1)
        XCTAssertTrue(indexNames.contains("idx_annotations_workout_timestamp"))
    }

    func testMigrationIsIdempotent() throws {
        // Re-open the same database — migration should not fail.
        store = try SQLiteAnnotationStore(path: dbPath)
        let version = try querySingleInt("PRAGMA user_version;")
        XCTAssertEqual(version, 1)
    }

    // MARK: - Insert Returns Generated ID

    func testInsertReturnsGeneratedId() async throws {
        let a1 = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 10, text: "First", createdAt: 100))
        XCTAssertGreaterThan(a1.id, 0)

        let a2 = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 20, text: "Second", createdAt: 200))
        XCTAssertGreaterThan(a2.id, a1.id)
    }

    // MARK: - Persistence After Close / Reopen

    func testPersistenceAfterCloseAndReopen() async throws {
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "Persisted", createdAt: 1_000))

        // Close and reopen.
        store = try SQLiteAnnotationStore(path: dbPath)

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].text, "Persisted")
        XCTAssertEqual(loaded[0].timestamp, 30, accuracy: 0.001)
    }

    // MARK: - Trimming

    func testTextIsTrimmedBeforeSave() async throws {
        let saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "  trimmed  ", createdAt: 100))
        XCTAssertEqual(saved.text, "trimmed")

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded[0].text, "trimmed")
    }

    // MARK: - Validation

    func testEmptyTextAfterTrimThrows() async {
        do {
            _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "   ", createdAt: 100))
            XCTFail("Expected validation error")
        } catch let error as AnnotationError {
            if case .validationFailed = error {
                // expected
            } else {
                XCTFail("Unexpected AnnotationError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Deterministic Ordering

    func testLoadSortsByTimestampThenId() async throws {
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 60, text: "Later", createdAt: 200))
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "Earlier", createdAt: 100))
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "AlsoEarly", createdAt: 150))

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].text, "Earlier")
        XCTAssertEqual(loaded[1].text, "AlsoEarly")
        XCTAssertEqual(loaded[2].text, "Later")
    }

    // MARK: - Update Preserves createdAt

    func testUpdatePreservesOriginalCreatedAt() async throws {
        var saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "Original", createdAt: 1_000))
        saved.text = "Updated"
        saved.createdAt = 9_999

        let updated = try await store.saveAnnotation(workoutId: 1, saved)
        XCTAssertEqual(updated.createdAt, 1_000)
        XCTAssertEqual(updated.text, "Updated")
    }

    // MARK: - Cross-Workout Update Rejection

    func testUpdateRejectsCrossWorkoutId() async throws {
        let saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "Workout 1", createdAt: 100))

        let crossWorkout = Annotation(id: saved.id, timestamp: 30, text: "Cross", createdAt: 100)
        do {
            _ = try await store.saveAnnotation(workoutId: 2, crossWorkout)
            XCTFail("Expected notFound error")
        } catch let error as AnnotationError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Delete

    func testDeleteAnnotation() async throws {
        let saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "Delete me", createdAt: 100))
        try await store.deleteAnnotation(workoutId: 1, id: saved.id)

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testDeleteNonexistentIdIsNoop() async throws {
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "Keep", createdAt: 100))
        try await store.deleteAnnotation(workoutId: 1, id: 999)

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded.count, 1)
    }

    // MARK: - Delete All With Sequence Reset

    func testDeleteAllResetsAutoincrementSequence() async throws {
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "A", createdAt: 100))
        _ = try await store.saveAnnotation(workoutId: 2, Annotation(id: 0, timestamp: 60, text: "B", createdAt: 200))

        try await store.deleteAll()

        let w1 = try await store.loadAnnotations(workoutId: 1)
        let w2 = try await store.loadAnnotations(workoutId: 2)
        XCTAssertTrue(w1.isEmpty)
        XCTAssertTrue(w2.isEmpty)

        // New insert should get ID 1 again after sequence reset.
        let newAnnotation = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 90, text: "After reset", createdAt: 300))
        XCTAssertEqual(newAnnotation.id, 1)
    }

    // MARK: - Apostrophes / SQL-Like Text

    func testApostropheAndSqlLikeTextRoundTrips() async throws {
        let sqlText = "It's a \"test\" with 'quotes' and; semicolons -- and /* comments */"
        let saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: sqlText, createdAt: 100))
        XCTAssertEqual(saved.text, sqlText)

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded[0].text, sqlText)
    }

    // MARK: - Concurrent Writes

    func testConcurrentWritesDoNotLoseRows() async throws {
        let count = 50
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<count {
                group.addTask {
                    _ = try await self.store.saveAnnotation(
                        workoutId: 1,
                        Annotation(id: 0, timestamp: Double(i), text: "Concurrent \(i)", createdAt: Int64(i * 1000))
                    )
                }
            }
            try await group.waitForAll()
        }

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded.count, count, "Expected all \(count) annotations to be persisted")

        // All IDs should be unique.
        let ids = Set(loaded.map(\.id))
        XCTAssertEqual(ids.count, count, "Expected unique IDs")
    }

    // MARK: - Workout Isolation

    func testWorkoutIsolation() async throws {
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 10, text: "W1", createdAt: 100))
        _ = try await store.saveAnnotation(workoutId: 2, Annotation(id: 0, timestamp: 20, text: "W2", createdAt: 200))

        let w1 = try await store.loadAnnotations(workoutId: 1)
        let w2 = try await store.loadAnnotations(workoutId: 2)

        XCTAssertEqual(w1.count, 1)
        XCTAssertEqual(w2.count, 1)
        XCTAssertEqual(w1[0].text, "W1")
        XCTAssertEqual(w2[0].text, "W2")
    }

    // MARK: - Private Helpers

    private func querySingleInt(_ sql: String) throws -> Int {
        var db: OpaquePointer?
        defer { sqlite3_close_v2(db) }
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw NSError(domain: "test", code: 1)
        }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "test", code: 2)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw NSError(domain: "test", code: 3)
        }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func queryStrings(_ sql: String, column: Int32) throws -> [String] {
        var db: OpaquePointer?
        defer { sqlite3_close_v2(db) }
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw NSError(domain: "test", code: 1)
        }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "test", code: 2)
        }
        var values: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(stmt, column) else { continue }
            values.append(String(cString: cString))
        }
        return values
    }
}
