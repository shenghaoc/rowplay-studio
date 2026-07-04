import Foundation

/// Protocol for local annotation storage.
///
/// Annotations are keyed by workout ID. The store is async to allow
/// future persistent backends (SQLite) without changing callers.
public protocol AnnotationStore: Sendable {
    /// Load all annotations for a workout, sorted by timestamp.
    func loadAnnotations(workoutId: Int) async throws -> [Annotation]
    /// Save (create or update) an annotation for a workout.
    /// When `annotation.id == 0`, a new annotation is created with an auto-assigned id.
    func saveAnnotation(workoutId: Int, _ annotation: Annotation) async throws -> Annotation
    /// Delete an annotation by id.
    func deleteAnnotation(workoutId: Int, id: Int) async throws
}

/// In-memory annotation store for tests, previews, and early integration.
///
/// Thread-safe via NSLock.
public final class InMemoryAnnotationStore: AnnotationStore, @unchecked Sendable {
    /// workoutId → annotations
    private var storage: [Int: [Annotation]] = [:]
    private var nextId: Int = 1
    private let lock = NSLock()

    public init() {}

    public func loadAnnotations(workoutId: Int) async throws -> [Annotation] {
        lock.withLock {
            (storage[workoutId] ?? []).sorted { $0.timestamp < $1.timestamp }
        }
    }

    public func saveAnnotation(workoutId: Int, _ annotation: Annotation) async throws -> Annotation {
        // Validate before saving
        if let error = annotation.validate() {
            throw AnnotationError.validationFailed(error)
        }

        return lock.withLock {
            var annotations = storage[workoutId] ?? []

            if annotation.id == 0 {
                // Create new
                var newAnnotation = annotation
                newAnnotation.id = nextId
                nextId += 1
                annotations.append(newAnnotation)
                storage[workoutId] = annotations
                return newAnnotation
            } else {
                // Update existing
                if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
                    annotations[index] = annotation
                    storage[workoutId] = annotations
                    return annotation
                } else {
                    // ID was specified but not found — treat as create
                    var newAnnotation = annotation
                    newAnnotation.id = nextId
                    nextId += 1
                    annotations.append(newAnnotation)
                    storage[workoutId] = annotations
                    return newAnnotation
                }
            }
        }
    }

    public func deleteAnnotation(workoutId: Int, id: Int) async throws {
        lock.withLock {
            var annotations = storage[workoutId] ?? []
            annotations.removeAll { $0.id == id }
            storage[workoutId] = annotations
        }
    }
}

/// Errors from annotation operations.
public enum AnnotationError: Error, Equatable {
    case validationFailed(String)
}
