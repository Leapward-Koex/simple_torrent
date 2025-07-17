# Build script for Simple Torrent Plugin shared dependencies
# This script helps manage the shared torrent_core and dependencies across platforms

param(
    [string]$Command = "check"
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SharedDir = Join-Path $ScriptDir "..\shared"
$ThirdPartyDir = Join-Path $SharedDir "third_party"

Write-Host "Simple Torrent Plugin - Shared Dependencies Manager" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Function to check if a directory exists
function Test-DirectoryExists {
    param([string]$Path)
    
    if (Test-Path -Path $Path -PathType Container) {
        Write-Host "✅ Directory found: $Path" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "❌ Directory not found: $Path" -ForegroundColor Red
        return $false
    }
}

# Function to create directory structure
function Initialize-Directories {
    Write-Host "Creating shared directory structure..." -ForegroundColor Yellow
    
    $Directories = @(
        "$SharedDir\torrent_core",
        "$SharedDir\third_party",
        "$SharedDir\lib\android",
        "$SharedDir\lib\ios", 
        "$SharedDir\lib\windows",
        "$SharedDir\lib\linux",
        "$SharedDir\lib\macos"
    )
    
    foreach ($Dir in $Directories) {
        if (!(Test-Path -Path $Dir)) {
            New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        }
    }
    
    Write-Host "✅ Directory structure created" -ForegroundColor Green
}

# Function to check shared core
function Test-SharedCore {
    Write-Host ""
    Write-Host "Checking shared torrent core..." -ForegroundColor Yellow
    
    $TorrentCoreDir = Join-Path $SharedDir "torrent_core"
    
    if (Test-DirectoryExists -Path $TorrentCoreDir) {
        $HeaderFile = Join-Path $TorrentCoreDir "torrent_core.hpp"
        $SourceFile = Join-Path $TorrentCoreDir "torrent_core.cpp"
        
        if ((Test-Path $HeaderFile) -and (Test-Path $SourceFile)) {
            Write-Host "✅ Shared torrent core files found" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "❌ Shared torrent core files missing" -ForegroundColor Red
            return $false
        }
    }
    else {
        return $false
    }
}

# Function to check dependencies
function Test-Dependencies {
    Write-Host ""
    Write-Host "Checking third-party dependencies..." -ForegroundColor Yellow
    
    $LibTorrentDir = Join-Path $ThirdPartyDir "libtorrent"
    $LibTorrentInclude = Join-Path $LibTorrentDir "include"
    
    if (Test-DirectoryExists -Path $LibTorrentDir) {
        if (Test-DirectoryExists -Path $LibTorrentInclude) {
            Write-Host "✅ libtorrent headers found" -ForegroundColor Green
        }
        else {
            Write-Host "❌ libtorrent headers missing" -ForegroundColor Red
        }
    }
    
    $BoostDir = Join-Path $ThirdPartyDir "boost"
    if (Test-DirectoryExists -Path $BoostDir) {
        Write-Host "✅ Boost headers found" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Boost headers missing" -ForegroundColor Red
    }
}

# Function to check platform-specific libraries
function Test-PlatformLibraries {
    Write-Host ""
    Write-Host "Checking platform-specific libraries..." -ForegroundColor Yellow
    
    # Android
    $AndroidLibDir = Join-Path $SharedDir "lib\android"
    if (Test-Path $AndroidLibDir) {
        $AndroidLibs = @(Get-ChildItem -Path $AndroidLibDir -Filter "*.so" -Recurse).Count
        Write-Host "📱 Android: $AndroidLibs shared libraries found" -ForegroundColor Blue
    }
    
    # iOS
    $iOSLibDir = Join-Path $SharedDir "lib\ios"
    if (Test-Path $iOSLibDir) {
        $iOSLibs = @(Get-ChildItem -Path $iOSLibDir -Filter "*.a" -Recurse).Count
        Write-Host "🍎 iOS: $iOSLibs static libraries found" -ForegroundColor Blue
    }
    
    # Windows
    $WindowsLibDir = Join-Path $SharedDir "lib\windows"
    if (Test-Path $WindowsLibDir) {
        $WindowsLibs = @(Get-ChildItem -Path $WindowsLibDir -Include "*.lib", "*.dll" -Recurse).Count
        Write-Host "🪟 Windows: $WindowsLibs libraries found" -ForegroundColor Blue
    }
    
    # Linux
    $LinuxLibDir = Join-Path $SharedDir "lib\linux"
    if (Test-Path $LinuxLibDir) {
        $LinuxLibs = @(Get-ChildItem -Path $LinuxLibDir -Include "*.so", "*.a" -Recurse).Count
        Write-Host "🐧 Linux: $LinuxLibs libraries found" -ForegroundColor Blue
    }
    
    # macOS
    $macOSLibDir = Join-Path $SharedDir "lib\macos"
    if (Test-Path $macOSLibDir) {
        $macOSLibs = @(Get-ChildItem -Path $macOSLibDir -Include "*.dylib", "*.a" -Recurse).Count
        Write-Host "🍎 macOS: $macOSLibs libraries found" -ForegroundColor Blue
    }
}

# Function to validate platform configurations
function Test-PlatformConfigurations {
    Write-Host ""
    Write-Host "Checking platform configurations..." -ForegroundColor Yellow
    
    # Android CMakeLists.txt
    $AndroidCMake = Join-Path $ScriptDir "..\android\src\main\cpp\CMakeLists.txt"
    if (Test-Path $AndroidCMake) {
        $Content = Get-Content $AndroidCMake -Raw
        if ($Content -match "SHARED_ROOT.*torrent_core" -or $Content -match "\$\{SHARED_ROOT\}/torrent_core") {
            Write-Host "✅ Android CMakeLists.txt configured for shared core" -ForegroundColor Green
        }
        else {
            Write-Host "❌ Android CMakeLists.txt needs shared core configuration" -ForegroundColor Red
        }
    }
    
    # iOS podspec
    $iOSPodspec = Join-Path $ScriptDir "..\ios\simple_torrent.podspec"
    if (Test-Path $iOSPodspec) {
        $Content = Get-Content $iOSPodspec -Raw
        if ($Content -match "shared/torrent_core") {
            Write-Host "✅ iOS podspec configured for shared core" -ForegroundColor Green
        }
        else {
            Write-Host "❌ iOS podspec needs shared core configuration" -ForegroundColor Red
        }
    }
    
    # Windows CMakeLists.txt
    $WindowsCMake = Join-Path $ScriptDir "..\windows\CMakeLists.txt"
    if (Test-Path $WindowsCMake) {
        $Content = Get-Content $WindowsCMake -Raw
        if ($Content -match "SHARED_ROOT.*torrent_core" -or $Content -match "\$\{SHARED_ROOT\}/torrent_core") {
            Write-Host "✅ Windows CMakeLists.txt configured for shared core" -ForegroundColor Green
        }
        else {
            Write-Host "❌ Windows CMakeLists.txt needs shared core configuration" -ForegroundColor Red
        }
    }
}

# Main execution
switch ($Command.ToLower()) {
    "init" {
        Write-Host "Initializing shared directory structure..." -ForegroundColor Yellow
        Initialize-Directories
    }
    "check" {
        Test-SharedCore
        Test-Dependencies
        Test-PlatformLibraries
        Test-PlatformConfigurations
    }
    "help" {
        Write-Host "Usage: .\check_shared_deps.ps1 [command]" -ForegroundColor White
        Write-Host ""
        Write-Host "Commands:" -ForegroundColor White
        Write-Host "  check    Check shared dependencies and configuration (default)" -ForegroundColor Gray
        Write-Host "  init     Initialize shared directory structure" -ForegroundColor Gray
        Write-Host "  help     Show this help message" -ForegroundColor Gray
    }
    default {
        Write-Host "Unknown command: $Command" -ForegroundColor Red
        Write-Host "Use '.\check_shared_deps.ps1 help' for usage information" -ForegroundColor Yellow
        exit 1
    }
}
