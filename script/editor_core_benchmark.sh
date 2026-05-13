#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OPENAPI_FIXTURE="${SIMPLELIME_OPENAPI_FIXTURE:-/Users/malikov/Downloads/openapi.json}"
FIXTURE_DIR="${SIMPLELIME_EDITOR_BENCHMARK_DIR:-$ROOT_DIR/.build/editor-core-benchmark}"
LAUNCH_OPENAPI=0
SKIP_BUILD=0

usage() {
  printf '%s\n' "Usage: script/editor_core_benchmark.sh [--launch-openapi] [--skip-build]"
  printf '%s\n' ""
  printf '%s\n' "Environment:"
  printf '%s\n' "  SIMPLELIME_OPENAPI_FIXTURE=/path/to/openapi.json"
  printf '%s\n' "  SIMPLELIME_EDITOR_BENCHMARK_DIR=/path/to/generated/fixtures"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --launch-openapi)
      LAUNCH_OPENAPI=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
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

elapsed_seconds() {
  local start="$1"
  local end
  end="$(date +%s)"
  printf '%ss' "$((end - start))"
}

print_fixture_stats() {
  local label="$1"
  local path="$2"

  if [[ ! -f "$path" ]]; then
    printf '%-28s missing: %s\n' "$label" "$path"
    return
  fi

  local bytes
  local lines
  bytes="$(wc -c < "$path" | tr -d '[:space:]')"
  lines="$(wc -l < "$path" | tr -d '[:space:]')"
  printf '%-28s %s bytes, %s lines: %s\n' "$label" "$bytes" "$lines" "$path"
}

generate_fixtures() {
  mkdir -p "$FIXTURE_DIR"

  {
    printf '%s\n' "# Editor Core Markdown Fixture"
    printf '%s\n' ""
    seq 1 25000 | awk '{
      printf "## Section %05d\n", $1
      printf "- [ ] need verify editor line %05d\n", $1
      printf "Plain text paragraph for source editing, selection, minimap, comments, and folding smoke.\n\n"
    }'
  } > "$FIXTURE_DIR/large-markdown.md"

  {
    printf '%s\n' "id,name,value,flag"
    seq 1 16000 | awk '{
      flag = ($1 % 2 == 0) ? "false" : "true"
      printf "%d,item-%05d,%d,%s\n", $1, $1, $1 * 3, flag
    }'
  } > "$FIXTURE_DIR/large-table.csv"

  {
    printf '%s\n' "plain editor fixture"
    seq 1 25000 | awk '{
      printf "line %05d alpha beta gamma delta epsilon\n", $1
    }'
  } > "$FIXTURE_DIR/large-plain.txt"
}

run_focused_tests() {
  local start
  start="$(date +%s)"
  swift test --disable-sandbox \
    --filter CodeEditorViewTests \
    --filter SourceEditorAdapterTests \
    --filter EditorCorePerformanceProbeTests \
    --filter LargeFileVirtualTextDocumentTests \
    --filter DelimitedVirtualTableDocumentTests \
    --filter EditorPerformanceTelemetryTests \
    --filter EditorStoreModeTests/testEditorDiagnosticsScratchReportsNormalSourceEditorPath \
    --filter EditorStoreModeTests/testEditorDiagnosticsScratchReportsLargeFileRestrictions
  printf 'Focused editor smoke tests completed in %s.\n' "$(elapsed_seconds "$start")"
}

run_build() {
  local start
  start="$(date +%s)"
  ./script/build_and_run.sh --build-only
  printf 'App build completed in %s.\n' "$(elapsed_seconds "$start")"
}

launch_openapi() {
  if [[ ! -f "$OPENAPI_FIXTURE" ]]; then
    printf 'Cannot launch missing OpenAPI fixture: %s\n' "$OPENAPI_FIXTURE" >&2
    exit 1
  fi

  ./script/build_and_run.sh run "$OPENAPI_FIXTURE"
}

START_TIME="$(date +%s)"

printf '%s\n' "SimpleLime editor core benchmark smoke"
printf '%s\n' "======================================="
generate_fixtures
print_fixture_stats "OpenAPI fixture" "$OPENAPI_FIXTURE"
print_fixture_stats "Generated Markdown" "$FIXTURE_DIR/large-markdown.md"
print_fixture_stats "Generated CSV" "$FIXTURE_DIR/large-table.csv"
print_fixture_stats "Generated plain text" "$FIXTURE_DIR/large-plain.txt"
printf '%s\n' ""

run_focused_tests

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  run_build
else
  printf '%s\n' "Skipping app build."
fi

if [[ "$LAUNCH_OPENAPI" -eq 1 ]]; then
  launch_openapi
fi

printf 'Editor core benchmark smoke finished in %s.\n' "$(elapsed_seconds "$START_TIME")"
printf '%s\n' "Next live gate: script/editor_live_latency_smoke.sh --skip-build"
printf '%s\n' "OpenAPI live gate: script/editor_live_latency_smoke.sh --skip-build --openapi"
