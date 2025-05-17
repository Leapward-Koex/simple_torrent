# simple_torrent

A new Flutter plugin project.

## Getting Started

## General steps for updating/generating libtorrent native code
1. Setup prerequisites
2. Setup your user-config.jam file for the compiler your using (depends on target and architecture)
3. Build boost B2 for your required toolset that you're updating the binary for (android-arm64-v8a, android-armeabi-v7a, android-x86_64, iOS arm64, etc..)
4. Create the boost tool 'BCP' to be able to include the correct boost headers in the project.
5. Compile libtorrent using the B2 executable we created in step 3 and copy the .so files to the appropriate folder in the plugin as well as the `include` folder generated for libtorrent to the appropirate include folder in the plugin.
6. Generate the necessary boost headers using BCP and copy them to the appropriate location in the plugin.

### Android Prerequisites
- A copy of libtorrent (Currently 2.0.11)
- A copy of the boost C++ library files (Currently 1.88.0)
- Android NDK (Currently 29.0.13113456)

### Setting up user-config.jam file
This is an example file under your home directory for building android-arm64-v8a.
```
using clang : android
    : "%ANDROID_NDK%/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android24-clang++.cmd"
    : <compileflags>"-fPIC"
      <linkflags>"-fPIC"
      <arch>arm           <address-model>64
      <abi>aapcs          <binary-format>elf
      <target-os>android
      <archiver>"%ANDROID_NDK%/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-ar.exe"
;
```

### Building B2 for your toolchain
Run this command it will generate a boost toolchain to compile libtorrent with
```
b2 -j%NUMBER_OF_PROCESSORS% ^
    toolset=clang-android ^
    target-os=android architecture=arm address-model=64 ^
    cxxstd=17 link=static runtime-link=static threading=multi ^
    --with-system --with-atomic ^
    --hash ^
    install --prefix="<output folder location>"
```

### Building BCP (toolchain agnostic)
Run this command to generate a bcp executable at `<path to boost>\dist\bin`. Change it based on your host machine architecture.
```
b2 --with-bcp toolset=msvc address-model=64 architecture=x86 link=static runtime-link=static release
```


### Building libtorrent
Run this command to generate the dynamic boost binaries and the necessary libtorrent headers
```
b2 -j%NUMBER_OF_PROCESSORS% ^
   toolset=clang-android ^
   target-os=android architecture=arm address-model=64 ^
   cxxstd=17 ^
   link=static             ^
   boost-link=static       ^
   runtime-link=static     ^
   crypto=built-in         ^
   variant=release         ^
   fpic=on                 ^
   --hash                  ^
   --prefix="<output folder location>" install
```

### Including boost headers
libtorrent uses boost c++ libraries so their headers need to be included to be able to build the C++ code. Boost contains tens of thosands of headers so the use of boost's bcp tool is required to file out what ones are required.
For every libtorrent header we import we need to feed this into bcp for it to work out the boost dependency tree. An example command for this is

```
bcp --boost=<path to boost> --scan "<path to libtorrent>\include\libtorrent\session.hpp" "<path to libtorrent>\include\libtorrent\alert_types.hpp" "<path to libtorrent>\include\libtorrent\magnet_uri.hpp" "<output path, e.g. 'simple_torrent\android\src\main\cpp\third_party\boost'>"
```
