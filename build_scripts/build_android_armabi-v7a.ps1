<#
Build Boost (static, PIC) and libtorrent (shared) for Android armeabi-v7a.
Outputs go to the appropriate shared and Android jniLibs directories.
#>

param()

# ── config ──────────────────────────────────────────────────────────
$Here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolsDir   = Join-Path $Here 'toolchains'
$SharedDir  = Join-Path $Here '..\shared'
$AndroidDir = Join-Path $Here '..\android'

# Architecture-specific settings
$ABI        = 'armeabi-v7a'
$BoostSrc   = 'C:\Dev\boost_1_88_0'
$LibtSrc    = 'C:\Dev\libtorrent'

# Output directories (matching expected structure)
$BoostOut      = Join-Path $SharedDir 'third_party\boost'
$LibtIncludeOut = Join-Path $SharedDir 'third_party\libtorrent\include'
$JniLibsOut    = Join-Path $AndroidDir "src\main\jniLibs\$ABI"

# Build directories (temporary)
$BoostBuildOut = Join-Path $ToolsDir "boost-android-$ABI"
$LibtPrefix    = Join-Path $ToolsDir "libtorrent-$ABI"

$NDK        = $Env:ANDROID_NDK -replace '"',''
if (-not $NDK) { throw 'ANDROID_NDK is not set' }

$Toolchain  = Join-Path $NDK 'toolchains\llvm\prebuilt\windows-x86_64'
$Clang      = Join-Path $Toolchain 'bin\armv7a-linux-androideabi24-clang++.cmd'
$Ar         = Join-Path $Toolchain 'bin\llvm-ar.exe'
$Jobs       = [Environment]::ProcessorCount
$B2         = Join-Path $BoostSrc 'b2.exe'

# ensure toolchains folder exists
$null = New-Item -Force -ItemType Directory -Path $ToolsDir
$null = New-Item -Force -ItemType Directory -Path $BoostOut
$null = New-Item -Force -ItemType Directory -Path $LibtIncludeOut  
$null = New-Item -Force -ItemType Directory -Path $JniLibsOut

# ── 1. temporary user-config.jam ────────────────────────────────────
# convert back-slashes to forward-slashes for jam
$Clang = $Clang.Replace('\','/')
$Ar    = $Ar.Replace('\','/')
$Jam = Join-Path $ToolsDir 'android-arm64.jam'
@"
using clang : android
    : "$Clang"
    : <compileflags>"-fPIC"
      <linkflags>"-fPIC"
      <arch>arm           <address-model>32
      <abi>aapcs          <binary-format>elf
      <target-os>android
      <archiver>"$Ar"
;
"@ | Set-Content -Encoding ascii $Jam
$Env:BOOST_BUILD_USER_CONFIG = $Jam

try {
    # ── 2. build Boost (only once) ──────────────────────────────────
    if (-not (Test-Path (Join-Path $BoostBuildOut 'include\boost\config.hpp'))) {

        if (-not (Test-Path $B2)) { & "$BoostSrc\bootstrap.bat" }

        Push-Location $BoostSrc
        & $B2 "-j$Jobs" `
              toolset=clang-android `
              --user-config=$Jam `
              target-os=android architecture=arm address-model=32 `
              cxxstd=17 link=static runtime-link=static threading=multi `
              --with-system --with-atomic `
              --hash install "--prefix=$BoostBuildOut"
        if ($LASTEXITCODE) { throw 'Boost build failed' }
        Pop-Location
    }

    # Copy Boost headers to shared location (only once for all Android ABIs)
    if (-not (Test-Path (Join-Path $BoostOut 'boost\config.hpp'))) {
        Write-Host "Copying Boost headers to shared location..."
        Copy-Item -Recurse -Force (Join-Path $BoostBuildOut 'include\*') $BoostOut
    }

    # ── 3. clone libtorrent if needed ───────────────────────────────
    if (-not (Test-Path $LibtSrc)) {
        git clone --branch RC_2_0 --depth 1 https://github.com/arvidn/libtorrent.git $LibtSrc
        if ($LASTEXITCODE) { throw 'git clone failed' }
    }

    # ── 4. build libtorrent (shared) ────────────────────────────────
    Push-Location $LibtSrc
    & $B2 "-j$Jobs" `
          toolset=clang-android `
          --user-config=$Jam `
          target-os=android architecture=arm address-model=32 `
          cxxstd=17 link=shared boost-link=static runtime-link=shared `
          crypto=built-in variant=release fpic=on --hash `
          "--prefix=$LibtPrefix" install
    if ($LASTEXITCODE) { throw 'libtorrent build failed' }
    Pop-Location

    # Copy libtorrent shared library to jniLibs
    $LibtSharedLib = Join-Path $LibtPrefix 'lib\libtorrent-rasterbar.so.2.0.11'
    if (Test-Path $LibtSharedLib) {
        Write-Host "Copying libtorrent shared library to jniLibs..."
        Copy-Item $LibtSharedLib $JniLibsOut
    } else {
        throw "libtorrent shared library not found at $LibtSharedLib"
    }

    # Copy libtorrent headers to shared location (only once for all Android ABIs) 
    if (-not (Test-Path (Join-Path $LibtIncludeOut 'libtorrent\session.hpp'))) {
        Write-Host "Copying libtorrent headers to shared location..."
        Copy-Item -Recurse -Force (Join-Path $LibtPrefix 'include\*') $LibtIncludeOut
    }

}
finally {
    # clean up
    # Remove-Item Env:BOOST_BUILD_USER_CONFIG
    Set-Location $Here
}

Write-Host "`nBuild complete for Android $ABI."
Write-Host "Boost headers → $BoostOut"
Write-Host "libtorrent headers → $LibtIncludeOut"
Write-Host "libtorrent shared lib → $JniLibsOut"
