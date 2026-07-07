# Manual Concept2 Sync Wiring

## Purpose

Document and verify the manual BYOT (bring-your-own-token) sync wiring that connects the Concept2 sync coordinator, token store, and workout cache into the native macOS app through user-triggered actions.

## Requirements

1. **Token entry**: Settings exposes a `SecureField` for pasting a Concept2 BYOT token.
2. **Token persistence**: Saved tokens persist through the `TokenStore` protocol; production uses `KeychainTokenStore`. Tokens are never written to UserDefaults, plain files, logs, SQLite, or test assertions.
3. **Token clearing**: The visible token text field clears after a successful save.
4. **Token deletion**: Disconnect removes the token from Keychain and clears cached data.
5. **Manual sync trigger**: A "Sync Now" button and `Workout > Sync Concept2 Logbook` menu command trigger sync.
6. **Sync guard**: Sync Now is disabled if no token is saved or if a sync is already in progress.
7. **Sync orchestration**: Sync creates `URLSessionConcept2Client` from the saved token, uses `SQLiteWorkoutCache`, and runs `WorkoutSyncCoordinator.syncAll()`.
8. **Result display**: Sync result (saved count, failure count) is shown in the UI status message.
9. **Cache-backed loading**: After successful sync, `WorkoutLibrary.replaceWithSyncedDetails` loads cached workouts and disables demo mode.
10. **Demo mode interaction**: Demo mode ON shows demo workouts; demo mode OFF with no synced workouts shows empty state.
11. **Privacy**: Error messages shown to users are short and non-sensitive. Tokens, Authorization headers, raw payloads, and cookie values are never exposed.
12. **Disconnect cleanup**: Disconnect deletes the token, clears the SQLite cache, and clears the in-memory library.

## Non-Goals (this PR)

- No background sync scheduling.
- No OAuth flow.
- No Bluetooth or hardware work.
- No real network calls in tests.
- No app redesign.
- No token storage outside Keychain.

## Privacy Invariant

User-facing error messages must not contain:
- BYOT tokens.
- Authorization header values.
- Full raw workout payloads.
- Cookie values.

`redact()` and `PrivacySafeLogger` provide defense-in-depth.
