# Manual Concept2 Sync Wiring — Design

## Architecture

```
SettingsView / Workout menu
    ↓
Concept2SyncController
    ↓
WorkoutSyncCoordinator
    ↓ (depends on protocols)
Concept2APIClient               WorkoutCache
    ↑                               ↑
URLSessionConcept2Client        SQLiteWorkoutCache
MockConcept2Client              InMemoryWorkoutCache
```

## Components

### Concept2SyncController

App-shell bridge (`@MainActor ObservableObject`) owning UI-facing state:

- `syncState: SyncState` — in-progress, last sync date, total workouts, last error
- `isConnected: Bool` — whether a token is saved
- `statusMessage: String?` — user-facing status text
- `canSync: Bool` — computed from cached `isConnected` and `syncState.inProgress`; `syncNow` re-validates the token as a safety net
- `loadCachedWorkouts(into:)` — launch-time cache hydration for an empty library when a saved token exists; does not contact the network

Dependencies are injected via closures:
- `tokenStore: TokenStore` — defaults to `KeychainTokenStore`
- `cacheFactory: () throws -> WorkoutCache` — defaults to `SQLiteWorkoutCache` under Application Support
- `clientFactory: (String) -> Concept2APIClient` — defaults to `URLSessionConcept2Client`

### SettingsView — Concept2 Section

- Connection status indicator (checkmark or person icon).
- `SecureField` for token entry (local `@State`).
- Save Token button — trims, validates non-empty and length <= 4096, saves via controller, clears field.
- Sync Now button — disabled when `canSync` is false.
- Disconnect button — destructive, disabled when not connected or syncing, and confirmed before deleting the token/cache.
- Progress indicator during sync.
- Status message after sync completes or fails.

### RowPlayStudioApp

- `@StateObject` for `Concept2SyncController`.
- `.environmentObject(syncController)` injected into `ContentView` and `Settings`.
- Window `.task` calls `syncController.loadCachedWorkouts(into:)` so synced data survives app relaunch without requiring another network sync.
- `Workout > Sync Concept2 Logbook` menu command with ⌘⇧S shortcut.

### WorkoutLibrary

- `replaceWithSyncedDetails(_:)` replaces the entire `details` array with synced data.
- Clears demo detail IDs.
- Sets demo mode off on the library and persists the state to UserDefaults so the sidebar reflects real data.
- `clearData()` empties the library for disconnect.

## Sync Flow

1. User taps Sync Now or uses menu command.
2. Controller loads token from `TokenStore`.
3. Controller creates/resolves `WorkoutCache` (lazy singleton).
4. Controller creates `WorkoutSyncCoordinator` with injected client and cache.
5. Coordinator calls `syncAll()` — pages summaries, fetches details, saves to cache.
6. Controller loads all cached details via `cache.listWorkouts()` + `cache.detail(id:)`.
7. Controller calls `library.replaceWithSyncedDetails(details)`.
8. Controller updates `SyncStateTracker` and sets `statusMessage`.

## Startup Cache Hydration

1. `RowPlayStudioApp` creates `WorkoutLibrary.demo()` from persisted demo preferences.
2. The main window task calls `Concept2SyncController.loadCachedWorkouts(into:)`.
3. The controller returns immediately when no token is saved, sync is already in progress, or the library already contains data (including active demo data).
4. Otherwise, it resolves `SQLiteWorkoutCache`, runs `migrate()`, loads all cached details, refreshes `SyncStateTracker`, and calls `WorkoutLibrary.replaceWithSyncedDetails`.
5. This makes previously synced workouts visible after relaunch without a Concept2 network request.

## Error Handling

- No token → statusMessage: "Add a Concept2 token before syncing."
- Token save failure → statusMessage: "Could not save Concept2 token."
- Sync failure → statusMessage: "Concept2 sync failed." (generic, no details)
- Cache hydration failure → statusMessage: "Could not load cached Concept2 workouts."
- Disconnect migrates the cache before `deleteAll()` so a fresh SQLite cache instance after relaunch can still purge persisted rows, and still attempts `deleteAll()` when migration fails after a cache instance was resolved.
- `SyncStateTracker.syncFailed` stores redacted error in `syncState.lastError` (with a fallback if tracker is nil).
- `WorkoutSyncError.description` applies `redact()` to associated strings.

## Web Architecture Context

Before rowplay PR #166, the web app accepted BYOT tokens and performed
server-side sync into persistent KV/D1 storage. That architecture has been
retired: the current web app seals a personal token in the httpOnly `rp_tok`
cookie and reads workout data live from Concept2; it has no web sync endpoint
or server-side workout cache.

The native `WorkoutSyncCoordinator`, Keychain token store, and SQLite cache are
therefore native-local capabilities, not ports of a current web backend.

## Test Strategy

- `FakeTokenStore` — in-memory token store for all tests.
- `InMemoryWorkoutCache` — in-memory cache for success-path tests.
- Temporary `SQLiteWorkoutCache` files — relaunch-path tests for startup hydration and disconnect cleanup.
- `MockConcept2Client` — deterministic fixture data.
- Factory closures allow injecting all three without real network or Keychain calls.
- Tests verify: token save/clear/disconnect, sync guard, coordinator invocation, library replacement, launch cache hydration, demo mode toggle, fresh-cache disconnect cleanup, error privacy.
