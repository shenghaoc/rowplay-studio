# RowPlayFormatting Stress Tests — Requirements

## Purpose

Add stress and boundary coverage for `RowPlayFormatting` helpers to improve confidence before larger storage or network work.

## Scope

- This PR adds stress/boundary coverage for formatting helpers.
- This PR may fix formatter bugs discovered by tests.
- This PR must not add product features.
- This PR must not change UI behavior except through formatter correctness.

## Coverage Targets

### `RowPlayFormatting.time(_:tenths:)`

| Input | Expected |
| --- | --- |
| 0 seconds | `"0:00"` |
| 1 second | `"0:01"` |
| 59 seconds | `"0:59"` |
| 60 seconds | `"1:00"` |
| 61 seconds | `"1:01"` |
| 3599 seconds | `"59:59"` |
| 3600 seconds | `"1:00:00"` |
| 3661 seconds | `"1:01:01"` |
| negative seconds | `"--:--"` |
| `Double.infinity` | `"--:--"` |
| `Double.nan` | `"--:--"` |
| tenths enabled (normal) | `"M:SS.t"` |

### `RowPlayFormatting.pace(_:)`

| Input | Expected |
| --- | --- |
| valid normal pace | `"M:SS.t/500m"` |
| zero pace | `"--:--"` |
| negative pace | `"--:--"` |
| `Double.infinity` | `"--:--"` |
| `Double.nan` | `"--:--"` |

### `RowPlayFormatting.distance(_:unit:)`

| Input | Expected |
| --- | --- |
| 0 metres | `"0 m"` / `"0 ft"` |
| 1 metre | `"1 m"` / `"3 ft"` |
| 999 metres | `"999 m"` |
| 1000 metres | `"1.00 km"` |
| 1234 metres | `"1.23 km"` |
| very large distance | `"X.XX km"` |
| negative distance | negative km/mi prefix |
| `Double.infinity` | `"--"` |
| `Double.nan` | `"--"` |
| imperial: 1609.344m | `"1.00 mi"` |
| metric vs imperial differ | confirmed |

### `RowPlayFormatting.paceToWatts(_:)`

| Input | Expected |
| --- | --- |
| normal RowErg pace | ≈202.55 W |
| very slow pace | >0, smaller than normal |
| very fast positive pace | >normal watts |
| zero pace | 0 |
| negative pace | 0 |
| `Double.infinity` | 0 |
| `Double.nan` | 0 |

### `RowPlayFormatting.paceToWatts(for:pacePer500m:)`

| Input | Expected |
| --- | --- |
| rower == base watts | equal |
| skierg == base watts | equal |
| bike == base / 8.0 | equal |
| invalid pace → 0 | 0 for all sports |

### `RowPlayFormatting.challengeDistance(for:)`

| Input | Expected |
| --- | --- |
| rower distance | unchanged |
| skierg distance | unchanged |
| bike distance | halved |
