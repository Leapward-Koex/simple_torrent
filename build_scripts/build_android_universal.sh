#!/usr/bin/env bash
set -euo pipefail

#
# Build Android universal libraries for libtorrent and Boost.
# This script builds for all Android architectures and organizes output properly.
#

# ── config ──────────────────────────────────────────────────────────
Here="$(cd "$(dirname "$0")" && pwd)"
SharedDir="$Here/../shared"
AndroidDir="$Here/../android"

# Final output directories (matching CMakeLists.txt expectations)
FinalBoostDir="$SharedDir/third_party/boost"
FinalLibtIncludeDir="$SharedDir/third_party/libtorrent/include"
JniLibsBase="$AndroidDir/src/main/jniLibs"

# Supported Android ABIs
AndroidABIs=("arm64-v8a" "armeabi-v7a" "x86_64")

echo "Building Android universal libraries for libtorrent..."
echo "Output directories:"
echo "  Boost headers → $FinalBoostDir"
echo "  libtorrent headers → $FinalLibtIncludeDir"
echo "  libtorrent shared libs → $JniLibsBase/<abi>/"
echo ""

# ── 1. build all architectures ─────────────────────────────────────
for ABI in "${AndroidABIs[@]}"; do
    echo "Building Android $ABI..."
    
    case "$ABI" in
        'arm64-v8a')
            "$Here/build_android_arm64-v8a.sh"
            ;;
        'armeabi-v7a')
            "$Here/build_android_armabi-v7a.sh"
            ;;
        'x86_64')
            "$Here/build_android_x86_64.sh"
            ;;
    esac
    
    echo "✓ $ABI build complete"
    echo ""
done

# ── 2. verify output structure ─────────────────────────────────────
echo "Verifying build outputs..."
echo ""

echo "Headers:"
if [ -f "$FinalLibtIncludeDir/libtorrent/session.hpp" ]; then
    HeaderCount=$(find "$FinalLibtIncludeDir" -name "*.hpp" | wc -l | tr -d ' ')
    echo "✓ libtorrent headers: $HeaderCount files"
else
    echo "✗ libtorrent headers: not found"
fi

if [ -f "$FinalBoostDir/boost/config.hpp" ]; then
    BoostHeaderCount=$(find "$FinalBoostDir" -name "*.hpp" | wc -l | tr -d ' ')
    echo "✓ Boost headers: $BoostHeaderCount files"
else
    echo "✗ Boost headers: not found"
fi

echo ""
echo "Shared Libraries by ABI:"
for ABI in "${AndroidABIs[@]}"; do
    JniLibDir="$JniLibsBase/$ABI"
    LibtorrentLib="$JniLibDir/libtorrent-rasterbar.so.2.0.11"
    
    if [ -f "$LibtorrentLib" ]; then
        if command -v stat >/dev/null 2>&1; then
            if [ "$(uname)" = "Darwin" ]; then
                Size=$(stat -f%z "$LibtorrentLib")
            else
                Size=$(stat -c%s "$LibtorrentLib")
            fi
            SizeMB=$(echo "scale=1; $Size / 1024 / 1024" | bc)
            echo "✓ $ABI: libtorrent-rasterbar.so.2.0.11 (${SizeMB} MB)"
        else
            echo "✓ $ABI: libtorrent-rasterbar.so.2.0.11"
        fi
    else
        echo "✗ $ABI: libtorrent library not found"
    fi
done

echo ""
echo "Your Android libraries are ready for use in the Flutter plugin!"
echo "Libraries are organized by ABI in android/src/main/jniLibs/"
echo "Headers are in shared/third_party/ for CMakeLists.txt to find"
