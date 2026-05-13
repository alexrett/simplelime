#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="SimpleLime"
OPENAPI_FIXTURE="${SIMPLELIME_OPENAPI_FIXTURE:-/Users/malikov/Downloads/openapi.json}"
FIXTURE_DIR="${SIMPLELIME_EDITOR_LIVE_FIXTURE_DIR:-$ROOT_DIR/.build/editor-live-latency}"
LOG_FILE="${SIMPLELIME_EDITOR_LIVE_LOG:-$FIXTURE_DIR/editor-performance.log}"
FIXTURE_PATH="$FIXTURE_DIR/live-latency-smoke.md"
CAPTURE_SECONDS="${SIMPLELIME_EDITOR_LIVE_SECONDS:-8}"
SKIP_BUILD=0
USE_OPENAPI=0
TYPE_IN_APP=1
STRICT=0

usage() {
  printf '%s\n' "Usage: script/editor_live_latency_smoke.sh [--skip-build] [--openapi] [--no-type] [--strict]"
  printf '%s\n' ""
  printf '%s\n' "Runs the built macOS app, captures EditorPerformance logs, and prints p95/max"
  printf '%s\n' "duration metrics. The script does not capture screenshots."
  printf '%s\n' ""
  printf '%s\n' "Environment:"
  printf '%s\n' "  SIMPLELIME_OPENAPI_FIXTURE=/path/to/openapi.json"
  printf '%s\n' "  SIMPLELIME_EDITOR_LIVE_FIXTURE_DIR=/tmp/simplelime-live"
  printf '%s\n' "  SIMPLELIME_EDITOR_LIVE_LOG=/tmp/simplelime-live/editor-performance.log"
  printf '%s\n' "  SIMPLELIME_EDITOR_LIVE_SECONDS=8"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --openapi)
      USE_OPENAPI=1
      shift
      ;;
    --no-type)
      TYPE_IN_APP=0
      shift
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

running_app_pids() {
  pgrep -x "$APP_NAME" 2>/dev/null || true
}

wait_for_app() {
  local attempts=0
  while [[ -z "$(running_app_pids)" && "$attempts" -lt 80 ]]; do
    sleep 0.25
    attempts=$((attempts + 1))
  done
  [[ -n "$(running_app_pids)" ]]
}

wait_for_app_exit() {
  local attempts=0
  while [[ -n "$(running_app_pids)" && "$attempts" -lt 100 ]]; do
    sleep 0.2
    attempts=$((attempts + 1))
  done
  [[ -z "$(running_app_pids)" ]]
}

stop_app() {
  [[ -z "$(running_app_pids)" ]] && return 0

  pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
  if wait_for_app_exit; then
    return 0
  fi

  pkill -KILL -x "$APP_NAME" >/dev/null 2>&1 || true
  wait_for_app_exit
}

wait_for_bridge() {
  local attempts=0
  while [[ "$attempts" -lt 50 ]]; do
    if /usr/bin/curl -fsS "http://127.0.0.1:48777/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
    attempts=$((attempts + 1))
  done
  return 1
}

post_insert_text() {
  local text="$1"
  /usr/bin/curl -fsS "http://127.0.0.1:48777/v1/command" \
    -H 'Content-Type: application/json' \
    -d "{\"command\":\"insertText\",\"text\":\"$text\"}" >/dev/null
}

type_with_system_events() {
  /usr/bin/osascript <<'OSA'
tell application "SimpleLime" to activate
delay 0.5
tell application "System Events"
  if not (exists process "SimpleLime") then error "SimpleLime process is not visible to System Events"
  tell process "SimpleLime"
    set frontmost to true
    set targetWindow to window 1
    set windowPosition to position of targetWindow
    set windowSize to size of targetWindow
    set clickX to (item 1 of windowPosition) + ((item 1 of windowSize) / 2)
    set clickY to (item 2 of windowPosition) + ((item 2 of windowSize) / 2)
    click at {clickX, clickY}
    delay 0.2
    keystroke "live latency smoke"
    key code 36
    keystroke "shift selection probe"
    key down shift
    key code 125
    key up shift
    key code 124
  end tell
end tell
OSA
}

metric_values() {
  local metric="$1"
  grep "metric=$metric " "$LOG_FILE" 2>/dev/null |
    sed -E 's/.*duration_ms=([0-9.]+).*/\1/' |
    grep -E '^[0-9]+([.][0-9]+)?$' |
    sort -n
}

print_metric_stats() {
  local metric="$1"
  local values
  values="$(metric_values "$metric" || true)"
  if [[ -z "$values" ]]; then
    printf '%-28s no samples\n' "$metric"
    return 1
  fi

  local count
  count="$(printf '%s\n' "$values" | wc -l | tr -d '[:space:]')"
  local p95_index=$(( (count * 95 + 99) / 100 ))
  [[ "$p95_index" -lt 1 ]] && p95_index=1
  local p95
  local max
  local avg
  p95="$(printf '%s\n' "$values" | sed -n "${p95_index}p")"
  max="$(printf '%s\n' "$values" | tail -n 1)"
  avg="$(printf '%s\n' "$values" | awk '{sum += $1} END {printf "%.3f", sum / NR}')"
  printf '%-28s count=%-4s avg=%8.3fms p95=%8.3fms max=%8.3fms\n' "$metric" "$count" "$avg" "$p95" "$max"
}

fail_if_strict_metric_slow() {
  local metric="$1"
  local threshold="$2"
  local values
  values="$(metric_values "$metric" || true)"
  if [[ -z "$values" ]]; then
    printf 'Strict mode: missing required metric %s.\n' "$metric" >&2
    return 1
  fi

  local count
  count="$(printf '%s\n' "$values" | wc -l | tr -d '[:space:]')"
  local p95_index=$(( (count * 95 + 99) / 100 ))
  [[ "$p95_index" -lt 1 ]] && p95_index=1
  local p95
  p95="$(printf '%s\n' "$values" | sed -n "${p95_index}p")"
  awk -v p95="$p95" -v threshold="$threshold" 'BEGIN { exit(p95 <= threshold ? 0 : 1) }' || {
    printf 'Strict mode: %s p95 %.3fms exceeds %.3fms.\n' "$metric" "$p95" "$threshold" >&2
    return 1
  }
}

mkdir -p "$FIXTURE_DIR"
cat >"$FIXTURE_PATH" <<'EOF'
# Live Latency Smoke

This file is intentionally small. The live smoke checks the actual AppKit key
path, selection path, store update path, and render/update path in a built app.

EOF

if [[ "$USE_OPENAPI" -eq 1 ]]; then
  if [[ ! -f "$OPENAPI_FIXTURE" ]]; then
    printf 'Missing OpenAPI fixture: %s\n' "$OPENAPI_FIXTURE" >&2
    exit 1
  fi
  FIXTURE_PATH="$OPENAPI_FIXTURE"
fi

stop_app

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  ./script/build_and_run.sh --build-only
fi

APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  printf 'Missing app bundle: %s\n' "$APP_BUNDLE" >&2
  printf 'Run without --skip-build first.\n' >&2
  exit 1
fi

rm -f "$LOG_FILE"
/usr/bin/log stream --style compact --info --debug \
  --predicate 'process == "SimpleLime" && subsystem == "com.whitehappypony.SimpleLime" && category == "EditorPerformance"' \
  >"$LOG_FILE" 2>&1 &
LOG_PID=$!
cleanup() {
  kill "$LOG_PID" >/dev/null 2>&1 || true
  wait "$LOG_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

/usr/bin/open -n "$APP_BUNDLE" --args --safe-mode "$FIXTURE_PATH"
if ! wait_for_app; then
  printf 'SimpleLime did not start.\n' >&2
  exit 1
fi

if wait_for_bridge; then
  post_insert_text "automation latency smoke\n" || true
else
  printf '%s\n' "Automation bridge did not become ready; continuing with GUI telemetry only."
fi

if [[ "$TYPE_IN_APP" -eq 1 ]]; then
  if ! type_with_system_events; then
    printf '%s\n' "System Events typing failed. Grant Accessibility to the terminal/Codex host or rerun with --no-type for launch/open telemetry only." >&2
  fi
fi

sleep "$CAPTURE_SECONDS"
cleanup
trap - EXIT

printf '%s\n' "EditorPerformance metrics from $LOG_FILE"
printf '%s\n' "Fixture: $FIXTURE_PATH"
print_metric_stats "EditorOpenFile" || true
print_metric_stats "EditorInitialRender" || true
print_metric_stats "EditorUpdateRender" || true
print_metric_stats "EditorKeyDown" || true
print_metric_stats "EditorTextChange" || true
print_metric_stats "EditorSelectionChange" || true
print_metric_stats "EditorSyntaxHighlight" || true
print_metric_stats "EditorStoreUpdateText" || true

if [[ "$STRICT" -eq 1 ]]; then
  fail_if_strict_metric_slow "EditorKeyDown" 32
  fail_if_strict_metric_slow "EditorTextChange" 32
fi
