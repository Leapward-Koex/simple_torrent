#!/usr/bin/env bash
set -euo pipefail

#
# macOS Universal build script
# Creates universal (fat) binaries for macOS from arm64 and x86_64 builds
#

Here="$(cd "$(dirname "$0")" && pwd)"
ToolsDir="$Here/toolchains"

# Build directories
ARM64_BUILD_ROOT="${ToolsDir}/build-macos-arm64"
X86_64_BUILD_ROOT="${ToolsDir}/build-macos-x86_64"
UNIVERSAL_BUILD_ROOT="${ToolsDir}/build-macos-universal"

# Create universal build directory
mkdir -p "$UNIVERSAL_BUILD_ROOT/boost-stage/lib"
mkdir -p "$UNIVERSAL_BUILD_ROOT/libtorrent-build"

echo "▶︎ Creating macOS Universal binaries..."

# Function to create universal binary
create_universal_lib() {
    local lib_name="$1"
    local arm64_lib="${ARM64_BUILD_ROOT}/boost-stage/lib/${lib_name}"
    local x86_64_lib="${X86_64_BUILD_ROOT}/boost-stage/lib/${lib_name}"
    local universal_lib="${UNIVERSAL_BUILD_ROOT}/boost-stage/lib/${lib_name}"
    
    if [[ -f "$arm64_lib" && -f "$x86_64_lib" ]]; then
        echo "  Creating universal $lib_name..."
        lipo -create "$arm64_lib" "$x86_64_lib" -output "$universal_lib"
    else
        echo "  ⚠️  Missing libraries for $lib_name (arm64: $([ -f "$arm64_lib" ] && echo "✓" || echo "✗"), x86_64: $([ -f "$x86_64_lib" ] && echo "✓" || echo "✗"))"
    fi
}

# Create universal Boost libraries
create_universal_lib "libboost_system.a"
create_universal_lib "libboost_atomic.a"
create_universal_lib "libboost_thread.a"
create_universal_lib "libboost_chrono.a"
create_universal_lib "libboost_regex.a"
create_universal_lib "libboost_filesystem.a"
create_universal_lib "libboost_date_time.a"

# Create universal libtorrent library
ARM64_LIBTORRENT="${ARM64_BUILD_ROOT}/libtorrent-build/libtorrent-rasterbar.a"
X86_64_LIBTORRENT="${X86_64_BUILD_ROOT}/libtorrent-build/libtorrent-rasterbar.a"
UNIVERSAL_LIBTORRENT="${UNIVERSAL_BUILD_ROOT}/libtorrent-build/libtorrent-rasterbar.a"

if [[ -f "$ARM64_LIBTORRENT" && -f "$X86_64_LIBTORRENT" ]]; then
    echo "  Creating universal libtorrent-rasterbar.a..."
    lipo -create "$ARM64_LIBTORRENT" "$X86_64_LIBTORRENT" -output "$UNIVERSAL_LIBTORRENT"
else
    echo "  ⚠️  Missing libtorrent libraries (arm64: $([ -f "$ARM64_LIBTORRENT" ] && echo "✓" || echo "✗"), x86_64: $([ -f "$X86_64_LIBTORRENT" ] && echo "✓" || echo "✗"))"
fi

echo "✅ Universal macOS binaries created!"
echo "   Universal directory: ${UNIVERSAL_BUILD_ROOT}"
echo "   Boost libraries    : ${UNIVERSAL_BUILD_ROOT}/boost-stage/lib"
echo "   libtorrent library : ${UNIVERSAL_LIBTORRENT}"
