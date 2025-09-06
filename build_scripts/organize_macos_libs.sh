#!/usr/bin/env bash
set -euo pipefail

#
# macOS Library Organizer
# Copies built libraries from toolchain directories to shared/lib structure
#

Here="$(cd "$(dirname "$0")" && pwd)"
ToolsDir="$Here/toolchains"
SharedLibDir="$Here/../shared/lib/macos"

echo "▶︎ Organizing macOS libraries..."

# Universal libraries (preferred)
UNIVERSAL_BUILD_ROOT="${ToolsDir}/build-macos-universal"
if [[ -d "$UNIVERSAL_BUILD_ROOT" ]]; then
    echo "  Using universal libraries from ${UNIVERSAL_BUILD_ROOT}"
    
    # Copy boost libraries
    if [[ -d "${UNIVERSAL_BUILD_ROOT}/boost-stage/lib" ]]; then
        cp "${UNIVERSAL_BUILD_ROOT}/boost-stage/lib"/*.a "${SharedLibDir}/boost/" 2>/dev/null || true
        echo "    ✓ Boost libraries copied"
    fi
    
    # Copy libtorrent library
    if [[ -f "${UNIVERSAL_BUILD_ROOT}/libtorrent-build/libtorrent-rasterbar.a" ]]; then
        cp "${UNIVERSAL_BUILD_ROOT}/libtorrent-build/libtorrent-rasterbar.a" "${SharedLibDir}/"
        echo "    ✓ libtorrent library copied"
    fi
else
    echo "  Universal libraries not found, checking for arm64 libraries..."
    
    # Fallback to arm64 libraries
    ARM64_BUILD_ROOT="${ToolsDir}/build-macos-arm64"
    if [[ -d "$ARM64_BUILD_ROOT" ]]; then
        echo "  Using arm64 libraries from ${ARM64_BUILD_ROOT}"
        
        # Copy boost libraries
        if [[ -d "${ARM64_BUILD_ROOT}/boost-stage/lib" ]]; then
            cp "${ARM64_BUILD_ROOT}/boost-stage/lib"/*.a "${SharedLibDir}/boost/" 2>/dev/null || true
            echo "    ✓ Boost libraries copied (arm64 only)"
        fi
        
        # Copy libtorrent library
        if [[ -f "${ARM64_BUILD_ROOT}/libtorrent-build/libtorrent-rasterbar.a" ]]; then
            cp "${ARM64_BUILD_ROOT}/libtorrent-build/libtorrent-rasterbar.a" "${SharedLibDir}/"
            echo "    ✓ libtorrent library copied (arm64 only)"
        fi
    else
        echo "  ⚠️  No built libraries found. Please build libraries first."
        exit 1
    fi
fi

echo "✅ macOS libraries organized in ${SharedLibDir}"

# List the copied files
echo ""
echo "📋 Libraries in ${SharedLibDir}:"
find "${SharedLibDir}" -name "*.a" -type f | sort
