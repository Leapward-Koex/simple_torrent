#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <artifact-root>" >&2
  exit 64
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
artifact_root="$(cd -- "$1" && pwd)"

replace_tree() {
  local relative="$1"
  local source="$artifact_root/$relative"
  local destination="$repo_root/$relative"

  if [[ ! -d "$source" ]]; then
    echo "Native artifact staging tree is missing: $source" >&2
    exit 66
  fi
  if find "$source" -type l -print -quit | grep -q .; then
    echo "Native artifact staging trees may not contain symbolic links: $source" >&2
    exit 65
  fi

  rm -rf -- "$destination"
  mkdir -p -- "$(dirname -- "$destination")"
  cp -R -- "$source" "$destination"
  find "$destination" -type d -exec chmod 0755 {} +
  find "$destination" -type f -exec chmod 0644 {} +
}

replace_tree packages/simple_torrent_windows/windows/lib
replace_tree packages/simple_torrent_windows/windows/include
replace_tree packages/simple_torrent_android/android/src/main/jniLibs
replace_tree packages/simple_torrent_android/android/src/main/cpp/include
replace_tree packages/simple_torrent_ios/ios/simple_torrent_ios/Frameworks/SimpleTorrentNative.xcframework
replace_tree packages/simple_torrent_macos/macos/simple_torrent_macos/Frameworks/SimpleTorrentNative.xcframework
