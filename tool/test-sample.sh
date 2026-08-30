#!/usr/bin/env bash
set -Eeuo pipefail

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
requested_platform="${1:-unknown}"
build_mode="${2:-${SIMPLE_TORRENT_BUILD_MODE:-debug}}"
test_file="${SIMPLE_TORRENT_TEST_FILE:-integration_test/wired_download_test.dart}"
diagnostics_suite="${SIMPLE_TORRENT_DIAGNOSTICS_SUITE:-test-sample}"
case "$requested_platform" in
  windows|android) diagnostic_platform="$requested_platform" ;;
  *) diagnostic_platform="unknown" ;;
esac
timestamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
diagnostics_root="$repo_root/build/$diagnostics_suite/$diagnostic_platform-$timestamp"
mkdir -p "$diagnostics_root"
log_path="$diagnostics_root/flutter-test.log"
result_path="$diagnostics_root/result.json"
: > "$log_path"

platform="$requested_platform"
device_id="${SIMPLE_TORRENT_DEVICE_ID:-}"
device_target=""
timeout_minutes=""
keep_on_failure=false
handling_failure=false
test_execution_mode="debug"
release_artifact_built=false

fail() {
  local message="$1"
  local code="${2:-1}"
  handling_failure=true
  set +e
  trap - ERR
  printf 'ERROR: %s\n' "$message" >> "$log_path"
  local json
  json="{\"passed\":false,\"platform\":\"$(json_escape "$platform")\",\"device\":\"$(json_escape "$device_id")\",\"targetPlatform\":\"$(json_escape "$device_target")\",\"buildMode\":\"$(json_escape "$build_mode")\",\"testExecutionMode\":\"$(json_escape "$test_execution_mode")\",\"releaseArtifactBuilt\":$release_artifact_built,\"testFile\":\"$(json_escape "$test_file")\",\"exitCode\":$code,\"error\":\"$(json_escape "$message")\",\"log\":\"$(json_escape "$log_path")\",\"result\":\"$(json_escape "$result_path")\",\"completedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
  printf '%s\n' "$json" > "$result_path"
  printf '%s\n' "$message" >&2
  printf 'SIMPLE_TORRENT_TEST_RESULT=%s\n' "$json"
  exit "$code"
}

unexpected_failure() {
  local code="$1"
  local line="$2"
  if [[ "$handling_failure" == true ]]; then
    exit "$code"
  fi
  fail "Unexpected script failure at line $line." "$code"
}
trap 'unexpected_failure "$?" "$LINENO"' ERR

usage() {
  fail "Usage: tool/test-sample.sh <windows|android> [debug|release]" 64
}

[[ $# -ge 1 && $# -le 2 ]] || usage
[[ "$platform" == "windows" || "$platform" == "android" ]] || usage
[[ "$build_mode" == "debug" || "$build_mode" == "release" ]] ||
  fail "SIMPLE_TORRENT_BUILD_MODE must be debug or release." 64
if [[ "$build_mode" == "release" ]]; then
  test_execution_mode="profile"
fi
example_root="$repo_root/packages/simple_torrent/example"
[[ -f "$example_root/pubspec.yaml" ]] ||
  fail "Example package not found at $example_root" 66

if [[ -n "${SIMPLE_TORRENT_FLUTTER:-}" ]]; then
  flutter_cmd=("$SIMPLE_TORRENT_FLUTTER")
elif [[ -n "${FLUTTER_ROOT:-}" && -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  flutter_cmd=("$FLUTTER_ROOT/bin/flutter")
elif command -v flutter >/dev/null 2>&1; then
  flutter_cmd=("$(command -v flutter)")
elif command -v fvm >/dev/null 2>&1; then
  flutter_cmd=("$(command -v fvm)" flutter)
else
  fail "Flutter was not found. Put flutter on PATH or set SIMPLE_TORRENT_FLUTTER." 69
fi

if ! device_output="$("${flutter_cmd[@]}" devices 2>&1)"; then
  printf '%s\n' "$device_output" >> "$log_path"
  fail "flutter devices failed." 69
fi
printf 'Flutter devices:\n%s\n' "$device_output" >> "$log_path"

if [[ -n "$device_id" ]]; then
  device_target="$(printf '%s\n' "$device_output" | awk -F ' • ' -v expected="$device_id" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    NF >= 3 {
      id = trim($2)
      target = trim($3)
      if (id == expected) {
        print target
        exit
      }
    }
  ')"
  [[ -n "$device_target" ]] ||
    fail "Flutter device '$device_id' was not found." 69
else
  if [[ "$platform" == "windows" ]]; then
    device_record="$(printf '%s\n' "$device_output" | awk -F ' • ' '
      function trim(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        return value
      }
      NF >= 3 {
        id = trim($2)
        target = trim($3)
        if (target ~ /^windows-/) {
          print id "\t" target
          exit
        }
      }
    ')"
  else
    device_record="$(printf '%s\n' "$device_output" | awk -F ' • ' '
      function trim(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        return value
      }
      NF >= 3 {
        id = trim($2)
        target = trim($3)
        if (target ~ /^android-/ && fallback == "") {
          fallback = id "\t" target
        }
        if (target == "android-x64") {
          print id "\t" target
          found = 1
          exit
        }
      }
      END {
        if (!found && fallback != "") print fallback
      }
    ')"
  fi
  [[ -n "$device_record" ]] ||
    fail "No supported $platform device is available. Start/connect one or set SIMPLE_TORRENT_DEVICE_ID." 69
  IFS=$'\t' read -r device_id device_target <<< "$device_record"
fi

case "$platform" in
  windows)
    [[ "$device_target" == windows-* ]] ||
      fail "Flutter device '$device_id' targets '$device_target', not windows." 69
    ;;
  android)
    [[ "$device_target" == android-* ]] ||
      fail "Flutter device '$device_id' targets '$device_target', not android." 69
    ;;
esac
printf 'Selected device: %s (%s)\n' "$device_id" "$device_target" >> "$log_path"

timeout_input="${SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES:-45}"
[[ "$timeout_input" =~ ^[0-9]+$ && ${#timeout_input} -le 3 ]] ||
  fail "SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES must be an integer from 1 to 240." 64
timeout_minutes=$((10#$timeout_input))
((timeout_minutes >= 1 && timeout_minutes <= 240)) ||
  fail "SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES must be an integer from 1 to 240." 64
case "${SIMPLE_TORRENT_KEEP_ON_FAILURE:-false}" in
  1|true|TRUE|yes|YES) keep_on_failure=true ;;
  *) keep_on_failure=false ;;
esac

trap - ERR
set +e
define_arguments=(
  "--dart-define=SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES=$timeout_minutes"
  "--dart-define=SIMPLE_TORRENT_KEEP_ON_FAILURE=$keep_on_failure"
  "--dart-define=SIMPLE_TORRENT_EXPECTED_PLATFORM=$platform"
)
if [[ "$build_mode" == "release" ]]; then
  # Non-web Flutter Driver intentionally rejects --release because release
  # builds have no VM service. Build the real release artifact, then drive the
  # same bundled native binary in the closest supported mode.
  test_command=(
    "${flutter_cmd[@]}" drive
    --driver=test_driver/integration_test.dart
    "--target=$test_file"
    -d "$device_id"
    --profile
    "${define_arguments[@]}"
  )
else
  test_command=(
    "${flutter_cmd[@]}" test "$test_file"
    -d "$device_id"
    "${define_arguments[@]}"
  )
fi
if [[ "$build_mode" == "release" ]]; then
  if [[ "$platform" == "windows" ]]; then
    release_build_command=("${flutter_cmd[@]}" build windows --release)
  else
    release_build_command=("${flutter_cmd[@]}" build apk --release)
  fi
  printf 'Building actual %s Release artifact before the Profile integration run.\n' "$platform" |
    tee -a "$log_path"
  (
    cd "$example_root"
    "${release_build_command[@]}"
  ) 2>&1 | tee -a "$log_path"
  release_pipeline_status=("${PIPESTATUS[@]}")
  if [[ ${release_pipeline_status[1]} -ne 0 ]]; then
    fail "Could not write Flutter Release-build diagnostics (tee exit code ${release_pipeline_status[1]})." "${release_pipeline_status[1]}"
  fi
  if [[ ${release_pipeline_status[0]} -ne 0 ]]; then
    fail "Flutter Release build failed with exit code ${release_pipeline_status[0]}." "${release_pipeline_status[0]}"
  fi
  release_artifact_built=true
fi
(
  cd "$example_root"
  "${test_command[@]}"
) 2>&1 | tee -a "$log_path"
pipeline_status=("${PIPESTATUS[@]}")
set -e
trap 'unexpected_failure "$?" "$LINENO"' ERR
test_exit_code="${pipeline_status[0]}"
tee_exit_code="${pipeline_status[1]}"
if [[ $tee_exit_code -ne 0 ]]; then
  fail "Could not write Flutter diagnostics (tee exit code $tee_exit_code)." "$tee_exit_code"
fi

if [[ $test_exit_code -eq 0 ]]; then
  passed=true
  error_field=""
else
  passed=false
  error_field=",\"error\":\"Flutter integration test failed with exit code $test_exit_code.\""
fi
json="{\"passed\":$passed,\"platform\":\"$(json_escape "$platform")\",\"device\":\"$(json_escape "$device_id")\",\"targetPlatform\":\"$(json_escape "$device_target")\",\"timeoutMinutes\":$timeout_minutes,\"keepOnFailure\":$keep_on_failure,\"buildMode\":\"$(json_escape "$build_mode")\",\"testExecutionMode\":\"$(json_escape "$test_execution_mode")\",\"releaseArtifactBuilt\":$release_artifact_built,\"testFile\":\"$(json_escape "$test_file")\",\"exitCode\":$test_exit_code,\"log\":\"$(json_escape "$log_path")\",\"result\":\"$(json_escape "$result_path")\",\"completedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"$error_field}"
printf '%s\n' "$json" > "$result_path"
printf 'SIMPLE_TORRENT_TEST_RESULT=%s\n' "$json"
exit "$test_exit_code"
