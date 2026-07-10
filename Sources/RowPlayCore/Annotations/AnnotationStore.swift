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
    /// Delete all annotations (disconnect/logout).
    func deleteAll() async throws
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
        var normalized = annotation
        normalized.text = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate before saving
        if let error = normalized.validate() {
            throw AnnotationError.validationFailed(error)
        }

        return try lock.withLock {
            var annotations = storage[workoutId] ?? []

            if normalized.id == 0 {
                // Create new
                var newAnnotation = normalized
                newAnnotation.id = nextId
                nextId += 1
                annotations.append(newAnnotation)
                storage[workoutId] = annotations
                return newAnnotation
            } else {
                // Update existing
                if let index = annotations.firstIndex(where: { $0.id == normalized.id }) {
                    var updated = normalized
                    updated.createdAt = annotations[index].createdAt
                    annotations[index] = updated
                    storage[workoutId] = annotations
                    return updated
                }
                throw AnnotationError.notFound
            }
        }
    }

    public func deleteAnnotation(workoutId: Int, id: Int) async throws {
        lock.withLock {
            guard var annotations = storage[workoutId] else { return }
            annotations.removeAll { $0.id == id }
            if annotations.isEmpty {
                storage.removeValue(forKey: workoutId)
            } else {
                storage[workoutId] = annotations
            }
        }
    }

    public func deleteAll() async throws {
        lock.withLock {
            storage.removeAll()
            nextId = 1
        }
    }
}

/// Errors from annotation operations.
///
/// Diagnostic messages must not include annotation text, tokens, complete
/// workout payloads, or SQL containing user content.
public enum AnnotationError: Error, Equatable {
    case validationFailed(String)
    case notFound
    /// The annotation database cannot be opened or is fundamentally unusable.
    case storageUnavailable
    /// A specific storage operation failed. The associated string is a
    /// privacy-safe diagnostic (no user content).
    case storageFailed(String)
}

/// Sentinel annotation store that throws ``AnnotationError/storageUnavailable``
/// for every operation.
///
/// Use this as the fallback when the real annotation database cannot be opened.
/// It does **not** silently fall back to in-memory storage.
public final class UnavailableAnnotationStore: AnnotationStore, @unchecked Sendable {
    public init() {}

    public func loadAnnotations(workoutId: Int) async throws -> [Annotation] {
        throw AnnotationError.storageUnavailable
    }

    public func saveAnnotation(workoutId: Int, _ annotation: Annotation) async throws -> Annotation {
        throw AnnotationError.storageUnavailable
    }

    public func deleteAnnotation(workoutId: Int, id: Int) async throws {
        throw AnnotationError.storageUnavailable
    }

    public func deleteAll() async throws {
        throw AnnotationError.storageUnavailable
    }
}
