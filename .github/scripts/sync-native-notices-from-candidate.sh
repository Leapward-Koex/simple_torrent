#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <candidate-root>" >&2
  exit 64
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
candidate_root="$(cd -- "$1" && pwd)"
start_marker='<!-- BEGIN GENERATED NATIVE DEPENDENCIES -->'
end_marker='<!-- END GENERATED NATIVE DEPENDENCIES -->'
temporary_root="$(mktemp -d)"
trap 'rm -rf -- "$temporary_root"' EXIT

marker_count() {
  local marker="$1"
  local file="$2"
  awk -v marker="$marker" '$0 == marker { count += 1 } END { print count + 0 }' "$file"
}

for relative in \
  THIRD_PARTY_NOTICES.md \
  packages/simple_torrent_windows/THIRD_PARTY_NOTICES.md \
  packages/simple_torrent_android/THIRD_PARTY_NOTICES.md \
  packages/simple_torrent_ios/THIRD_PARTY_NOTICES.md \
  packages/simple_torrent_macos/THIRD_PARTY_NOTICES.md; do
  source="$candidate_root/$relative"
  destination="$repo_root/$relative"
  if [[ ! -f "$source" || -L "$source" || ! -f "$destination" || -L "$destination" ]]; then
    echo "Native notice source and destination must be regular files: $relative" >&2
    exit 65
  fi
  for file in "$source" "$destination"; do
    if [[ "$(marker_count "$start_marker" "$file")" != 1 || \
          "$(marker_count "$end_marker" "$file")" != 1 ]]; then
      echo "Native notice must contain exactly one generated block: $file" >&2
      exit 65
    fi
  done

  key="${relative//\//_}"
  block="$temporary_root/$key.block"
  output="$temporary_root/$key.output"
  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { inside = 1 }
    inside { print }
    inside && $0 == end { found = 1; exit }
    END { if (!found) exit 65 }
  ' "$source" > "$block"
  awk -v start="$start_marker" -v end="$end_marker" -v block="$block" '
    BEGIN {
      while ((getline line < block) > 0) replacement[++replacement_count] = line
      close(block)
    }
    $0 == start {
      for (i = 1; i <= replacement_count; i += 1) print replacement[i]
      skipping = 1
      next
    }
    skipping && $0 == end { skipping = 0; replaced = 1; next }
    !skipping { print }
    END { if (!replaced) exit 65 }
  ' "$destination" > "$output"
  chmod --reference="$destination" "$output"
  mv -- "$output" "$destination"
done
