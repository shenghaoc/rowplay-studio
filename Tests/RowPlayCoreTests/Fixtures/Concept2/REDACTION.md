# Golden fixture redaction policy

Fixtures under this directory capture **redacted** Concept2 Logbook API response
bodies used by `concept2.golden.test.ts`. They must never contain real athlete
data, credentials, or device identifiers.

## Removed or absent fields

| Field | Policy |
|-------|--------|
| Result / user `id` | Replace with deterministic stand-ins (`9001`, `9002`, …) |
| `first_name`, `last_name`, `username`, `email`, names in `comments` | Omit or `"REDACTED"` |
| `serial_number`, `device` (in `metadata`) | Omit entirely — not replaced with placeholders |
| Tokens, cookies, Authorization headers | Never included — fixtures are response bodies only |

## Realistic performance values

Use plausible workout numbers (e.g. 2000 m RowErg at 7:30 → `time = 4500`
tenths). Avoid trivial or absurd values that would make assertions meaningless.

## Adding a new fixture

1. Capture or construct a raw API-shaped `rawResult` and optional `rawStrokes`.
2. Apply the table above.
3. Compute `expected.*` **by hand** from the documented wire units (tenths,
   decimetres, BikeErg per-1000m pace) — do not copy values from running
   `mapResult` / `mapStrokes` / `mapSplits`.
4. Name the file `<case>.fixture.json` and add a matching `describe` block in
   `src/lib/server/concept2.golden.test.ts`.
5. Run `pnpm run test`.

## Provenance

Once the full-fidelity payload shape stabilises (see PR #61), add an optional
`"fixtureVersion": 1` key to each fixture to track schema bumps. Not required
for the initial four cases.
