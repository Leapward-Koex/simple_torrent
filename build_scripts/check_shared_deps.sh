#!/bin/bash
# Build script for Simple Torrent Plugin shared dependencies
# This script helps manage the shared torrent_core and dependencies across platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$SCRIPT_DIR/../shared"
THIRD_PARTY_DIR="$SHARED_DIR/third_party"

echo "Simple Torrent Plugin - Shared Dependencies Manager"
echo "=================================================="

# Function to check if a directory exists
check_directory() {
    if [ ! -d "$1" ]; then
        echo "❌ Directory not found: $1"
        return 1
    else
        echo "✅ Directory found: $1"
        return 0
    fi
}

# Function to create directory structure
create_directories() {
    echo "Creating shared directory structure..."
    mkdir -p "$SHARED_DIR/torrent_core"
    mkdir -p "$SHARED_DIR/third_party"
    mkdir -p "$SHARED_DIR/lib/android"
    mkdir -p "$SHARED_DIR/lib/ios"
    mkdir -p "$SHARED_DIR/lib/windows"
    mkdir -p "$SHARED_DIR/lib/linux"
    mkdir -p "$SHARED_DIR/lib/macos"
    echo "✅ Directory structure created"
}

# Function to check shared core
check_shared_core() {
    echo ""
    echo "Checking shared torrent core..."
    
    if check_directory "$SHARED_DIR/torrent_core"; then
        if [ -f "$SHARED_DIR/torrent_core/torrent_core.hpp" ] && [ -f "$SHARED_DIR/torrent_core/torrent_core.cpp" ]; then
            echo "✅ Shared torrent core files found"
        else
            echo "❌ Shared torrent core files missing"
            return 1
        fi
    else
        return 1
    fi
}

# Function to check dependencies
check_dependencies() {
    echo ""
    echo "Checking third-party dependencies..."
    
    if check_directory "$THIRD_PARTY_DIR/libtorrent"; then
        if check_directory "$THIRD_PARTY_DIR/libtorrent/include"; then
            echo "✅ libtorrent headers found"
        else
            echo "❌ libtorrent headers missing"
        fi
    fi
    
    if check_directory "$THIRD_PARTY_DIR/boost"; then
        echo "✅ Boost headers found"
    else
        echo "❌ Boost headers missing"
    fi
}

# Function to check platform-specific libraries
check_platform_libs() {
    echo ""
    echo "Checking platform-specific libraries..."
    
    # Android
    if [ -d "$SHARED_DIR/lib/android" ]; then
        android_libs=$(find "$SHARED_DIR/lib/android" -name "*.so" | wc -l)
        echo "📱 Android: $android_libs shared libraries found"
    fi
    
    # iOS
    if [ -d "$SHARED_DIR/lib/ios" ]; then
        ios_libs=$(find "$SHARED_DIR/lib/ios" -name "*.a" | wc -l)
        echo "🍎 iOS: $ios_libs static libraries found"
    fi
    
    # Windows
    if [ -d "$SHARED_DIR/lib/windows" ]; then
        windows_libs=$(find "$SHARED_DIR/lib/windows" -name "*.lib" -o -name "*.dll" | wc -l)
        echo "🪟 Windows: $windows_libs libraries found"
    fi
    
    # Linux
    if [ -d "$SHARED_DIR/lib/linux" ]; then
        linux_libs=$(find "$SHARED_DIR/lib/linux" -name "*.so" -o -name "*.a" | wc -l)
        echo "🐧 Linux: $linux_libs libraries found"
    fi
    
    # macOS
    if [ -d "$SHARED_DIR/lib/macos" ]; then
        macos_libs=$(find "$SHARED_DIR/lib/macos" -name "*.dylib" -o -name "*.a" | wc -l)
        echo "🍎 macOS: $macos_libs libraries found"
    fi
}

# Function to validate platform configurations
check_platform_configs() {
    echo ""
    echo "Checking platform configurations..."
    
    # Android CMakeLists.txt
    if [ -f "$SCRIPT_DIR/../android/src/main/cpp/CMakeLists.txt" ]; then
        if grep -q "shared/torrent_core" "$SCRIPT_DIR/../android/src/main/cpp/CMakeLists.txt"; then
            echo "✅ Android CMakeLists.txt configured for shared core"
        else
            echo "❌ Android CMakeLists.txt needs shared core configuration"
        fi
    fi
    
    # iOS podspec
    if [ -f "$SCRIPT_DIR/../ios/simple_torrent.podspec" ]; then
        if grep -q "shared/torrent_core" "$SCRIPT_DIR/../ios/simple_torrent.podspec"; then
            echo "✅ iOS podspec configured for shared core"
        else
            echo "❌ iOS podspec needs shared core configuration"
        fi
    fi
    
    # Windows CMakeLists.txt
    if [ -f "$SCRIPT_DIR/../windows/CMakeLists.txt" ]; then
        if grep -q "shared/torrent_core" "$SCRIPT_DIR/../windows/CMakeLists.txt"; then
            echo "✅ Windows CMakeLists.txt configured for shared core"
        else
            echo "❌ Windows CMakeLists.txt needs shared core configuration"
        fi
    fi
}

# Main function
main() {
    case "${1:-check}" in
        "init")
            echo "Initializing shared directory structure..."
            create_directories
            ;;
        "check")
            check_shared_core
            check_dependencies
            check_platform_libs
            check_platform_configs
            ;;
        "help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  check    Check shared dependencies and configuration (default)"
            echo "  init     Initialize shared directory structure"
            echo "  help     Show this help message"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
