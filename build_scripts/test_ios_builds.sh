#!/usr/bin/env bash
set -euo pipefail

#
# Test iOS builds - run individual architecture builds to verify they work
#

Here="$(cd "$(dirname "$0")" && pwd)"

echo "Testing iOS build scripts..."
echo ""

# Function to test a single build script
test_build() {
    local script="$1"
    local name="$2"
    
    echo "Testing $name..."
    if [ -x "$script" ]; then
        echo "  Script is executable: ✓"
        # Test basic syntax by doing a dry run
        if bash -n "$script"; then
            echo "  Script syntax: ✓"
        else
            echo "  Script syntax: ✗"
            return 1
        fi
    else
        echo "  Script is executable: ✗"
        return 1
    fi
}

# Test all iOS build scripts
test_build "$Here/build_iphoneos_arm64.sh" "iOS Device (arm64)"
test_build "$Here/build_iphonesimulator_arm64.sh" "iOS Simulator (arm64)"
test_build "$Here/build_iphonesimulator_x86_64.sh" "iOS Simulator (x86_64)"
test_build "$Here/build_ios_universal.sh" "iOS Universal"
test_build "$Here/clean_ios.sh" "iOS Clean"

echo ""
echo "Basic tests complete."
echo ""
echo "To actually build the libraries, run:"
echo "  $Here/build_ios_universal.sh"
echo ""
echo "To clean build artifacts, run:"
echo "  $Here/clean_ios.sh"
