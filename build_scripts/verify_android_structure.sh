#!/usr/bin/env bash
set -euo pipefail

#
# Verify Android build output structure
# This script checks that the Android build outputs are in the correct locations
#

Here="$(cd "$(dirname "$0")" && pwd)"
SharedDir="$Here/../shared"
AndroidDir="$Here/../android"

echo "Verifying Android build output structure..."
echo ""

# Expected locations
BoostHeaders="$SharedDir/third_party/boost"
LibtorrentHeaders="$SharedDir/third_party/libtorrent/include"
JniLibsBase="$AndroidDir/src/main/jniLibs"

# Android ABIs to check
ABIs=("arm64-v8a" "armeabi-v7a" "x86_64")

# Check headers
echo "=== HEADERS ==="
if [ -f "$BoostHeaders/boost/config.hpp" ]; then
    echo "✓ Boost headers found at: $BoostHeaders"
    echo "  Files: $(find "$BoostHeaders" -name "*.hpp" | wc -l | tr -d ' ')"
else
    echo "✗ Boost headers missing at: $BoostHeaders"
fi

if [ -f "$LibtorrentHeaders/libtorrent/session.hpp" ]; then
    echo "✓ libtorrent headers found at: $LibtorrentHeaders"
    echo "  Files: $(find "$LibtorrentHeaders" -name "*.hpp" | wc -l | tr -d ' ')"
else
    echo "✗ libtorrent headers missing at: $LibtorrentHeaders"
fi

echo ""
echo "=== SHARED LIBRARIES ==="

# Check shared libraries by ABI
for ABI in "${ABIs[@]}"; do
    JniLibDir="$JniLibsBase/$ABI"
    echo "Checking $ABI:"
    
    if [ -d "$JniLibDir" ]; then
        # Check for versioned library (expected by CMakeLists.txt)
        if [ -f "$JniLibDir/libtorrent-rasterbar.so.2.0.11" ]; then
            if command -v stat >/dev/null 2>&1; then
                if [ "$(uname)" = "Darwin" ]; then
                    Size=$(stat -f%z "$JniLibDir/libtorrent-rasterbar.so.2.0.11")
                else
                    Size=$(stat -c%s "$JniLibDir/libtorrent-rasterbar.so.2.0.11")
                fi
                SizeMB=$(echo "scale=1; $Size / 1024 / 1024" | bc 2>/dev/null || echo "N/A")
                echo "  ✓ libtorrent-rasterbar.so.2.0.11 (${SizeMB} MB)"
            else
                echo "  ✓ libtorrent-rasterbar.so.2.0.11"
            fi
        else
            echo "  ✗ libtorrent-rasterbar.so.2.0.11 missing"
        fi
        
        # Check for other library (convenience symlink)
        if [ -f "$JniLibDir/libtorrent-rasterbar.so" ]; then
            echo "  ✓ libtorrent-rasterbar.so (symlink/copy)"
        else
            echo "  - libtorrent-rasterbar.so not present"
        fi
        
        # Check for C++ shared library
        if [ -f "$JniLibDir/libc++_shared.so" ]; then
            echo "  ✓ libc++_shared.so"
        else
            echo "  - libc++_shared.so not present"
        fi
    else
        echo "  ✗ Directory missing: $JniLibDir"
    fi
    echo ""
done

echo "=== CMAKE EXPECTATIONS ==="
echo "CMakeLists.txt expects:"
echo "  - Boost headers at: SHARED_ROOT/third_party/boost"
echo "  - libtorrent headers at: SHARED_ROOT/third_party/libtorrent/include"
echo "  - libtorrent library at: jniLibs/\${ANDROID_ABI}/libtorrent-rasterbar.so.2.0.11"
echo ""

# Check if CMakeLists.txt can find what it needs
echo "=== COMPATIBILITY CHECK ==="
SHARED_ROOT="$SharedDir"
LIBTORRENT_ROOT="$SHARED_ROOT/third_party/libtorrent"
BOOST_ROOT="$SHARED_ROOT/third_party/boost"

echo "Checking CMakeLists.txt compatibility:"
echo "SHARED_ROOT=$SHARED_ROOT"
echo "LIBTORRENT_ROOT=$LIBTORRENT_ROOT"
echo "BOOST_ROOT=$BOOST_ROOT"
echo ""

if [ -d "$LIBTORRENT_ROOT/include" ]; then
    echo "✓ LIBTORRENT_ROOT/include exists"
else
    echo "✗ LIBTORRENT_ROOT/include missing"
fi

if [ -d "$BOOST_ROOT" ]; then
    echo "✓ BOOST_ROOT exists"
else
    echo "✗ BOOST_ROOT missing"
fi

for ABI in "${ABIs[@]}"; do
    LibPath="$AndroidDir/src/main/jniLibs/$ABI/libtorrent-rasterbar.so.2.0.11"
    if [ -f "$LibPath" ]; then
        echo "✓ $ABI library path exists"
    else
        echo "✗ $ABI library path missing"
    fi
done

echo ""
echo "Verification complete!"
