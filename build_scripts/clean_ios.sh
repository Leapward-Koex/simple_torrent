#!/usr/bin/env bash
set -euo pipefail

#
# Clean iOS build artifacts
#

Here="$(cd "$(dirname "$0")" && pwd)"
ToolsDir="$Here/toolchains"
SharedDir="$Here/../shared"

echo "Cleaning iOS build artifacts..."

# Remove individual architecture builds
echo "Removing architecture-specific builds..."
rm -rf "$ToolsDir/boost-iphoneos-arm64"
rm -rf "$ToolsDir/boost-iphonesim-arm64"
rm -rf "$ToolsDir/boost-iphonesim-x86_64"
rm -rf "$ToolsDir/libtorrent-iphoneos-arm64"
rm -rf "$ToolsDir/libtorrent-iphonesim-arm64"
rm -rf "$ToolsDir/libtorrent-iphonesim-x86_64"

# Remove temporary jam files
echo "Removing temporary config files..."
rm -f "$ToolsDir/ios-dev-arm64.jam"
rm -f "$ToolsDir/iphonesim-arm64.jam"
rm -f "$ToolsDir/iphonesim-x86_64.jam"

# Remove final output (optional - uncomment if you want to clean these too)
# echo "Removing final libraries..."
# rm -rf "$SharedDir/lib/ios"
# rm -rf "$SharedDir/third_party/libtorrent"
# rm -rf "$SharedDir/third_party/boost"

echo "iOS build artifacts cleaned."
