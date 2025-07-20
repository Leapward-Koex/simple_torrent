#!/usr/bin/env bash
set -euo pipefail

#
# Build Boost (static, PIC) and libtorrent (shared) for Android armeabi-v7a.
# Outputs go to the appropriate shared and Android jniLibs directories.
#

# ── config ──────────────────────────────────────────────────────────
Here="$(cd "$(dirname "$0")" && pwd)"
ToolsDir="$Here/toolchains"
SharedDir="$Here/../shared"
AndroidDir="$Here/../android"

# Architecture-specific settings
ABI="armeabi-v7a"
BoostSrc="$HOME/Documents/boost_1_88_0"
LibtSrc="$HOME/Documents/libtorrent"

# Output directories (matching expected structure)
BoostOut="$SharedDir/third_party/boost"
LibtIncludeOut="$SharedDir/third_party/libtorrent/include"
JniLibsOut="$AndroidDir/src/main/jniLibs/$ABI"

# Build directories (temporary)
BoostBuildOut="$ToolsDir/boost-android-$ABI"
LibtPrefix="$ToolsDir/libtorrent-$ABI"

# NDK configuration
NDK="${ANDROID_NDK:-}"
if [ -z "$NDK" ]; then
    echo "Error: ANDROID_NDK environment variable is not set"
    exit 1
fi

Toolchain="$NDK/toolchains/llvm/prebuilt/$(uname -s | tr '[:upper:]' '[:lower:]')-x86_64"
if [ "$(uname)" = "Darwin" ]; then
    Toolchain="$NDK/toolchains/llvm/prebuilt/darwin-x86_64"
fi

Clang="$Toolchain/bin/armv7a-linux-androideabi24-clang++"
Ar="$Toolchain/bin/llvm-ar"

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

echo "▶︎ Building Android $ABI"
echo "▶︎ NDK: $NDK"
echo "▶︎ Boost source: $BoostSrc"
echo "▶︎ libtorrent source: $LibtSrc"
echo "▶︎ Output directories:"
echo "  Boost headers → $BoostOut"
echo "  libtorrent headers → $LibtIncludeOut"
echo "  libtorrent shared lib → $JniLibsOut"

# ensure directories exist
mkdir -p "$ToolsDir"
mkdir -p "$BoostOut"
mkdir -p "$LibtIncludeOut"
mkdir -p "$JniLibsOut"

# ── 1. temporary user-config.jam ────────────────────────────────────
# convert paths for jam (use forward slashes)
ClangJam="$Clang"
ArJam="$Ar"
Jam="$ToolsDir/android-$ABI.jam"

cat > "$Jam" << EOF
using clang : android
    : "$ClangJam"
    : <compileflags>"-fPIC"
      <linkflags>"-fPIC"
      <arch>arm           <address-model>32
      <abi>aapcs          <binary-format>elf
      <target-os>android
      <archiver>"$ArJam"
;
EOF

export BOOST_BUILD_USER_CONFIG="$Jam"

# ── 2. build Boost (only once) ──────────────────────────────────
if [ ! -f "$BoostBuildOut/include/boost/config.hpp" ]; then
    echo "▶︎ Building Boost for Android $ABI..."
    
    if [ ! -f "$B2" ]; then
        (cd "$BoostSrc" && ./bootstrap.sh)
    fi

    (cd "$BoostSrc" && \
        "$B2" -j"$Jobs" \
              toolset=clang-android \
              --user-config="$Jam" \
              target-os=android architecture=arm address-model=32 \
              cxxstd=17 link=static runtime-link=static threading=multi \
              --with-system --with-atomic \
              --hash install --prefix="$BoostBuildOut"
    )
fi

# Copy Boost headers to shared location (only once for all Android ABIs)
if [ ! -f "$BoostOut/boost/config.hpp" ]; then
    echo "▶︎ Copying Boost headers to shared location..."
    cp -R "$BoostBuildOut/include/"* "$BoostOut/"
fi

# ── 3. clone libtorrent if needed ───────────────────────────────
if [ ! -d "$LibtSrc" ]; then
    echo "▶︎ Cloning libtorrent..."
    git clone --branch RC_2_0 --depth 1 https://github.com/arvidn/libtorrent.git "$LibtSrc"
fi

# ── 4. build libtorrent (shared) ────────────────────────────────
echo "▶︎ Building libtorrent for Android $ABI..."
(cd "$LibtSrc" && \
    "$B2" -j"$Jobs" \
          toolset=clang-android \
          --user-config="$Jam" \
          target-os=android architecture=arm address-model=32 \
          cxxstd=17 link=shared boost-link=static runtime-link=shared \
          crypto=built-in variant=release fpic=on --hash \
          --prefix="$LibtPrefix" install
)

# Copy libtorrent shared library to jniLibs
LibtSharedLib="$LibtPrefix/lib/libtorrent-rasterbar.so.2.0.11"
if [ -f "$LibtSharedLib" ]; then
    echo "▶︎ Copying libtorrent shared library to jniLibs..."
    cp "$LibtSharedLib" "$JniLibsOut/"
else
    echo "Error: libtorrent shared library not found at $LibtSharedLib"
    exit 1
fi

# Copy libtorrent headers to shared location (only once for all Android ABIs)
if [ ! -f "$LibtIncludeOut/libtorrent/session.hpp" ]; then
    echo "▶︎ Copying libtorrent headers to shared location..."
    cp -R "$LibtPrefix/include/"* "$LibtIncludeOut/"
fi

echo ""
echo "✅ Build complete for Android $ABI"
echo "   Boost headers → $BoostOut"
echo "   libtorrent headers → $LibtIncludeOut"
echo "   libtorrent shared lib → $JniLibsOut"
