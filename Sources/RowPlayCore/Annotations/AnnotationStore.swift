import Foundation
import Synchronization

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
/// Thread-safe via ``Mutex``.
public final class InMemoryAnnotationStore: AnnotationStore {
    private struct State: Sendable {
        /// workoutId → annotations
        var storage: [Int: [Annotation]] = [:]
        var nextID = 1
    }

    private let state = Mutex(State())

    public init() {}

    public func loadAnnotations(workoutId: Int) async throws -> [Annotation] {
        state.withLock {
            ($0.storage[workoutId] ?? []).sorted { $0.timestamp < $1.timestamp }
        }
    }

    public func saveAnnotation(workoutId: Int, _ annotation: Annotation) async throws -> Annotation {
        let normalized = try annotation.normalizedForSave()

        return try state.withLock { state in
            var annotations = state.storage[workoutId] ?? []

            if normalized.id == 0 {
                // Create new
                var newAnnotation = normalized
                newAnnotation.id = state.nextID
                state.nextID += 1
                annotations.append(newAnnotation)
                state.storage[workoutId] = annotations
                return newAnnotation
            } else {
                // Update existing
                if let index = annotations.firstIndex(where: { $0.id == normalized.id }) {
                    var updated = normalized
                    updated.createdAt = annotations[index].createdAt
                    annotations[index] = updated
                    state.storage[workoutId] = annotations
                    return updated
                }
                throw AnnotationError.notFound
            }
        }
    }

    public func deleteAnnotation(workoutId: Int, id: Int) async throws {
        state.withLock { state in
            guard var annotations = state.storage[workoutId] else { return }
            annotations.removeAll { $0.id == id }
            if annotations.isEmpty {
                state.storage.removeValue(forKey: workoutId)
            } else {
                state.storage[workoutId] = annotations
            }
        }
    }

    public func deleteAll() async throws {
        state.withLock {
            $0.storage.removeAll()
            $0.nextID = 1
        }
    }
}

/// Errors from annotation operations.
///
/// Diagnostic messages must not include annotation text, tokens, complete
/// workout payloads, or SQL containing user content.
public enum AnnotationError: Error, Equatable, Sendable {
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
public final class UnavailableAnnotationStore: AnnotationStore, Sendable {
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
