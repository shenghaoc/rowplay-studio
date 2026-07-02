# Web To Native Source Map

This file records the first mapping from the existing rowplay web repository to the native app.

| Web Source | Native Target | Notes |
| --- | --- | --- |
| `src/lib/types.ts` | `Sources/RowPlayCore/Models` | Core Concept2 domain models are being ported as Swift value types. |
| `src/lib/format.ts` | `Sources/RowPlayCore/Support/RowPlayFormatting.swift` | Phase 0 ports time, pace, distance, challenge distance, and sport-specific watts. |
| `src/lib/analytics.ts` | `Sources/RowPlayCore/Analytics/WorkoutAnalytics.swift` | Phase 0 ports summaries, distance bands, and linear trend only. |
| `src/lib/mockData.ts` | `Sources/RowPlayCore/Fixtures/DemoWorkoutLibrary.swift` | Phase 0 ports deterministic demo workouts to keep the native app explorable without Concept2 credentials. |
| `src/routes/dashboard` and dashboard components | `Sources/RowPlayStudio/Views/DashboardView.swift` | Phase 0 creates a native dashboard shell; full parity is Phase 2. |
| `src/routes/replay/[id]` and `src/lib/replay` | Future Phase 3 | Not yet ported beyond exposing stroke data and split tables. |
| `src/lib/server/concept2.ts`, `session.ts`, `db.ts` | Future Phase 4 | Native sync should use URLSession, Keychain, and local SQLite rather than Cloudflare KV/D1. |

