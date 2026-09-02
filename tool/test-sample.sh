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
  windows|android|macos|ios) diagnostic_platform="$requested_platform" ;;
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
device_emulator=false
timeout_minutes=0
preflight_timeout_minutes=0
process_timeout_minutes=0
build_timeout_minutes=0
keep_on_failure=false
handling_failure=false
test_execution_mode="debug"
integration_runner="flutter-cli"
release_artifact_built=false
spm_release_verified=false
xctest_result_path=""
ios_spm_restore=""
xctest_derived_data=""
xctest_temp_root=""

fail() {
  local message="$1"
  local code="${2:-1}"
  handling_failure=true
  set +e
  trap - ERR
  printf 'ERROR: %s\n' "$message" >> "$log_path"
  local json
  json="{\"passed\":false,\"platform\":\"$(json_escape "$platform")\",\"device\":\"$(json_escape "$device_id")\",\"targetPlatform\":\"$(json_escape "$device_target")\",\"emulator\":$device_emulator,\"timeoutMinutes\":$timeout_minutes,\"preflightTimeoutMinutes\":$preflight_timeout_minutes,\"processTimeoutMinutes\":$process_timeout_minutes,\"buildTimeoutMinutes\":$build_timeout_minutes,\"keepOnFailure\":$keep_on_failure,\"buildMode\":\"$(json_escape "$build_mode")\",\"testExecutionMode\":\"$(json_escape "$test_execution_mode")\",\"integrationRunner\":\"$(json_escape "$integration_runner")\",\"releaseArtifactBuilt\":$release_artifact_built,\"spmReleaseVerified\":$spm_release_verified,\"testFile\":\"$(json_escape "$test_file")\",\"xctestResult\":\"$(json_escape "$xctest_result_path")\",\"exitCode\":$code,\"error\":\"$(json_escape "$message")\",\"log\":\"$(json_escape "$log_path")\",\"result\":\"$(json_escape "$result_path")\",\"completedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
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
  fail "Usage: tool/test-sample.sh <windows|android|macos|ios> [debug|release]" 64
}

[[ $# -ge 1 && $# -le 2 ]] || usage
case "$platform" in
  windows|android|macos|ios) ;;
  *) usage ;;
esac
[[ "$build_mode" == "debug" || "$build_mode" == "release" ]] ||
  fail "SIMPLE_TORRENT_BUILD_MODE must be debug or release." 64
if [[ "$build_mode" == "release" && "$platform" != "ios" ]]; then
  test_execution_mode="profile"
fi
if [[ "$platform" == "ios" ]]; then
  test_execution_mode="xctest-debug"
  integration_runner="xctest"
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

cleanup_ios_xctest() {
  set +e
  if [[ "$ios_spm_restore" == "enable" ]]; then
    (
      cd "$example_root"
      python3 "$script_dir/run_with_timeout.py" 60 \
        "${flutter_cmd[@]}" config --enable-swift-package-manager
    ) >> "$log_path" 2>&1 || true
  fi
  if [[ -n "$xctest_derived_data" && -n "$xctest_temp_root" &&
    -d "$xctest_derived_data" &&
    "$xctest_derived_data" == "$xctest_temp_root"/simple-torrent-ios-xctest.* ]]; then
    rm -rf -- "$xctest_derived_data"
  fi
}

command -v python3 >/dev/null 2>&1 ||
  fail "python3 is required for Flutter process supervision and device validation." 69
preflight_timeout_input="${SIMPLE_TORRENT_PREFLIGHT_TIMEOUT_MINUTES:-3}"
[[ "$preflight_timeout_input" =~ ^[0-9]+$ && ${#preflight_timeout_input} -le 2 ]] ||
  fail "SIMPLE_TORRENT_PREFLIGHT_TIMEOUT_MINUTES must be an integer from 1 to 30." 64
preflight_timeout_minutes=$((10#$preflight_timeout_input))
((preflight_timeout_minutes >= 1 && preflight_timeout_minutes <= 30)) ||
  fail "SIMPLE_TORRENT_PREFLIGHT_TIMEOUT_MINUTES must be an integer from 1 to 30." 64

device_stderr_path="$diagnostics_root/flutter-devices.stderr.log"
if device_output="$(
  python3 "$script_dir/run_with_timeout.py" \
    "$((preflight_timeout_minutes * 60))" \
    "${flutter_cmd[@]}" devices --machine 2>"$device_stderr_path"
)"; then
  device_exit_code=0
else
  device_exit_code=$?
fi
if [[ $device_exit_code -ne 0 ]]; then
  printf '%s\n' "$(<"$device_stderr_path")" >> "$log_path"
  if [[ $device_exit_code -eq 124 ]]; then
    fail "flutter devices exceeded its ${preflight_timeout_minutes}-minute process deadline." 124
  fi
  fail "flutter devices failed." 69
fi
printf 'Flutter devices:\n%s\n' "$device_output" >> "$log_path"
if [[ -s "$device_stderr_path" ]]; then
  printf 'Flutter device diagnostics:\n%s\n' "$(<"$device_stderr_path")" >> "$log_path"
fi
devices_path="$diagnostics_root/flutter-devices.json"
printf '%s\n' "$device_output" > "$devices_path"

if ! device_record="$(python3 - "$devices_path" "$platform" "$device_id" 2>>"$log_path" <<'PY'
import json
import sys

devices_path, platform, requested_id = sys.argv[1:]
with open(devices_path, encoding="utf-8") as stream:
    devices = json.load(stream)


def matches(device):
    target = str(device.get("targetPlatform", ""))
    if platform == "windows":
        return target.startswith("windows-")
    if platform == "android":
        return target.startswith("android-")
    if platform == "macos":
        return target == "darwin"
    if platform == "ios":
        return target == "ios" and device.get("emulator") is True
    return False


if requested_id:
    candidates = [device for device in devices if str(device.get("id", "")) == requested_id]
else:
    candidates = [
        device
        for device in devices
        if device.get("isSupported") is True and matches(device)
    ]
    candidates.sort(
        key=lambda device: (
            0
            if platform == "android" and device.get("targetPlatform") == "android-x64"
            else 1,
            0 if device.get("emulator") is True else 1,
            str(device.get("id", "")),
        )
    )

if candidates:
    selected = candidates[0]
    fields = (
        str(selected.get("id", "")),
        str(selected.get("targetPlatform", "")),
        "true" if selected.get("emulator") is True else "false",
        "true" if selected.get("isSupported") is True else "false",
    )
    print("\t".join(fields))
PY
)"; then
  fail "flutter devices returned invalid JSON; see $log_path." 69
fi
if [[ -z "$device_record" ]]; then
  if [[ -n "$device_id" ]]; then
    fail "Flutter device '$device_id' was not found." 69
  fi
  fail "No supported $platform device is available. Start/connect one or set SIMPLE_TORRENT_DEVICE_ID." 69
fi
IFS=$'\t' read -r device_id device_target device_emulator device_supported <<< "$device_record"
[[ "$device_supported" == true ]] ||
  fail "Flutter device '$device_id' is not supported." 69

case "$platform" in
  windows)
    [[ "$device_target" == windows-* ]] ||
      fail "Flutter device '$device_id' targets '$device_target', not windows." 69
    ;;
  android)
    [[ "$device_target" == android-* ]] ||
      fail "Flutter device '$device_id' targets '$device_target', not android." 69
    ;;
  macos)
    [[ "$device_target" == "darwin" ]] ||
      fail "Flutter device '$device_id' targets '$device_target', not macos." 69
    ;;
  ios)
    [[ "$device_target" == "ios" && "$device_emulator" == true ]] ||
      fail "Flutter device '$device_id' must be an iOS Simulator (targetPlatform ios, emulator true)." 69
    ;;
esac
printf 'Selected device: %s (%s, emulator=%s)\n' \
  "$device_id" "$device_target" "$device_emulator" >> "$log_path"

timeout_input="${SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES:-45}"
[[ "$timeout_input" =~ ^[0-9]+$ && ${#timeout_input} -le 3 ]] ||
  fail "SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES must be an integer from 1 to 240." 64
timeout_minutes=$((10#$timeout_input))
((timeout_minutes >= 1 && timeout_minutes <= 240)) ||
  fail "SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES must be an integer from 1 to 240." 64
process_timeout_input="${SIMPLE_TORRENT_PROCESS_TIMEOUT_MINUTES:-$((timeout_minutes + 10))}"
[[ "$process_timeout_input" =~ ^[0-9]+$ && ${#process_timeout_input} -le 3 ]] ||
  fail "SIMPLE_TORRENT_PROCESS_TIMEOUT_MINUTES must be an integer from 1 to 360." 64
process_timeout_minutes=$((10#$process_timeout_input))
((process_timeout_minutes >= 1 && process_timeout_minutes <= 360)) ||
  fail "SIMPLE_TORRENT_PROCESS_TIMEOUT_MINUTES must be an integer from 1 to 360." 64
build_timeout_input="${SIMPLE_TORRENT_BUILD_TIMEOUT_MINUTES:-30}"
[[ "$build_timeout_input" =~ ^[0-9]+$ && ${#build_timeout_input} -le 3 ]] ||
  fail "SIMPLE_TORRENT_BUILD_TIMEOUT_MINUTES must be an integer from 1 to 360." 64
build_timeout_minutes=$((10#$build_timeout_input))
((build_timeout_minutes >= 1 && build_timeout_minutes <= 360)) ||
  fail "SIMPLE_TORRENT_BUILD_TIMEOUT_MINUTES must be an integer from 1 to 360." 64
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
if [[ "$platform" == "ios" ]]; then
  # The iOS command is prepared after the real Release build and XCTest
  # project configuration below.
  test_command=()
elif [[ "$build_mode" == "release" ]]; then
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
  case "$platform" in
    windows)
      release_build_command=("${flutter_cmd[@]}" build windows --release)
      ;;
    android)
      release_build_command=("${flutter_cmd[@]}" build apk --release)
      ;;
    macos)
      release_build_command=("${flutter_cmd[@]}" build macos --release)
      ;;
    ios)
      release_build_command=("${flutter_cmd[@]}" build ios --release --no-codesign)
      ;;
  esac
  printf 'Building actual %s Release artifact before the %s integration run.\n' \
    "$platform" "$test_execution_mode" |
    tee -a "$log_path"
  (
    cd "$example_root"
    python3 "$script_dir/run_with_timeout.py" \
      "$((build_timeout_minutes * 60))" "${release_build_command[@]}"
  ) 2>&1 | tee -a "$log_path"
  release_pipeline_status=("${PIPESTATUS[@]}")
  if [[ ${release_pipeline_status[1]} -ne 0 ]]; then
    fail "Could not write Flutter Release-build diagnostics (tee exit code ${release_pipeline_status[1]})." "${release_pipeline_status[1]}"
  fi
  if [[ ${release_pipeline_status[0]} -ne 0 ]]; then
    if [[ ${release_pipeline_status[0]} -eq 124 ]]; then
      fail "Flutter Release build exceeded its ${build_timeout_minutes}-minute process deadline." 124
    fi
    fail "Flutter Release build failed with exit code ${release_pipeline_status[0]}." "${release_pipeline_status[0]}"
  fi
  release_artifact_built=true

  if [[ "$platform" == "ios" || "$platform" == "macos" ]]; then
    spm_manifest="$example_root/$platform/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
    spm_plugin="simple_torrent_$platform"
    if [[ ! -f "$spm_manifest" ]] || ! grep -Fq "$spm_plugin" "$spm_manifest"; then
      fail "The $platform Release build did not consume $spm_plugin through Flutter's generated Swift package." 70
    fi
    spm_release_verified=true
    printf 'Verified SwiftPM Release consumer: %s contains %s.\n' \
      "$spm_manifest" "$spm_plugin" | tee -a "$log_path"
  fi
fi

if [[ "$platform" == "ios" ]]; then
  command -v xcodebuild >/dev/null 2>&1 ||
    fail "xcodebuild is required for the iOS XCTest integration runner." 69

  # Flutter's normal simulator runner discovers the VM service by parsing a
  # live `simctl log stream`. That parser is unreliable with Xcode/iOS 26.
  # Flutter's supported XCTest adapter reports the same Dart integration tests
  # without depending on that log-discovery path. The adapter is exposed to the
  # app-hosted RunnerTests bundle through CocoaPods' `inherit! :search_paths`.
  # The preceding Release build still proves that the plugin is a valid SwiftPM
  # consumer; only this app-hosted test adapter uses the CocoaPods fallback.
  if ! swiftpm_config_json="$(
    cd "$example_root"
    python3 "$script_dir/run_with_timeout.py" 60 \
      "${flutter_cmd[@]}" config --machine 2>> "$log_path"
  )"; then
    fail "Could not read Flutter's SwiftPM configuration before the iOS XCTest run." 69
  fi
  if ! swiftpm_config_state="$(
    printf '%s\n' "$swiftpm_config_json" | python3 -c \
      'import json, sys; print("false" if json.load(sys.stdin).get("enable-swift-package-manager") is False else "true")'
  )"; then
    fail "Could not parse Flutter's SwiftPM configuration before the iOS XCTest run." 69
  fi
  if [[ "$swiftpm_config_state" == "true" ]]; then
    ios_spm_restore="enable"
  fi
  trap cleanup_ios_xctest EXIT

  printf 'Preparing iOS app-hosted XCTest integration target.\n' | tee -a "$log_path"
  (
    cd "$example_root"
    python3 "$script_dir/run_with_timeout.py" 60 \
      "${flutter_cmd[@]}" config --no-enable-swift-package-manager
  ) 2>&1 | tee -a "$log_path"
  config_toggle_status=("${PIPESTATUS[@]}")
  if [[ ${config_toggle_status[1]} -ne 0 ]]; then
    fail "Could not write Flutter dependency-manager diagnostics (tee exit code ${config_toggle_status[1]})." "${config_toggle_status[1]}"
  fi
  if [[ ${config_toggle_status[0]} -ne 0 ]]; then
    fail "Could not select CocoaPods for the iOS XCTest adapter." "${config_toggle_status[0]}"
  fi

  ios_config_command=(
    "${flutter_cmd[@]}" build ios
    --debug
    --simulator
    --config-only
    "${define_arguments[@]}"
    "$test_file"
  )
  (
    cd "$example_root"
    python3 "$script_dir/run_with_timeout.py" \
      "$((build_timeout_minutes * 60))" "${ios_config_command[@]}"
  ) 2>&1 | tee -a "$log_path"
  ios_config_status=("${PIPESTATUS[@]}")
  if [[ ${ios_config_status[1]} -ne 0 ]]; then
    fail "Could not write iOS XCTest configuration diagnostics (tee exit code ${ios_config_status[1]})." "${ios_config_status[1]}"
  fi
  if [[ ${ios_config_status[0]} -ne 0 ]]; then
    if [[ ${ios_config_status[0]} -eq 124 ]]; then
      fail "iOS XCTest configuration exceeded its ${build_timeout_minutes}-minute process deadline." 124
    fi
    fail "iOS XCTest configuration failed with exit code ${ios_config_status[0]}." "${ios_config_status[0]}"
  fi

  # Flutter retains the generated Swift package reference after SPM has been
  # disabled, but deliberately rewrites that package with no plugin products.
  # Prove that invariant before combining it with the app-hosted CocoaPods test
  # adapter, otherwise a stale aggregate could duplicate native symbols.
  ios_generated_spm_manifest="$example_root/ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
  [[ -f "$ios_generated_spm_manifest" ]] ||
    fail "Flutter did not regenerate the empty Swift package for the CocoaPods XCTest adapter." 70
  if grep -Fq 'simple_torrent_ios' "$ios_generated_spm_manifest" ||
    grep -Fq 'integration_test' "$ios_generated_spm_manifest"; then
    fail "The CocoaPods XCTest adapter still has plugin dependencies in Flutter's generated Swift package." 70
  fi

  pod_lock="$example_root/ios/Podfile.lock"
  if [[ ! -f "$pod_lock" ]] ||
    ! grep -Fq 'integration_test' "$pod_lock" ||
    ! grep -Fq 'simple_torrent_ios' "$pod_lock"; then
    fail "The iOS XCTest adapter was not configured with integration_test and simple_torrent_ios CocoaPods." 70
  fi

  xctest_result_path="$diagnostics_root/RunnerTests.xcresult"
  xctest_temp_root="${TMPDIR:-/tmp}"
  xctest_temp_root="${xctest_temp_root%/}"
  [[ -n "$xctest_temp_root" ]] || xctest_temp_root="/tmp"
  xctest_derived_data="$(mktemp -d "$xctest_temp_root/simple-torrent-ios-xctest.XXXXXX")" ||
    fail "Could not allocate isolated Xcode DerivedData for the iOS XCTest run." 73
  [[ -d "$xctest_derived_data" &&
    "$xctest_derived_data" == "$xctest_temp_root"/simple-torrent-ios-xctest.* ]] ||
    fail "The iOS XCTest DerivedData path is outside the validated temporary root." 73
  test_command=(
    env NSUnbufferedIO=YES
    xcodebuild test
    -workspace ios/Runner.xcworkspace
    -scheme Runner
    -configuration Debug
    -sdk iphonesimulator
    -destination "platform=iOS Simulator,id=$device_id"
    -destination-timeout 120
    -derivedDataPath "$xctest_derived_data"
    -resultBundlePath "$xctest_result_path"
    -parallel-testing-enabled NO
    -maximum-parallel-testing-workers 1
    CODE_SIGNING_ALLOWED=NO
    COMPILER_INDEX_STORE_ENABLE=NO
  )
fi
(
  cd "$example_root"
  python3 "$script_dir/run_with_timeout.py" \
    "$((process_timeout_minutes * 60))" "${test_command[@]}"
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
elif [[ $test_exit_code -eq 124 ]]; then
  passed=false
  error_field=",\"error\":\"Integration command exceeded its ${process_timeout_minutes}-minute process deadline.\""
else
  passed=false
  error_field=",\"error\":\"Integration test failed with exit code $test_exit_code.\""
fi
json="{\"passed\":$passed,\"platform\":\"$(json_escape "$platform")\",\"device\":\"$(json_escape "$device_id")\",\"targetPlatform\":\"$(json_escape "$device_target")\",\"emulator\":$device_emulator,\"timeoutMinutes\":$timeout_minutes,\"preflightTimeoutMinutes\":$preflight_timeout_minutes,\"processTimeoutMinutes\":$process_timeout_minutes,\"buildTimeoutMinutes\":$build_timeout_minutes,\"keepOnFailure\":$keep_on_failure,\"buildMode\":\"$(json_escape "$build_mode")\",\"testExecutionMode\":\"$(json_escape "$test_execution_mode")\",\"integrationRunner\":\"$(json_escape "$integration_runner")\",\"releaseArtifactBuilt\":$release_artifact_built,\"spmReleaseVerified\":$spm_release_verified,\"testFile\":\"$(json_escape "$test_file")\",\"xctestResult\":\"$(json_escape "$xctest_result_path")\",\"exitCode\":$test_exit_code,\"log\":\"$(json_escape "$log_path")\",\"result\":\"$(json_escape "$result_path")\",\"completedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"$error_field}"
printf '%s\n' "$json" > "$result_path"
printf 'SIMPLE_TORRENT_TEST_RESULT=%s\n' "$json"
exit "$test_exit_code"
