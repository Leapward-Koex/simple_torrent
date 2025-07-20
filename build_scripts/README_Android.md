# Android Build Scripts for simple_torrent

This directory contains scripts to build libtorrent and Boost libraries for Android.

## Quick Start

### For macOS/Linux (recommended):

```bash
./build_android_universal.sh
```

### For Windows:

```powershell
.\build_android_universal.ps1
```

This will:
1. Build for Android arm64-v8a (64-bit ARM)
2. Build for Android armeabi-v7a (32-bit ARM)
3. Build for Android x86_64 (64-bit x86)
4. Copy headers to shared location for CMakeLists.txt
5. Copy shared libraries to appropriate jniLibs directories

## Individual Architecture Builds

### For macOS/Linux:

```bash
./build_android_arm64-v8a.sh      # Android arm64-v8a (most common)
./build_android_armabi-v7a.sh     # Android armeabi-v7a (legacy)  
./build_android_x86_64.sh         # Android x86_64 (emulator)
```

### For Windows:

```powershell
.\build_android_arm64-v8a.ps1      # Android arm64-v8a (most common)
.\build_android_armabi-v7a.ps1     # Android armeabi-v7a (legacy)  
.\build_android_x86_64.ps1         # Android x86_64 (emulator)
```

## Prerequisites

### For macOS/Linux:

Before running these scripts, ensure you have:

1. **Android NDK** - Set `ANDROID_NDK` environment variable
2. **Boost source** - Located at `$HOME/Documents/boost_1_88_0` (or update script paths)
3. **libtorrent source** - Will be cloned automatically to `$HOME/Documents/libtorrent`
4. **bash** - Scripts are written for bash shell

### For Windows:

Before running these scripts, ensure you have:

1. **Android NDK** - Set `ANDROID_NDK` environment variable
2. **Boost source** - Located at `C:\Dev\boost_1_88_0` (or update script paths)
3. **libtorrent source** - Will be cloned automatically to `C:\Dev\libtorrent`
4. **PowerShell** - Scripts are written for Windows PowerShell

### Environment Setup

#### macOS/Linux:

```bash
# Set Android NDK path
export ANDROID_NDK="$HOME/Library/Android/sdk/ndk/29.0.13113456"

# Verify NDK is found
if [ -d "$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64" ]; then
    echo "NDK found: $ANDROID_NDK"
else
    echo "NDK not found. Please set ANDROID_NDK correctly."
fi
```

#### Windows:

```powershell
# Set Android NDK path
$env:ANDROID_NDK = "C:\Users\YourUser\AppData\Local\Android\Sdk\ndk\29.0.13113456"

# Verify NDK is found
if (Test-Path "$env:ANDROID_NDK\toolchains\llvm\prebuilt\windows-x86_64") {
    Write-Host "NDK found: $env:ANDROID_NDK"
} else {
    Write-Host "NDK not found. Please set ANDROID_NDK correctly."
}
```

## Output Structure

The build scripts create the following structure:

```
shared/
├── third_party/
│   ├── boost/                       # Boost headers (shared across ABIs)
│   │   └── boost/
│   │       ├── config.hpp
│   │       └── ...
│   └── libtorrent/
│       └── include/                 # libtorrent headers (shared across ABIs)
│           └── libtorrent/
│               ├── session.hpp
│               └── ...
android/
└── src/
    └── main/
        └── jniLibs/                 # Native libraries by ABI
            ├── arm64-v8a/
            │   └── libtorrent-rasterbar.so.2.0.11
            ├── armeabi-v7a/
            │   └── libtorrent-rasterbar.so.2.0.11
            └── x86_64/
                └── libtorrent-rasterbar.so.2.0.11
```

## Configuration

### macOS/Linux Scripts

Each bash script has configurable paths at the top:

```bash
BoostSrc="$HOME/Documents/boost_1_88_0"    # Boost source location
LibtSrc="$HOME/Documents/libtorrent"       # libtorrent source (auto-cloned)
```

### Windows Scripts

Each PowerShell script has configurable paths at the top:

```powershell
$BoostSrc   = 'C:\Dev\boost_1_88_0'    # Boost source location
$LibtSrc    = 'C:\Dev\libtorrent'      # libtorrent source (auto-cloned)
```

Update these paths if your development environment differs.

## Build Details

- **Boost**: Built as static libraries with PIC (Position Independent Code)
- **libtorrent**: Built as shared libraries (.so files) 
- **C++ Standard**: C++17
- **Linking**: Boost static, libtorrent shared, runtime shared
- **Variant**: Release builds for performance

## Troubleshooting

### Common Issues

1. **NDK not found**: Ensure `ANDROID_NDK` environment variable points to your NDK installation
2. **Boost not found**: Update `$BoostSrc` path in scripts to match your Boost installation
3. **Build failures**: Check that you have the correct NDK version (29.0.13113456 recommended)
4. **Permission errors**: Run PowerShell as Administrator if needed

### Verifying Output

After building, verify libraries exist:

#### macOS/Linux:

```bash
# Check if libraries were created
find ./android/src/main/jniLibs -name "*.so"

# Check if headers were copied
test -f "./shared/third_party/boost/boost/config.hpp" && echo "Boost headers found"
test -f "./shared/third_party/libtorrent/include/libtorrent/session.hpp" && echo "libtorrent headers found"
```

#### Windows:

```powershell
# Check if libraries were created
Get-ChildItem ".\android\src\main\jniLibs" -Recurse -Filter "*.so"

# Check if headers were copied
Test-Path ".\shared\third_party\boost\boost\config.hpp"
Test-Path ".\shared\third_party\libtorrent\include\libtorrent\session.hpp"
```

## Integration with Flutter

The CMakeLists.txt in `android/src/main/cpp/` is configured to find libraries and headers in the locations these scripts output to:

- Headers: `shared/third_party/boost` and `shared/third_party/libtorrent/include`
- Libraries: `android/src/main/jniLibs/${ANDROID_ABI}/libtorrent-rasterbar.so.2.0.11`

No additional configuration should be needed after running the build scripts.
