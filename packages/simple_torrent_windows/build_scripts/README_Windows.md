# Windows Build Instructions

This document describes how to build the native Windows plugin for Simple Torrent.

## Prerequisites

### Required Software
- **Visual Studio 2022** with C++ build tools
- **CMake 3.14+** (included with Visual Studio)
- **Flutter SDK** (for testing)

### Required Dependencies
- **Boost 1.88.0** extracted to `c:\Dev\boost_1_88_0`
- **libtorrent** source code at `c:\Dev\libtorrent`

## Building libtorrent for Windows

### Option 1: Using PowerShell Script (Recommended)
```powershell
cd c:\Dev\simple_torrent\build_scripts
.\build_windows_x64.ps1 -Configuration Release
```

### Option 2: Manual CMake Build
```powershell
# Create build directory
mkdir c:\Dev\libtorrent\build_windows_x64
cd c:\Dev\libtorrent\build_windows_x64

# Configure with CMake
cmake -G "Visual Studio 17 2022" -A x64 ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CXX_STANDARD=17 ^
  -DBUILD_SHARED_LIBS=OFF ^
  -Ddeprecated-functions=OFF ^
  -Dencryption=ON ^
  -Ddht=ON ^
  -Dextensions=ON ^
  -Dlogging=ON ^
  -Dpython-bindings=OFF ^
  -Dtests=OFF ^
  -Dexamples=OFF ^
  -Dtools=OFF ^
  -DBoost_ROOT=c:\Dev\boost_1_88_0 ^
  -DBoost_USE_STATIC_LIBS=ON ^
  -DCMAKE_INSTALL_PREFIX=c:\Dev\simple_torrent\shared\lib\windows ^
  ..

# Build and install
cmake --build . --config Release --parallel
cmake --install . --config Release
```

## Build Configuration Options

### Release Build (Default)
```powershell
.\build_windows_x64.ps1 -Configuration Release
```

### Debug Build
```powershell
.\build_windows_x64.ps1 -Configuration Debug
```

### Clean Build
```powershell
.\build_windows_x64.ps1 -Configuration Release -Clean
```

## Expected Output

After a successful build, you should have:

```
shared/lib/windows/
├── lib/
│   └── torrent-rasterbar.lib    # Static library (~50-100MB)
├── include/
│   └── libtorrent/              # Header files
│       ├── version.hpp
│       ├── session.hpp
│       └── ... (other headers)
└── bin/                         # (if any executables were built)
```

## Testing the Plugin

### Build the Example App
```powershell
cd c:\Dev\simple_torrent\example
flutter clean
flutter build windows --debug
```

### Run the Example App
```powershell
cd c:\Dev\simple_torrent\example
flutter run -d windows
```

## Common Issues

### Issue: CMake not found
**Solution**: Install Visual Studio 2022 with "C++ CMake tools" workload, or install CMake separately.

### Issue: Boost not found
**Solution**: 
1. Download Boost 1.88.0 from https://www.boost.org/
2. Extract to `c:\Dev\boost_1_88_0`
3. No need to build Boost - headers only are sufficient

### Issue: Visual Studio version mismatch
**Solution**: Update the generator in the build script:
- For VS 2019: Change to `"Visual Studio 16 2019"`
- For VS 2022: Use `"Visual Studio 17 2022"` (default)

### Issue: Build fails with linking errors
**Solution**: 
1. Ensure you're using the same runtime library (MT/MD) across all components
2. Check that Boost and libtorrent are built with the same configuration
3. Try a clean rebuild: `.\build_windows_x64.ps1 -Clean`

### Issue: Plugin fails to load
**Solution**:
1. Check that all dependencies are properly linked in CMakeLists.txt
2. Ensure the shared core is included in the build
3. Verify Windows-specific library paths are correct

## Performance Notes

- **Release builds** are significantly faster and smaller
- **Static linking** is recommended to avoid DLL dependencies
- The built library will be ~50-100MB depending on configuration

## Architecture Support

Currently supports:
- ✅ **x64 (64-bit)** - Primary target
- ❌ **x86 (32-bit)** - Not supported (Flutter Windows requires x64)
- ❌ **ARM64** - Not yet supported

## Next Steps

After building successfully:

1. **Test basic functionality**: Ensure torrents can be started, paused, resumed
2. **Implement event channels**: Add proper stats/metadata callbacks
3. **Performance testing**: Test with multiple torrents
4. **Integration testing**: Test with the full Flutter app

## Troubleshooting Build Issues

### Enable Verbose Output
```powershell
$env:VERBOSE = "1"
.\build_windows_x64.ps1
```

### Check Dependencies
```powershell
cd c:\Dev\simple_torrent\build_scripts
.\check_shared_deps.ps1 check
```

### Manual Verification
```powershell
# Check if files exist
Test-Path "c:\Dev\simple_torrent\shared\lib\windows\lib\torrent-rasterbar.lib"
Test-Path "c:\Dev\simple_torrent\shared\lib\windows\include\libtorrent\version.hpp"

# Check file sizes
Get-Item "c:\Dev\simple_torrent\shared\lib\windows\lib\torrent-rasterbar.lib" | Select-Object Name, Length
```
