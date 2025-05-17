<#
Build Boost (static, PIC) and libtorrent (static) for Android arm64-v8a.
Outputs go to ./toolchains relative to this script.
#>

param()

# ── config ──────────────────────────────────────────────────────────
$Here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolsDir   = Join-Path $Here 'toolchains'

$BoostSrc   = 'C:\Dev\boost_1_88_0'
$BoostOut   = Join-Path $ToolsDir 'boost-android-arm64'
$LibtPrefix = Join-Path $ToolsDir 'libtorrent-arm64'
$LibtSrc    = 'C:\Dev\libtorrent'

$NDK        = $Env:ANDROID_NDK -replace '"',''
if (-not $NDK) { throw 'ANDROID_NDK is not set' }

$Toolchain  = Join-Path $NDK 'toolchains\llvm\prebuilt\windows-x86_64'
$Clang      = Join-Path $Toolchain 'bin\aarch64-linux-android24-clang++.cmd'
$Ar         = Join-Path $Toolchain 'bin\llvm-ar.exe'
$Jobs       = [Environment]::ProcessorCount
$B2         = Join-Path $BoostSrc 'b2.exe'

# ensure toolchains folder exists
$null = New-Item -Force -ItemType Directory -Path $ToolsDir

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
      <arch>arm           <address-model>64
      <abi>aapcs          <binary-format>elf
      <target-os>android
      <archiver>"$Ar"
;
"@ | Set-Content -Encoding ascii $Jam
$Env:BOOST_BUILD_USER_CONFIG = $Jam

try {
    # ── 2. build Boost (only once) ──────────────────────────────────
    if (-not (Test-Path (Join-Path $BoostOut 'include\boost\config.hpp'))) {

        if (-not (Test-Path $B2)) { & "$BoostSrc\bootstrap.bat" }

        Push-Location $BoostSrc
        & $B2 "-j$Jobs" `
              toolset=clang-android `
              --user-config=$Jam `
              target-os=android architecture=arm address-model=64 `
              cxxstd=17 link=static runtime-link=static threading=multi `
              --with-system --with-atomic `
              --hash install "--prefix=$BoostOut"
        if ($LASTEXITCODE) { throw 'Boost build failed' }
        Pop-Location
    }

    # ── 3. clone libtorrent if needed ───────────────────────────────
    if (-not (Test-Path $LibtSrc)) {
        git clone --branch RC_2_0 --depth 1 https://github.com/arvidn/libtorrent.git $LibtSrc
        if ($LASTEXITCODE) { throw 'git clone failed' }
    }

    # ── 4. build libtorrent (static) ────────────────────────────────
    Push-Location $LibtSrc
    & $B2 "-j$Jobs" `
          toolset=clang-android `
          --user-config=$Jam `
          target-os=android architecture=arm address-model=64 `
          cxxstd=17 link=shared boost-link=static runtime-link=shared `
          crypto=built-in variant=release fpic=on --hash `
          "--prefix=$LibtPrefix" install
    if ($LASTEXITCODE) { throw 'libtorrent build failed' }
    Pop-Location

}
finally {
    # clean up
    # Remove-Item Env:BOOST_BUILD_USER_CONFIG
    Set-Location $Here
}

Write-Host "`nBuild complete."
Write-Host "Boost → $BoostOut"
Write-Host "libtorrent → $LibtPrefix"
