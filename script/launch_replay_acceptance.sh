#!/usr/bin/env bash
# Launch a deterministic staged-app replay acceptance scenario.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO_CATALOG="$ROOT_DIR/script/replay_acceptance_scenarios.json"
APP_NAME="RowPlayStudio"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"

usage() {
  cat >&2 <<'EOF'
usage:
  ./script/launch_replay_acceptance.sh --list
  ./script/launch_replay_acceptance.sh --scenario <ID> [--output <DIR>] [--skip-build]
EOF
}

require_catalog() {
  if [[ ! -f "$SCENARIO_CATALOG" ]]; then
    echo "missing scenario catalog: $SCENARIO_CATALOG" >&2
    exit 1
  fi
  python3 -m json.tool "$SCENARIO_CATALOG" >/dev/null
}

list_scenarios() {
  require_catalog
  python3 - <<'PY' "$SCENARIO_CATALOG"
import json, sys
catalog = json.load(open(sys.argv[1]))
print(f"scenarios={len(catalog['scenarios'])}")
for scenario in catalog["scenarios"]:
    print(
        f"{scenario['id']}\t"
        f"{scenario['sport']}\t"
        f"{scenario['renderer']}\t"
        f"{scenario['quality']}\t"
        f"camera={scenario['camera']}\t"
        f"theme={scenario['theme']}\t"
        f"rival={scenario['rival']}\t"
        f"t={scenario['time']}\t"
        f"rm={int(scenario['reducedMotion'])}\t"
        f"{scenario['width']}x{scenario['height']}\t"
        f"phase={scenario['phase']}"
    )
PY
}

load_scenario() {
  local scenario_id="$1"
  python3 - <<'PY' "$SCENARIO_CATALOG" "$scenario_id"
import json, sys
catalog = json.load(open(sys.argv[1]))
wanted = sys.argv[2]
for scenario in catalog["scenarios"]:
    if scenario["id"] == wanted:
        print(json.dumps(scenario))
        raise SystemExit(0)
print(f"unknown scenario: {wanted}", file=sys.stderr)
raise SystemExit(1)
PY
}

SCENARIO_ID=""
OUTPUT_DIR=""
SKIP_BUILD=0

while (($#)); do
  case "$1" in
    --list)
      list_scenarios
      exit 0
      ;;
    --scenario)
      shift
      SCENARIO_ID="${1:-}"
      ;;
    --output)
      shift
      OUTPUT_DIR="${1:-}"
      ;;
    --skip-build)
      SKIP_BUILD=1
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

if [[ -z "$SCENARIO_ID" ]]; then
  usage
  exit 2
fi

require_catalog
SCENARIO_JSON="$(load_scenario "$SCENARIO_ID")"
SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"

read_env_value() {
  python3 - <<'PY' "$SCENARIO_JSON" "$1"
import json, sys
scenario = json.loads(sys.argv[1])
key = sys.argv[2]
value = scenario[key]
if isinstance(value, bool):
    print("1" if value else "0")
else:
    print(value)
PY
}

SPORT="$(read_env_value sport)"
RENDERER="$(read_env_value renderer)"
QUALITY="$(read_env_value quality)"
CAMERA="$(read_env_value camera)"
THEME="$(read_env_value theme)"
RIVAL="$(read_env_value rival)"
TIME="$(read_env_value time)"
REDUCED_MOTION="$(read_env_value reducedMotion)"
WIDTH="$(read_env_value width)"
HEIGHT="$(read_env_value height)"
PHASE="$(read_env_value phase)"

echo "scenario=$SCENARIO_ID"
echo "source_commit=$SOURCE_COMMIT"
echo "sport=$SPORT renderer=$RENDERER quality=$QUALITY camera=$CAMERA"
echo "theme=$THEME rival=$RIVAL time=$TIME reduced_motion=$REDUCED_MOTION"
echo "window=${WIDTH}x${HEIGHT} phase=$PHASE"
if [[ -n "$OUTPUT_DIR" ]]; then
  echo "output=<local directory supplied>"
  mkdir -p "$OUTPUT_DIR"
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  "$ROOT_DIR/script/build_and_run.sh" --acceptance --scenario "$SCENARIO_ID" --stage-only
else
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "missing staged app: $APP_BUNDLE (run without --skip-build)" >&2
    exit 1
  fi
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

OPEN_ARGS=(
  -n
  --env "ROWPLAY_REPLAY_ACCEPTANCE=1"
  --env "ROWPLAY_QA_SCENARIO=$SCENARIO_ID"
  --env "ROWPLAY_QA_SPORT=$SPORT"
  --env "ROWPLAY_QA_RENDERER=$RENDERER"
  --env "ROWPLAY_QA_QUALITY=$QUALITY"
  --env "ROWPLAY_QA_CAMERA=$CAMERA"
  --env "ROWPLAY_QA_THEME=$THEME"
  --env "ROWPLAY_QA_RIVAL=$RIVAL"
  --env "ROWPLAY_QA_TIME=$TIME"
  --env "ROWPLAY_QA_REDUCED_MOTION=$REDUCED_MOTION"
  --env "ROWPLAY_QA_WIDTH=$WIDTH"
  --env "ROWPLAY_QA_HEIGHT=$HEIGHT"
)

if [[ -n "$OUTPUT_DIR" ]]; then
  OPEN_ARGS+=(--env "ROWPLAY_QA_OUTPUT=$OUTPUT_DIR")
fi

/usr/bin/open "${OPEN_ARGS[@]}" "$APP_BUNDLE"
sleep 1
if ! pgrep -x "$APP_NAME" >/dev/null; then
  echo "acceptance launch failed: process not running" >&2
  exit 1
fi
echo "acceptance launch verified for scenario=$SCENARIO_ID"
