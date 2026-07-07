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

Dependencies are injected via closures:
- `tokenStore: TokenStore` — defaults to `KeychainTokenStore`
- `cacheFactory: () throws -> WorkoutCache` — defaults to `SQLiteWorkoutCache` under Application Support
- `clientFactory: (String) -> Concept2APIClient` — defaults to `URLSessionConcept2Client`

### SettingsView — Concept2 Section

- Connection status indicator (checkmark or person icon).
- `SecureField` for token entry (local `@State`).
- Save Token button — trims, validates non-empty and length <= 4096, saves via controller, clears field.
- Sync Now button — disabled when `canSync` is false.
- Disconnect button — destructive, disabled when not connected or syncing.
- Progress indicator during sync.
- Status message after sync completes or fails.

### RowPlayStudioApp

- `@StateObject` for `Concept2SyncController`.
- `.environmentObject(syncController)` injected into `ContentView` and `Settings`.
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

## Error Handling

- No token → statusMessage: "Add a Concept2 token before syncing."
- Token save failure → statusMessage: "Could not save Concept2 token."
- Sync failure → statusMessage: "Concept2 sync failed." (generic, no details)
- `SyncStateTracker.syncFailed` stores redacted error in `syncState.lastError` (with a fallback if tracker is nil).
- `WorkoutSyncError.description` applies `redact()` to associated strings.

## Web Reference

From `src/routes/auth/token/+page.svelte` and `src/routes/api/sync/+server.ts`:

- Web uses a form to accept BYOT tokens and stores them in encrypted KV.
- Web sync is server-side via `syncWorkouts()` in `+server.ts`.
- Native replaces KV with Keychain, server sync with client-side `WorkoutSyncCoordinator`, and cookie sessions with direct token injection.

## Test Strategy

- `FakeTokenStore` — in-memory token store for all tests.
- `InMemoryWorkoutCache` — in-memory cache for success-path tests.
- `MockConcept2Client` — deterministic fixture data.
- Factory closures allow injecting all three without real network or Keychain calls.
- Tests verify: token save/clear/disconnect, sync guard, coordinator invocation, library replacement, demo mode toggle, error privacy.
