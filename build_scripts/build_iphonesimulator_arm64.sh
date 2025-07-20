#!/usr/bin/env bash
set -euo pipefail

#
# iOS Simulator arm64 build script
# Builds Boost and libtorrent for iOS simulator (arm64) using CMake
#

# ── config ──────────────────────────────────────────────────────────
Here="$(cd "$(dirname "$0")" && pwd)"
ToolsDir="$Here/toolchains"

BoostSrc="/Users/scottmacky/Documents/boost_1_88_0"
LibtSrc="/Users/scottmacky/Documents/libtorrent"

# Build configuration
ARCH="arm64"
MIN_IOS_VERSION="12.0"
IOS_SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
BuildRoot="${ToolsDir}/build-ios-sim-${ARCH}"
BOOST_STAGE_LIB="${BuildRoot}/boost-stage/lib"

# CPU cores count
if command -v nproc &>/dev/null; then
    Jobs="$(nproc)"
elif [ "$(uname)" = "Darwin" ]; then
    Jobs="$(sysctl -n hw.ncpu)"
else
    Jobs=4
fi

# Boost build tool
B2="$BoostSrc/b2"

echo "▶︎ Boost source      : $BoostSrc"
echo "▶︎ libtorrent source : $LibtSrc"
echo "▶︎ Build directory   : $BuildRoot"
echo "▶︎ iOS SDK           : $IOS_SDK_PATH"

# ensure build directory exists
mkdir -p "$BuildRoot"
mkdir -p "$BOOST_STAGE_LIB"

# ── 1. build Boost for iOS simulator arm64 ────────────────────────────────
echo "▶︎ Building Boost for iOS Simulator arm64..."

if [ ! -f "$BOOST_STAGE_LIB/libboost_system.a" ]; then
    (cd "$BoostSrc" && \
        "$B2" -j"$Jobs" \
          toolset=clang \
          target-os=iphone architecture=arm address-model=64 \
          cxxstd=17 link=static runtime-link=static threading=multi \
          cflags="-arch ${ARCH} -isysroot ${IOS_SDK_PATH} -mios-simulator-version-min=${MIN_IOS_VERSION}" \
          cxxflags="-arch ${ARCH} -isysroot ${IOS_SDK_PATH} -mios-simulator-version-min=${MIN_IOS_VERSION}" \
          linkflags="-arch ${ARCH} -isysroot ${IOS_SDK_PATH} -mios-simulator-version-min=${MIN_IOS_VERSION}" \
          --with-system --with-atomic --with-thread --with-chrono --with-regex --with-filesystem --with-date_time \
          --stagedir="$BuildRoot/boost-stage" stage
    )
fi

# ── 2. clone libtorrent if missing ─────────────────────────────────────
if [ ! -d "$LibtSrc" ]; then
    git clone --branch RC_2_0 --depth 1 https://github.com/arvidn/libtorrent.git "$LibtSrc"
fi

# ─────────────────────────── Build libtorrent (static) ──────────────────────────
# Help CMake find our iOS-built Boost libraries
export Boost_INCLUDE_DIR="${BoostSrc}"
export Boost_LIBRARY_DIRS="${BOOST_STAGE_LIB}"

cmake -B "${BuildRoot}/libtorrent-build" -S "${LibtSrc}" \
    -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="${IOS_SDK_PATH}" \
    -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MIN_IOS_VERSION}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_CXX_STANDARD=17 \
    -DBoost_INCLUDE_DIR="${BoostSrc}" \
    -DBoost_LIBRARY_DIRS="${BOOST_STAGE_LIB}" \
    -DBoost_NO_SYSTEM_PATHS=ON \
    -DBoost_USE_STATIC_LIBS=ON \
    -DBoost_SYSTEM_LIBRARY="${BOOST_STAGE_LIB}/libboost_system.a" \
    -DBoost_FILESYSTEM_LIBRARY="${BOOST_STAGE_LIB}/libboost_filesystem.a" \
    -DBoost_THREAD_LIBRARY="${BOOST_STAGE_LIB}/libboost_thread.a" \
    -DBoost_CHRONO_LIBRARY="${BOOST_STAGE_LIB}/libboost_chrono.a" \
    -DBoost_ATOMIC_LIBRARY="${BOOST_STAGE_LIB}/libboost_atomic.a" \
    -DBoost_REGEX_LIBRARY="${BOOST_STAGE_LIB}/libboost_regex.a" \
    -DBoost_DATE_TIME_LIBRARY="${BOOST_STAGE_LIB}/libboost_date_time.a" \
    -DBUILD_SHARED_LIBS=OFF \
    -DTORRENT_USE_PIC=ON \
    -DTORRENT_CXX_STANDARD=17 \
    -Wno-dev

cmake --build "${BuildRoot}/libtorrent-build" --target torrent-rasterbar -j"${Jobs}"

# ────────────────────────── Finish & Show output paths ──────────────────────────
BOOST_STAGE_HEADERS="${BoostSrc}"
BOOST_STAGE_LIBS="${BOOST_STAGE_LIB}"
LIBTORRENT_STATIC_LIB="${BuildRoot}/libtorrent-build/libtorrent-rasterbar.a"

echo "✅ Build complete!"
echo "   Boost headers    : ${BOOST_STAGE_HEADERS}"
echo "   Boost libraries  : ${BOOST_STAGE_LIBS}"
echo "   libtorrent lib   : ${LIBTORRENT_STATIC_LIB}"
