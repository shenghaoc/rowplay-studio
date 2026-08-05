#!/usr/bin/env bash
# Profile a staged-app acceptance scenario with xctrace when available.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RowPlayStudio"
DURATION=60
SCENARIO_ID=""
OUTPUT_DIR=""

usage() {
  cat >&2 <<'EOF'
usage:
  ./script/profile_replay.sh --scenario <ID> --duration <seconds> --output <DIR>
EOF
}

while (($#)); do
  case "$1" in
    --scenario)
      shift
      SCENARIO_ID="${1:-}"
      ;;
    --duration)
      shift
      DURATION="${1:-}"
      ;;
    --output)
      shift
      OUTPUT_DIR="${1:-}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

if [[ -z "$SCENARIO_ID" || -z "$OUTPUT_DIR" ]]; then
  usage
  exit 2
fi

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 5 ]]; then
  echo "duration must be an integer >= 5" >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"
SUMMARY_PATH="$OUTPUT_DIR/profile-summary.json"
MEMORY_PATH="$OUTPUT_DIR/memory-samples.csv"
TRACE_DIR="$OUTPUT_DIR/traces"
mkdir -p "$TRACE_DIR"

SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
MACHINE_MODEL="$(sysctl -n hw.model 2>/dev/null || echo unknown)"

echo "Profiling scenario=$SCENARIO_ID duration=${DURATION}s"
echo "source_commit=$SOURCE_COMMIT"

"$ROOT_DIR/script/launch_replay_acceptance.sh" \
  --scenario "$SCENARIO_ID" \
  --output "$OUTPUT_DIR"

PID="$(pgrep -x "$APP_NAME" | head -n 1 || true)"
if [[ -z "$PID" ]]; then
  echo "no $APP_NAME process to profile" >&2
  exit 1
fi

TEMPLATES="$(xcrun xctrace list templates 2>/dev/null || true)"
TIME_PROFILER_AVAILABLE=0
GPU_TEMPLATE=""
if printf '%s\n' "$TEMPLATES" | grep -Fq 'Time Profiler'; then
  TIME_PROFILER_AVAILABLE=1
fi
if printf '%s\n' "$TEMPLATES" | grep -Fq 'Metal System Trace'; then
  GPU_TEMPLATE="Metal System Trace"
elif printf '%s\n' "$TEMPLATES" | grep -Fq 'Core Animation'; then
  GPU_TEMPLATE="Core Animation"
fi

TRACE_STATUS="not-started"
GPU_TRACE_STATUS="unavailable"

# Resident memory sampling runs concurrently with xctrace.
echo "timestamp_unix,rss_bytes" >"$MEMORY_PATH"
(
  SAMPLE_INTERVAL=5
  ELAPSED=0
  while [[ "$ELAPSED" -lt "$DURATION" ]]; do
    if ! kill -0 "$PID" 2>/dev/null; then
      break
    fi
    RSS="$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ' || true)"
    if [[ -n "$RSS" ]]; then
      # ps rss is in kilobytes on macOS.
      RSS_BYTES=$((RSS * 1024))
      echo "$(date +%s),$RSS_BYTES" >>"$MEMORY_PATH"
    fi
    sleep "$SAMPLE_INTERVAL"
    ELAPSED=$((ELAPSED + SAMPLE_INTERVAL))
  done
) &
MEMORY_PID=$!

if [[ "$TIME_PROFILER_AVAILABLE" -eq 1 ]]; then
  TRACE_PATH="$TRACE_DIR/time-profiler.trace"
  # Leave .trace bundles outside the repository; this output dir is caller-supplied.
  if xcrun xctrace record \
    --template 'Time Profiler' \
    --attach "$PID" \
    --time-limit "${DURATION}s" \
    --output "$TRACE_PATH" >/dev/null 2>"$OUTPUT_DIR/xctrace-time-profiler.log"; then
    TRACE_STATUS="recorded"
  else
    TRACE_STATUS="failed"
  fi
else
  TRACE_STATUS="template-unavailable"
  sleep "$DURATION"
fi

wait "$MEMORY_PID" 2>/dev/null || true

# GPU/Metal templates are listed for availability reporting. A second full-duration
# attach would double scenario cost; record template presence honestly rather than
# fabricating GPU counter evidence from an unrun template.
if [[ -n "$GPU_TEMPLATE" ]]; then
  GPU_TRACE_STATUS="template-listed-not-attached:$GPU_TEMPLATE"
else
  GPU_TRACE_STATUS="template-unavailable"
fi

python3 - <<'PY' "$SUMMARY_PATH" "$SCENARIO_ID" "$SOURCE_COMMIT" "$DURATION" "$TRACE_STATUS" "$GPU_TRACE_STATUS" "$MACOS_VERSION" "$MACHINE_MODEL" "$MEMORY_PATH" "$OUTPUT_DIR"
import csv, json, sys, pathlib
summary_path, scenario, commit, duration, trace_status, gpu_status, macos, machine, memory_path, output_dir = sys.argv[1:]
rss_values = []
with open(memory_path, newline="") as handle:
    reader = csv.DictReader(handle)
    for row in reader:
        try:
            rss_values.append(int(row["rss_bytes"]))
        except Exception:
            pass

def stats(values):
    if not values:
        return {"count": 0}
    values = sorted(values)
    return {
        "count": len(values),
        "minBytes": values[0],
        "maxBytes": values[-1],
        "p50Bytes": values[len(values)//2],
        "lastBytes": values[-1],
    }

metrics_path = pathlib.Path(output_dir) / "acceptance-metrics.json"
acceptance_metrics = None
if metrics_path.exists():
    try:
        acceptance_metrics = json.loads(metrics_path.read_text())
        # Strip accidental absolute paths if present.
        for key in list(acceptance_metrics):
            if "path" in key.lower() or "dir" in key.lower():
                del acceptance_metrics[key]
    except Exception:
        acceptance_metrics = {"status": "unreadable"}

payload = {
    "scenario": scenario,
    "sourceCommit": commit,
    "durationSeconds": int(duration),
    "macosVersion": macos,
    "machineModel": machine,
    "timeProfilerStatus": trace_status,
    "gpuTraceStatus": gpu_status,
    "memory": stats(rss_values),
    "acceptanceMetrics": acceptance_metrics,
    "notes": [
        "Trace bundles stay outside the repository.",
        "No workout IDs, tokens, account data, or absolute private paths are included.",
        "GPU counters are reported only when xctrace lists a usable template.",
    ],
}
pathlib.Path(summary_path).write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
print(f"wrote profile summary for scenario={scenario}")
PY

# Stop the profiled process so subsequent scenarios start cleanly.
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
echo "profile complete scenario=$SCENARIO_ID"
