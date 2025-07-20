#!/usr/bin/env bash
set -euo pipefail

#
# Build iOS universal libraries for libtorrent and Boost.
# This script builds for all iOS architectures and creates universal binaries.
#

# ── config ──────────────────────────────────────────────────────────
Here="$(cd "$(dirname "$0")" && pwd)"
ToolsDir="$Here/toolchains"
SharedDir="$Here/../shared"

# Final output directories (matching your podspec expectations)
FinalBoostDir="$SharedDir/third_party/boost"
FinalLibtDir="$SharedDir/lib/ios"
FinalLibtDeviceDir="$FinalLibtDir/device"
FinalLibtSimulatorDir="$FinalLibtDir/simulator"
FinalIncludeDir="$SharedDir/third_party/libtorrent/include"

# Individual architecture builds (updated for CMake approach)
DeviceArm64Build="$ToolsDir/build-ios-device-arm64"
SimArm64Build="$ToolsDir/build-ios-sim-arm64" 
SimX86_64Build="$ToolsDir/build-ios-sim-x86_64"

# Boost libraries from staged builds
BoostDeviceLibs="$DeviceArm64Build/boost-stage/lib"
BoostSimArm64Libs="$SimArm64Build/boost-stage/lib"
BoostSimX86_64Libs="$SimX86_64Build/boost-stage/lib"

echo "Building iOS universal libraries for libtorrent..."
echo "Output directories:"
echo "  Boost headers → $FinalBoostDir"
echo "  libtorrent device libs → $FinalLibtDeviceDir"
echo "  libtorrent simulator libs → $FinalLibtSimulatorDir"
echo "  libtorrent headers → $FinalIncludeDir"
echo ""

# ── 1. build all architectures ─────────────────────────────────────
echo "Building iOS device (arm64)..."
"$Here/build_iphoneos_arm64.sh"

echo "Building iOS simulator (arm64)..."
"$Here/build_iphonesimulator_arm64.sh"

echo "Building iOS simulator (x86_64)..."
"$Here/build_iphonesimulator_x86_64.sh"

# ── 2. create output directories ──────────────────────────────────
mkdir -p "$FinalLibtDeviceDir"
mkdir -p "$FinalLibtSimulatorDir"
mkdir -p "$FinalIncludeDir"
mkdir -p "$FinalBoostDir"

# ── 3. copy headers ─────────────────────────────────────────────────
echo "Copying headers..."

# Copy libtorrent headers (use device build as source)
if [ -d "$DeviceArm64Build/libtorrent-build/include/libtorrent" ]; then
    cp -R "$DeviceArm64Build/libtorrent-build/include/"* "$FinalIncludeDir/"
else
    echo "Warning: libtorrent headers not found in $DeviceArm64Build/libtorrent-build/include/"
fi

# Copy Boost headers (use device build as source)
if [ -d "$BoostDeviceLibs/../include/boost" ]; then
    cp -R "$BoostDeviceLibs/../include/"* "$FinalBoostDir/"
else
    echo "Warning: Boost headers not found in $BoostDeviceLibs/../include/"
fi

# ── 4. create device and simulator libraries ────────────────────────────────────
echo "Creating device and simulator libraries..."

# Copy device library (arm64)
DEVICE_LIB="$DeviceArm64Build/libtorrent-build/libtorrent-rasterbar.a"
if [ -f "$DEVICE_LIB" ]; then
    echo "  Copying device library (arm64)..."
    cp "$DEVICE_LIB" "$FinalLibtDeviceDir/libtorrent-rasterbar.a"
    echo "  Device library: $(lipo -info "$FinalLibtDeviceDir/libtorrent-rasterbar.a")"
else
    echo "Error: Device library not found: $DEVICE_LIB"
    exit 1
fi

# Create simulator universal binary (arm64 + x86_64)
SIM_ARM64_LIB="$SimArm64Build/libtorrent-build/libtorrent-rasterbar.a"
SIM_X86_LIB="$SimX86_64Build/libtorrent-build/libtorrent-rasterbar.a"

if [ -f "$SIM_ARM64_LIB" ] && [ -f "$SIM_X86_LIB" ]; then
    echo "  Creating simulator universal binary (arm64 + x86_64)..."
    lipo -create \
        "$SIM_ARM64_LIB" \
        "$SIM_X86_LIB" \
        -output "$FinalLibtSimulatorDir/libtorrent-rasterbar.a"
    
    echo "  Simulator library: $(lipo -info "$FinalLibtSimulatorDir/libtorrent-rasterbar.a")"
else
    echo "Error: One or more simulator libraries not found:"
    echo "  Sim ARM64: $SIM_ARM64_LIB" 
    echo "  Sim x86_64: $SIM_X86_LIB"
    exit 1
fi

# Create device and simulator Boost libraries
echo "  Creating Boost device and simulator libraries..."
BOOST_LIBS=(
    "libboost_system.a"
    "libboost_atomic.a"
    "libboost_thread.a"
    "libboost_chrono.a"
    "libboost_regex.a"
    "libboost_filesystem.a"
    "libboost_date_time.a"
)

# Copy device Boost libraries
mkdir -p "$FinalLibtDeviceDir/boost"
for lib in "${BOOST_LIBS[@]}"; do
    DEVICE_BOOST="$BoostDeviceLibs/$lib"
    if [ -f "$DEVICE_BOOST" ]; then
        cp "$DEVICE_BOOST" "$FinalLibtDeviceDir/boost/$lib"
    else
        echo "    Warning: Device $lib not found, skipping..."
    fi
done

# Create simulator universal Boost libraries
mkdir -p "$FinalLibtSimulatorDir/boost"
for lib in "${BOOST_LIBS[@]}"; do
    SIM_ARM64_BOOST="$BoostSimArm64Libs/$lib"
    SIM_X86_BOOST="$BoostSimX86_64Libs/$lib"
    
    if [ -f "$SIM_ARM64_BOOST" ] && [ -f "$SIM_X86_BOOST" ]; then
        echo "    Creating simulator $lib universal binary..."
        lipo -create \
            "$SIM_ARM64_BOOST" \
            "$SIM_X86_BOOST" \
            -output "$FinalLibtSimulatorDir/boost/$lib"
    else
        echo "    Warning: Simulator $lib not found in all architectures, skipping..."
    fi
done

# ── 5. verify results ────────────────────────────────────────────────
echo ""
echo "Build complete! Device and simulator libraries created:"
echo ""

echo "Device libraries (arm64):"
if [ -f "$FinalLibtDeviceDir/libtorrent-rasterbar.a" ]; then
    echo "✓ libtorrent-rasterbar.a: $(lipo -info "$FinalLibtDeviceDir/libtorrent-rasterbar.a" | cut -d: -f2)"
    echo "  Size: $(du -h "$FinalLibtDeviceDir/libtorrent-rasterbar.a" | cut -f1)"
fi

echo ""
echo "Simulator libraries (arm64 + x86_64):"
if [ -f "$FinalLibtSimulatorDir/libtorrent-rasterbar.a" ]; then
    echo "✓ libtorrent-rasterbar.a: $(lipo -info "$FinalLibtSimulatorDir/libtorrent-rasterbar.a" | cut -d: -f2)"
    echo "  Size: $(du -h "$FinalLibtSimulatorDir/libtorrent-rasterbar.a" | cut -f1)"
fi

echo ""
echo "Boost libraries:"
echo "Device:"
for lib in "${BOOST_LIBS[@]}"; do
    if [ -f "$FinalLibtDeviceDir/boost/$lib" ]; then
        echo "✓ $lib: $(lipo -info "$FinalLibtDeviceDir/boost/$lib" | cut -d: -f2)"
    else
        echo "✗ $lib: not found"
    fi
done

echo "Simulator:"
for lib in "${BOOST_LIBS[@]}"; do
    if [ -f "$FinalLibtSimulatorDir/boost/$lib" ]; then
        echo "✓ $lib: $(lipo -info "$FinalLibtSimulatorDir/boost/$lib" | cut -d: -f2)"
    else
        echo "✗ $lib: not found"
    fi
done

echo ""
echo "Headers:"
if [ -d "$FinalIncludeDir/libtorrent" ]; then
    echo "✓ libtorrent headers: $(find "$FinalIncludeDir" -name "*.hpp" | wc -l | tr -d ' ') files"
else
    echo "✗ libtorrent headers: not found"
fi

if [ -d "$FinalBoostDir/boost" ]; then
    echo "✓ Boost headers: $(find "$FinalBoostDir" -name "*.hpp" | wc -l | tr -d ' ') files"
else
    echo "✗ Boost headers: not found"
fi

echo ""
echo "Your iOS libraries are ready for use in the Flutter plugin!"
echo "Note: Libraries are now separated by platform (device/simulator) due to arm64 architecture overlap."
echo "Update your podspec to use the appropriate libraries for each platform."
