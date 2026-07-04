# Phase 4 Design: Concept2 Sync, Privacy, and Local Storage Foundation

## Goal

Establish the safe boundaries for Concept2 integration in the native app: a Keychain-backed token store, an injectable API client protocol, an async workout cache abstraction, privacy-safe logging, and sync state tracking. Real network sync is intentionally deferred — this PR creates the interfaces and testable implementations.

## Architecture

### 1. Token Store (`RowPlayCore/Sync/TokenStore.swift`)

Protocol-first design:

```swift
public protocol TokenStore: Sendable {
    func saveToken(_ token: String) throws
    func loadToken() throws -> String?
    func deleteToken() throws
}
```

- `KeychainTokenStore` uses Security framework directly (no third-party dependencies).
- Service name: `com.rowplay-studio.concept2-token`, account: `default`.
- Accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- `FakeTokenStore` holds the token in a `String?` property for tests.

### 2. Concept2 API Client (`RowPlayCore/Sync/Concept2Client.swift`)

Protocol for the Concept2 logbook API:

```swift
public protocol Concept2APIClient: Sendable {
    func fetchWorkouts(page: Int, perPage: Int) async throws -> Concept2Page
    func fetchWorkoutDetail(id: Int) async throws -> WorkoutDetail
}
```

- `Concept2Page` holds `workouts: [Workout]` and `totalPages: Int`.
- Token supply is decoupled: the real client (future PR) accepts a token provider closure.
- `MockConcept2Client` returns `DemoWorkoutLibrary` data, partitioned into pages.

### 3. Workout Cache (`RowPlayCore/Sync/WorkoutCache.swift`)

Protocol for local workout storage:

```swift
public protocol WorkoutCache: Sendable {
    func saveWorkouts(_ workouts: [Workout]) async throws
    func saveDetail(_ detail: WorkoutDetail) async throws
    func loadAllWorkouts() async throws -> [Workout]
    func loadWorkout(id: Int) async throws -> WorkoutDetail?
    func deleteAll() async throws
}
```

- `InMemoryWorkoutCache` uses `[Int: Workout]` and `[Int: WorkoutDetail]` dictionaries.
- Workouts are stored by `id` for O(1) lookup.
- Methods are async so future SQLite or file-backed implementations can perform I/O off the main actor without changing callers.
- `deleteAll()` is the disconnect/logout path.

### 4. Privacy-Safe Logger (`RowPlayCore/Support/PrivacySafeLogger.swift`)

Redaction layer over `os.Logger`:

- `redact(_:)` is a pure function applying regex patterns to strings.
- Patterns:
  - Hex tokens: `/\b[a-f0-9]{32,}\b/gi` → `[REDACTED]`
  - Bearer headers: `/Authorization:\s*Bearer\s+\S+/gi` → `[REDACTED]`
  - Cookie headers: `/(Cookie|Set-Cookie):\s*[^\n]+/gi` → `$1: [REDACTED]`
  - Token values: `/"(?:token|access_token)"\s*:\s*"[^"]+"/gi` → preserve key, replace value with `[REDACTED]`
  - Query/form credentials: `/\b(token|access_token)\s*=\s*[^\s&]+/gi` → `$1=[REDACTED]`
  - Large JSON blobs: objects or arrays over 100 characters → `[REDACTED]`
- `PrivacySafeLogger` wraps `os.Logger` and applies `redact()` to the main message and all string arguments.
- Interpolated error strings are redacted before emission to avoid logging tokens or authorization headers.

### 5. Sync State Tracker (`RowPlayCore/Sync/SyncStateTracker.swift`)

Observable sync progress:

```swift
public struct SyncState: Equatable, Sendable {
    public var lastSyncDate: Date?
    public var totalWorkouts: Int
    public var inProgress: Bool
    public var lastError: String?
    public var lastErrorDate: Date?
}
```

- `SyncStateTracker` is `@Observable` and `@MainActor` (macOS 14+).
- Reads workout count asynchronously from the cache protocol.
- Transitions: idle → syncing → complete/error.

## File Layout

```
Sources/RowPlayCore/
  Sync/
    TokenStore.swift              (new — protocol + KeychainTokenStore + FakeTokenStore)
    Concept2Client.swift          (new — protocol + Concept2Page + MockConcept2Client)
    WorkoutCache.swift            (new — protocol + InMemoryWorkoutCache)
    SyncStateTracker.swift        (new — SyncState + SyncStateTracker)
  Support/
    PrivacySafeLogger.swift       (new — redact() + PrivacySafeLogger)
Tests/RowPlayCoreTests/
  Sync/
    TokenStoreTests.swift         (new)
    Concept2ClientTests.swift     (new)
    WorkoutCacheTests.swift       (new)
    SyncStateTrackerTests.swift   (new)
  Support/
    PrivacySafeLoggerTests.swift  (new)
.kiro/specs/phase-04-sync-storage-foundation/
  requirements.md                 (new)
  design.md                       (new)
  tasks.md                        (new)
docs/
  source-map.md                   (modify — add Phase 4 mappings)
  roadmap.md                      (modify — Phase 4 status)
```

## Non-Goals

- No real URLSession-based Concept2 sync.
- No SQLite/Core Data implementation.
- No replay, export, share, live mode, or Bluetooth.
- No Cloudflare KV/D1 assumptions.
- No OAuth flow (BYOT only).
