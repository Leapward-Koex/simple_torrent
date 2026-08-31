#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

dart_command="$(command -v dart 2>/dev/null || true)"
dart_candidates=()
if [[ -n "$dart_command" ]]; then
  dart_command_dir="$(cd "$(dirname "$dart_command")" && pwd -P)"
  dart_candidates+=("$dart_command_dir/cache/dart-sdk/bin/dart")
fi
dart_candidates+=(
  "$repo_root/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart"
)
if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  dart_candidates+=("$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart")
fi
dart_candidates+=("${HOME}/fvm/default/bin/cache/dart-sdk/bin/dart")
if [[ -n "$dart_command" ]]; then
  dart_candidates+=("$dart_command")
fi

dart_bin=""
for candidate in "${dart_candidates[@]}"; do
  if [[ -x "$candidate" ]]; then
    dart_bin="$candidate"
    break
  fi
done
if [[ -z "$dart_bin" ]]; then
  echo "Dart was not found. Install Flutter 3.47 or newer, or add dart to PATH." >&2
  exit 127
fi

# Flutter's bin/dart wrapper runs the Flutter bootstrap and may wait on its
# global startup lock. The builder needs only the Dart VM, so prefer the SDK.
exec "$dart_bin" "$script_dir/native.dart" "$@"
