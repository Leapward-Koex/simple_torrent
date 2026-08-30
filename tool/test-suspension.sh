#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export SIMPLE_TORRENT_TEST_FILE="integration_test/transfer_suspension_test.dart"
export SIMPLE_TORRENT_DIAGNOSTICS_SUITE="test-suspension"
export SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES="${SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES:-5}"
exec "$script_dir/test-sample.sh" "$@"
