# Build script for Windows x64 libtorrent
# This script builds libtorrent as a static library for Windows x64

param(
    [string]$Configuration = "Release",
    [string]$BuildType = "Release",
    [switch]$Clean = $false
)

$ErrorActionPreference = "Stop"

# Use BuildType if provided, otherwise use Configuration
if ($BuildType -ne "Release") {
    $Configuration = $BuildType
}

# Script configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptDir
$LibtorrentSource = "c:\Dev\libtorrent"
$BoostSource = "c:\Dev\boost_1_88_0"
$SharedLibDir = Join-Path $ProjectRoot "shared\lib\windows"
$BuildDir = Join-Path $LibtorrentSource "build_windows_x64"

Write-Host "Building libtorrent for Windows x64..." -ForegroundColor Cyan
Write-Host "Configuration: $Configuration" -ForegroundColor Yellow
Write-Host "Build Directory: $BuildDir" -ForegroundColor Yellow
Write-Host "Output Directory: $SharedLibDir" -ForegroundColor Yellow

# Create directories
if (!(Test-Path $SharedLibDir)) {
    New-Item -ItemType Directory -Path $SharedLibDir -Force | Out-Null
    Write-Host "Created output directory: $SharedLibDir" -ForegroundColor Green
}

if ($Clean -and (Test-Path $BuildDir)) {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    Remove-Item -Path $BuildDir -Recurse -Force
}

if (!(Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    Write-Host "Created build directory: $BuildDir" -ForegroundColor Green
}

# Check for required tools
$CmakePath = Get-Command "cmake.exe" -ErrorAction SilentlyContinue
if (!$CmakePath) {
    Write-Error "Required tool 'cmake.exe' not found in PATH. Please install CMake."
    exit 1
}
Write-Host "✓ Found cmake: $($CmakePath.Source)" -ForegroundColor Green

# Find MSBuild in common Visual Studio locations
$MSBuildPaths = @(
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Enterprise\MSBuild\Current\Bin\MSBuild.exe"
)

$MSBuildPath = $null
foreach ($path in $MSBuildPaths) {
    if (Test-Path $path) {
        $MSBuildPath = $path
        break
    }
}

if (!$MSBuildPath) {
    # Try to find via command line
    $MSBuildCmd = Get-Command "msbuild.exe" -ErrorAction SilentlyContinue
    if ($MSBuildCmd) {
        $MSBuildPath = $MSBuildCmd.Source
    }
}

if (!$MSBuildPath) {
    Write-Error "MSBuild not found. Please install Visual Studio 2019 or 2022 with C++ build tools."
    Write-Host "Expected locations:" -ForegroundColor Yellow
    foreach ($path in $MSBuildPaths) {
        Write-Host "  $path" -ForegroundColor Gray
    }
    exit 1
}
Write-Host "✓ Found MSBuild: $MSBuildPath" -ForegroundColor Green

# Check if Boost exists
if (!(Test-Path $BoostSource)) {
    Write-Error "Boost source not found at: $BoostSource"
    Write-Host "Please ensure Boost 1.88.0 is extracted to c:\Dev\boost_1_88_0" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Found Boost source: $BoostSource" -ForegroundColor Green

# Check if libtorrent exists
if (!(Test-Path $LibtorrentSource)) {
    Write-Error "libtorrent source not found at: $LibtorrentSource"
    Write-Host "Please ensure libtorrent source is available at c:\Dev\libtorrent" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Found libtorrent source: $LibtorrentSource" -ForegroundColor Green

try {
    # Configure with CMake
    Write-Host "Configuring CMake..." -ForegroundColor Yellow
    
    Push-Location $BuildDir
    
    $CMakeArgs = @(
        "-G", "Visual Studio 17 2022"
        "-A", "x64"
        "-DCMAKE_BUILD_TYPE=$Configuration"
        "-DCMAKE_CXX_STANDARD=17"
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
        "-DBUILD_SHARED_LIBS=OFF"  # Build static library
        "-Ddeprecated-functions=OFF"
        "-Dencryption=OFF"  # Disable OpenSSL requirement
        "-Ddht=ON"
        "-Dextensions=ON"
        "-Dlogging=ON"
        "-Dpython-bindings=OFF"
        "-Dtests=OFF"
        "-Dexamples=OFF"
        "-Dtools=OFF"
        "-DBoost_ROOT=$BoostSource"
        "-DBoost_USE_STATIC_LIBS=ON"
        "-DCMAKE_INSTALL_PREFIX=$SharedLibDir"
        "$LibtorrentSource"
    )
    
    & cmake @CMakeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed with exit code $LASTEXITCODE"
    }
    
    Write-Host "✓ CMake configuration successful" -ForegroundColor Green
    
    # Build the library
    Write-Host "Building libtorrent..." -ForegroundColor Yellow
    
    & cmake --build . --config $Configuration --parallel
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE"
    }
    
    Write-Host "✓ Build successful" -ForegroundColor Green
    
    # Install to shared location
    Write-Host "Installing to shared location..." -ForegroundColor Yellow
    
    & cmake --install . --config $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Install failed with exit code $LASTEXITCODE"
    }
    
    Write-Host "✓ Install successful" -ForegroundColor Green
    
    # Verify the output files
    $ExpectedFiles = @(
        "lib\torrent-rasterbar.lib",
        "include\libtorrent\version.hpp"
    )
    
    $AllFilesExist = $true
    foreach ($file in $ExpectedFiles) {
        $fullPath = Join-Path $SharedLibDir $file
        if (Test-Path $fullPath) {
            Write-Host "✓ Found: $file" -ForegroundColor Green
        } else {
            Write-Host "✗ Missing: $file" -ForegroundColor Red
            $AllFilesExist = $false
        }
    }
    
    if ($AllFilesExist) {
        Write-Host "`n🎉 Build completed successfully!" -ForegroundColor Cyan
        Write-Host "Libraries installed to: $SharedLibDir" -ForegroundColor Green
        
        # Show library info
        $LibFile = Join-Path $SharedLibDir "lib\torrent-rasterbar.lib"
        if (Test-Path $LibFile) {
            $LibInfo = Get-Item $LibFile
            Write-Host "Library size: $([math]::Round($LibInfo.Length / 1MB, 2)) MB" -ForegroundColor Blue
        }
    } else {
        Write-Host "`n❌ Some expected files are missing from the build output" -ForegroundColor Red
        exit 1
    }

} catch {
    Write-Host "`n❌ Build failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if (Get-Location | Where-Object {$_.Path -ne $env:USERPROFILE}) {
        Pop-Location
    }
}Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Update the Windows CMakeLists.txt to link against the built library" -ForegroundColor White
Write-Host "2. Test the Windows plugin build with: flutter build windows" -ForegroundColor White
