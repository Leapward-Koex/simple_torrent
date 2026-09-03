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
trap 'rm -rf "$temporary_root"' EXIT

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

  # The Boost 1.92 source update retires two reviewed paragraphs outside the
  # generated tables. Apply only those exact migrations, then require the
  # complete result to match the candidate. This keeps unrelated notice prose
  # protected while allowing the generated bundle PR to remove stale claims.
  python3 - "$relative" "$source" "$output" <<'PY'
import pathlib
import sys

relative, source_path, output_path = sys.argv[1:]
migrations = {
    "THIRD_PARTY_NOTICES.md": (
        "When required by the pinned Boost release, the builder applies the reviewed,\n"
        "repository-tracked Android x86_64 long-double compatibility patch. Applied\n"
        "patch paths and checksums are recorded in the authenticated source stamp and\n"
        "artifact provenance, so a dependency version change cannot silently reuse a\n"
        "patch for a different source release.",
        "The pinned Boost release contains the Android x86_64 long-double correction\n"
        "upstream in Boost.Math, so the bundled sources require no repository-maintained\n"
        "Boost patch. Artifact provenance records an empty source-patch inventory.",
    ),
    "packages/simple_torrent_android/THIRD_PARTY_NOTICES.md": (
        "When required by the pinned Boost release, the maintainer build applies the\n"
        "reviewed Android x86_64 long-double compatibility patch documented in the root\n"
        "third-party notices. Its path and checksum are recorded in artifact provenance.",
        "The pinned Boost release contains the Android x86_64 long-double correction\n"
        "upstream in Boost.Math, so this bundle requires no repository-maintained Boost\n"
        "patch.",
    ),
}


def normalized_text(path):
    return (
        pathlib.Path(path)
        .read_text(encoding="utf-8")
        .replace("\r\n", "\n")
        .replace("\r", "\n")
    )


source_text = normalized_text(source_path)
output_text = normalized_text(output_path)
migration = migrations.get(relative)
if migration is not None and migration[0] in output_text:
    output_text = output_text.replace(migration[0], migration[1], 1)

if output_text != source_text:
    print(
        f"Candidate native notice contains unsupported changes outside the generated block: {relative}",
        file=sys.stderr,
    )
    raise SystemExit(65)

with open(output_path, "w", encoding="utf-8", newline="\n") as output_file:
    output_file.write(output_text)
PY

  # Notice files are committed as ordinary non-executable Markdown. A fixed
  # mode is portable across GNU and BSD userlands; macOS chmod does not support
  # GNU's --reference option.
  chmod 0644 "$output"
  mv "$output" "$destination"
done
