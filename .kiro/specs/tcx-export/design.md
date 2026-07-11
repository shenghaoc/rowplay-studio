# TCX Export Design

## Architecture

The TCX exporter is a pure domain-logic addition to `RowPlayCore/Export/WorkoutExport.swift`. It follows the same stateless enum namespace pattern as the existing CSV and JSON exporters.

No new files are created in RowPlayCore. The UI button is added to the existing `WorkoutFileActionsView`.

## TCX Structure

The output follows the Garmin TrainingCenterDatabase v2 schema:

```
<TrainingCenterDatabase xmlns="..." xsi:schemaLocation="...">
  <Activities>
    <Activity Sport="Other|Biking">
      <Id>2023-11-14T22:13:20Z</Id>
      <Lap StartTime="2023-11-14T22:13:20Z">
        <TotalTimeSeconds>480</TotalTimeSeconds>
        <DistanceMeters>2000</DistanceMeters>
        <Calories>150</Calories>
        <AverageHeartRateBpm><Value>145</Value></AverageHeartRateBpm>
        <Intensity>Active</Intensity>
        <TriggerMethod>Manual</TriggerMethod>
        <Track>
          <Trackpoint>
            <Time>2023-11-14T22:13:21Z</Time>
            <DistanceMeters>5.2</DistanceMeters>
            <HeartRateBpm><Value>130</Value></HeartRateBpm>
            <Cadence>28</Cadence>
          </Trackpoint>
          ...
        </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>
```

## Sport Mapping

- `Sport.bike` → `Sport="Biking"`
- `Sport.rower`, `Sport.skierg` → `Sport="Other"`

This matches the TCX v2 `Sport_t` enumeration which only supports Running, Biking, and Other.

## Date Handling

All timestamps use UTC ISO-8601 format (`YYYY-MM-DDTHH:MM:SSZ`). The workout `date` field is already a UTC `Date` and is formatted using a cached `ISO8601DateFormatter`.

## Stroke Filtering and Validation

1. Skip strokes with non-finite or negative `t` (timestamp offset from workout start).
2. Skip strokes with non-finite or negative `d` (cumulative distance).
3. Compute absolute stroke time as `workout.date + stroke.t`.
4. Skip strokes whose absolute time exceeds workout end.
5. Clamp stroke distance to `workout.distance`.
6. Deduplicate by absolute timestamp (first occurrence wins).
7. Sort by absolute time.

## XML Construction

The TCX is built using string interpolation with XML entity escaping. All numeric values use locale-independent `String(format:)` with `"%.Nf"` patterns. A small `xmlEscape` helper handles `&`, `<`, `>`, `"`, `'` in any text content.

This avoids a dependency on `Foundation.XMLDocument` (which pulls in `libxml2` and behaves differently on Linux) and keeps the output deterministic.

## Heart Rate and Cadence

- HeartRateBpm: included only when `stroke.heartRate` is in `1...255`.
- Cadence: `stroke.cadence` is rounded to `Int`, clamped to `0...255`, and included when finite and non-negative.

## Calories

When `workout.caloriesTotal` is nil, `0` is emitted because `Calories` is required by the TCX `ActivityLap_t` structure in practice (Garmin Connect rejects files without it).

## No-Track Workouts

When a workout has no valid strokes, the `Track` element is omitted entirely. The lap summary is still emitted.

## UI Integration

A single `saveTCX()` method is added to `WorkoutFileActionsView`, following the same pattern as `saveCSV()` and `saveJSON()`. It uses `NSSavePanel` with `UTType(filenameExtension: "tcx") ?? .xml`.
