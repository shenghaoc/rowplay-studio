# TCX Export Requirements

## R1: TCX File Generation

The native app must export a single workout as a Garmin Training Center Database v2 (TCX) XML file.

- **R1.1** `WorkoutExport.tcx(_ detail: WorkoutDetail) -> String` produces a deterministic UTF-8 TCX XML string.
- **R1.2** The XML uses the `http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2` namespace as the default namespace.
- **R1.3** The XML includes the `http://www.w3.org/2001/XMLSchema-instance` namespace prefix `xsi`.
- **R1.4** The root `TrainingCenterDatabase` element includes `xsi:schemaLocation` pointing to `http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd`.
- **R1.5** The output is deterministic: identical input produces byte-identical output.

## R2: Activity Structure

- **R2.1** A single `Activities/Activity` element is emitted per workout.
- **R2.2** The `Sport` attribute is `"Biking"` for BikeErg and `"Other"` for RowErg/SkiErg.
- **R2.3** The `Id` element contains the workout UTC date in ISO-8601 format (`YYYY-MM-DDTHH:MM:SSZ`).
- **R2.4** No `Notes`, `Training`, `Creator`, or `Extensions` elements are emitted.

## R3: Lap Summary

- **R3.1** A single `Lap` element is emitted with `StartTime` matching the activity `Id`.
- **R3.2** `TotalTimeSeconds` contains the workout summary duration without truncating fractional seconds.
- **R3.3** `DistanceMeters` contains the workout summary distance.
- **R3.4** `Calories` contains `caloriesTotal` clamped to the TCX `xsd:unsignedShort` range `0...65535`, or `0` when absent.
- **R3.5** `AverageHeartRateBpm` is emitted only when `heartRateAvg` is in the valid TCX range `1...255`.
- **R3.6** `Intensity` is `"Active"`.
- **R3.7** `TriggerMethod` is `"Manual"`.

## R4: Trackpoint Generation

- **R4.1** `Trackpoint` elements are generated from valid strokes, ordered by stroke time.
- **R4.2** Each trackpoint contains `Time` (absolute UTC ISO-8601 with fractional seconds) and `DistanceMeters` (absolute cumulative distance).
- **R4.3** `HeartRateBpm` is included only when the stroke's heart rate is in the range 1...255.
- **R4.4** `Cadence` is included when the stroke's cadence is valid (finite, non-negative), rounded and clamped to the TCX `CadenceValue_t` range `0...254` before integer conversion.
- **R4.5** Non-finite or negative stroke timestamps and distances are rejected/skipped.
- **R4.6** Trackpoint distance is clamped to the workout summary distance.
- **R4.7** Samples beyond the valid workout duration are skipped.
- **R4.8** Identical raw trackpoint timestamp offsets are deduplicated deterministically (first occurrence wins); distinct sub-second offsets remain distinct.
- **R4.9** No GPS `Position` or `AltitudeMeters` elements are emitted (indoor ergometer workouts).

## R5: Privacy and Metadata Exclusions

- **R5.1** No comments, source strings, device identifiers, serial numbers, or hardware metadata are included.
- **R5.2** No `Creator` or `Author` blocks are emitted.
- **R5.3** No proprietary extensions or watts data are included.

## R6: Formatting

- **R6.1** Decimal values use locale-independent formatting (dot decimal separator).
- **R6.2** No user-entered text is emitted; XML content is limited to fixed schema strings and validated numeric values.
- **R6.3** All export generation lives in `RowPlayCore` with no SwiftUI/AppKit imports.

## R7: Native UI Integration

- **R7.1** An "Export TCX" button is added to `WorkoutFileActionsView`.
- **R7.2** The file is saved as `rowplay-workout-<id>.tcx` using an XML-conforming dynamic `UTType` tagged with the `tcx` filename extension.
- **R7.3** Existing CSV, JSON, and share-package behavior is preserved.

## R8: Test Coverage

- **R8.1** Well-formed XML is validated with `XMLParser`, not substring checks alone.
- **R8.2** Namespace and schema attributes are verified.
- **R8.3** Required hierarchy (`TrainingCenterDatabase/Activities/Activity/Lap/Track/Trackpoint`) is verified.
- **R8.4** Exact UTC Activity ID and Lap StartTime are verified.
- **R8.5** Sport mapping: RowErg/SkiErg → Other, BikeErg → Biking.
- **R8.6** Summary duration, distance, calories, and average HR are verified.
- **R8.7** Ordered trackpoints with absolute timestamps, distance, HR, and cadence are verified.
- **R8.8** Missing HR/calories handling is verified.
- **R8.9** No-stroke workout produces valid summary with no Track.
- **R8.10** Invalid/non-finite samples never produce NaN or Infinity in XML.
- **R8.11** Duplicate timestamp handling is verified.
- **R8.12** Deterministic output is verified.
- **R8.13** Absence of comments, source, hardware metadata, Creator, and Author is verified.

## R9: Non-Goals

- No TCX import.
- No FIT/GPX parsing.
- No HR file parsing.
- No Bluetooth.
- No 3D rendering.
- No OAuth.
- No public sharing.
- No GPS coordinates.
- No proprietary TCX extensions.
- No external dependencies.
- No unrelated refactors.
