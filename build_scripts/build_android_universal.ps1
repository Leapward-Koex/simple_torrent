<#
Build Android universal libraries for libtorrent and Boost.
This script builds for all Android architectures and organizes output properly.
#>

param()

# ── config ──────────────────────────────────────────────────────────
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$SharedDir = Join-Path $Here '..\shared'
$AndroidDir = Join-Path $Here '..\android'

# Final output directories (matching CMakeLists.txt expectations)
$FinalBoostDir = Join-Path $SharedDir 'third_party\boost'
$FinalLibtIncludeDir = Join-Path $SharedDir 'third_party\libtorrent\include'
$JniLibsBase = Join-Path $AndroidDir 'src\main\jniLibs'

# Supported Android ABIs
$AndroidABIs = @('arm64-v8a', 'armeabi-v7a', 'x86_64')

Write-Host "Building Android universal libraries for libtorrent..."
Write-Host "Output directories:"
Write-Host "  Boost headers → $FinalBoostDir"
Write-Host "  libtorrent headers → $FinalLibtIncludeDir"
Write-Host "  libtorrent shared libs → $JniLibsBase\<abi>\"
Write-Host ""

# ── 1. build all architectures ─────────────────────────────────────
foreach ($ABI in $AndroidABIs) {
    Write-Host "Building Android $ABI..."
    
    switch ($ABI) {
        'arm64-v8a' {
            & "$Here\build_android_arm64-v8a.ps1"
        }
        'armeabi-v7a' {
            & "$Here\build_android_armabi-v7a.ps1"
        }
        'x86_64' {
            & "$Here\build_android_x86_64.ps1"
        }
    }
    
    if ($LASTEXITCODE) {
        throw "Build failed for Android $ABI"
    }
    
    Write-Host "✓ $ABI build complete" -ForegroundColor Green
    Write-Host ""
}

# ── 2. verify output structure ─────────────────────────────────────
Write-Host "Verifying build outputs..."
Write-Host ""

Write-Host "Headers:"
if (Test-Path (Join-Path $FinalLibtIncludeDir 'libtorrent\session.hpp')) {
    $HeaderCount = (Get-ChildItem -Recurse -Filter "*.hpp" -Path $FinalLibtIncludeDir).Count
    Write-Host "✓ libtorrent headers: $HeaderCount files" -ForegroundColor Green
} else {
    Write-Host "✗ libtorrent headers: not found" -ForegroundColor Red
}

if (Test-Path (Join-Path $FinalBoostDir 'boost\config.hpp')) {
    $BoostHeaderCount = (Get-ChildItem -Recurse -Filter "*.hpp" -Path $FinalBoostDir).Count
    Write-Host "✓ Boost headers: $BoostHeaderCount files" -ForegroundColor Green
} else {
    Write-Host "✗ Boost headers: not found" -ForegroundColor Red
}

Write-Host ""
Write-Host "Shared Libraries by ABI:"
foreach ($ABI in $AndroidABIs) {
    $JniLibDir = Join-Path $JniLibsBase $ABI
    $LibtorrentLib = Join-Path $JniLibDir 'libtorrent-rasterbar.so.2.0.11'
    
    if (Test-Path $LibtorrentLib) {
        $Size = [math]::Round((Get-Item $LibtorrentLib).Length / 1MB, 1)
        Write-Host "✓ $ABI" -ForegroundColor Green -NoNewline
        Write-Host ": libtorrent-rasterbar.so.2.0.11 ($Size MB)"
    } else {
        Write-Host "✗ $ABI" -ForegroundColor Red -NoNewline  
        Write-Host ": libtorrent library not found"
    }
}

Write-Host ""
Write-Host "Your Android libraries are ready for use in the Flutter plugin!" -ForegroundColor Green
Write-Host "Libraries are organized by ABI in android/src/main/jniLibs/"
Write-Host "Headers are in shared/third_party/ for CMakeLists.txt to find"
