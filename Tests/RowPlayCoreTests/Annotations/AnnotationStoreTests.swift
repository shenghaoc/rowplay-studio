import XCTest
@testable import RowPlayCore

final class AnnotationStoreTests: XCTestCase {

    private var store: InMemoryAnnotationStore!

    override func setUp() {
        store = InMemoryAnnotationStore()
    }

    // MARK: - Save and Load

    func testSaveAndLoad() async throws {
        let annotation = Annotation(id: 0, timestamp: 30, text: "Good catch position", createdAt: 1_000_000)
        let saved = try await store.saveAnnotation(workoutId: 1, annotation)
        XCTAssertGreaterThan(saved.id, 0)
        XCTAssertEqual(saved.text, "Good catch position")

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, saved.id)
    }

    func testSaveMultipleAnnotations() async throws {
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "First", createdAt: 1_000_000))
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 60, text: "Second", createdAt: 1_000_001))

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded.count, 2)
    }

    func testLoadSortedByTimestamp() async throws {
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 60, text: "Later", createdAt: 1_000_001))
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "Earlier", createdAt: 1_000_000))

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded[0].text, "Earlier")
        XCTAssertEqual(loaded[1].text, "Later")
    }

    func testLoadEmptyWorkout() async throws {
        let loaded = try await store.loadAnnotations(workoutId: 999)
        XCTAssertTrue(loaded.isEmpty)
    }

    // MARK: - Update

    func testUpdateAnnotation() async throws {
        var saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "Original", createdAt: 1_000_000))
        saved.text = "Updated"
        let updated = try await store.saveAnnotation(workoutId: 1, saved)
        XCTAssertEqual(updated.text, "Updated")

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].text, "Updated")
    }

    func testUpdatePreservesCreatedAt() async throws {
        var saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "Original", createdAt: 1_000_000))
        saved.text = "Updated"
        saved.createdAt = 2_000_000

        let updated = try await store.saveAnnotation(workoutId: 1, saved)

        XCTAssertEqual(updated.createdAt, 1_000_000)
    }

    func testUpdateMissingAnnotationThrows() async {
        let annotation = Annotation(id: 99, timestamp: 30, text: "Missing", createdAt: 1_000_000)
        do {
            _ = try await store.saveAnnotation(workoutId: 1, annotation)
            XCTFail("Expected missing annotation error")
        } catch let error as AnnotationError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Delete

    func testDeleteAnnotation() async throws {
        let saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "Delete me", createdAt: 1_000_000))
        try await store.deleteAnnotation(workoutId: 1, id: saved.id)

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testDeleteNonexistentIdIsNoop() async throws {
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "Keep", createdAt: 1_000_000))
        try await store.deleteAnnotation(workoutId: 1, id: 999)

        let loaded = try await store.loadAnnotations(workoutId: 1)
        XCTAssertEqual(loaded.count, 1)
    }

    func testDeleteAllClearsAnnotationsAndResetsIds() async throws {
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "First", createdAt: 1_000_000))
        _ = try await store.saveAnnotation(workoutId: 2, Annotation(id: 0, timestamp: 60, text: "Second", createdAt: 1_000_001))

        try await store.deleteAll()

        let firstWorkout = try await store.loadAnnotations(workoutId: 1)
        let secondWorkout = try await store.loadAnnotations(workoutId: 2)
        let saved = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 90, text: "After reset", createdAt: 1_000_002))
        XCTAssertTrue(firstWorkout.isEmpty)
        XCTAssertTrue(secondWorkout.isEmpty)
        XCTAssertEqual(saved.id, 1)
    }

    // MARK: - Validation

    func testSaveEmptyTextThrows() async {
        let annotation = Annotation(id: 0, timestamp: 30, text: "", createdAt: 1_000_000)
        do {
            _ = try await store.saveAnnotation(workoutId: 1, annotation)
            XCTFail("Expected validation error")
        } catch let error as AnnotationError {
            if case .validationFailed = error {
                // expected
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSaveWhitespaceOnlyTextThrows() async {
        let annotation = Annotation(id: 0, timestamp: 30, text: "   ", createdAt: 1_000_000)
        do {
            _ = try await store.saveAnnotation(workoutId: 1, annotation)
            XCTFail("Expected validation error")
        } catch is AnnotationError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSaveTrimsText() async throws {
        let annotation = Annotation(id: 0, timestamp: 30, text: "  Good catch  ", createdAt: 1_000_000)
        let saved = try await store.saveAnnotation(workoutId: 1, annotation)
        XCTAssertEqual(saved.text, "Good catch")
    }

    func testSaveTooLongTextThrows() async {
        let longText = String(repeating: "x", count: 1001)
        let annotation = Annotation(id: 0, timestamp: 30, text: longText, createdAt: 1_000_000)
        do {
            _ = try await store.saveAnnotation(workoutId: 1, annotation)
            XCTFail("Expected validation error")
        } catch is AnnotationError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSaveMaxLengthTextSucceeds() async throws {
        let maxText = String(repeating: "x", count: 1000)
        let annotation = Annotation(id: 0, timestamp: 30, text: maxText, createdAt: 1_000_000)
        let saved = try await store.saveAnnotation(workoutId: 1, annotation)
        XCTAssertEqual(saved.text.count, 1000)
    }

    // MARK: - Isolation Between Workouts

    func testWorkoutsAreIsolated() async throws {
        _ = try await store.saveAnnotation(workoutId: 1, Annotation(id: 0, timestamp: 30, text: "W1", createdAt: 1_000_000))
        _ = try await store.saveAnnotation(workoutId: 2, Annotation(id: 0, timestamp: 60, text: "W2", createdAt: 1_000_001))

        let w1 = try await store.loadAnnotations(workoutId: 1)
        let w2 = try await store.loadAnnotations(workoutId: 2)
        XCTAssertEqual(w1.count, 1)
        XCTAssertEqual(w2.count, 1)
        XCTAssertEqual(w1[0].text, "W1")
        XCTAssertEqual(w2[0].text, "W2")
    }
}
