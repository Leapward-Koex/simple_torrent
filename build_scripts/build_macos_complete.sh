#!/usr/bin/env bash
set -euo pipefail

#
# Complete macOS Build Script
# Builds arm64, x86_64, and universal libraries for macOS
#

Here="$(cd "$(dirname "$0")" && pwd)"

echo "🚀 Starting complete macOS build process..."

# Build arm64 libraries
echo ""
echo "1️⃣ Building arm64 libraries..."
"$Here/build_macos_arm64.sh"

# Build x86_64 libraries
echo ""
echo "2️⃣ Building x86_64 libraries..."
"$Here/build_macos_x86_64.sh"

# Create universal libraries
echo ""
echo "3️⃣ Creating universal libraries..."
"$Here/build_macos_universal.sh"

# Organize libraries for Flutter plugin
echo ""
echo "4️⃣ Organizing libraries for Flutter plugin..."
"$Here/organize_macos_libs.sh"

echo ""
echo "✅ Complete macOS build finished!"
echo "   Libraries are ready for use in the Flutter plugin."
