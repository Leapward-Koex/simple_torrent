@echo off
setlocal enabledelayedexpansion

rem ── edit these lines ───────────────────────────────────────────────
set "BOOST_SRC=C:\Dev\boost_1_88_0"
set "LBT_PREFIX=C:\Dev\libtorrent-arm64"
rem ───────────────────────────────────────────────────────────────────

rem derived paths
set "BOOST_PREFIX=C:\Dev\boost-android-arm64"
set "TOOLCHAIN=%ANDROID_NDK%\toolchains\llvm\prebuilt\windows-x86_64"
set "BOOST_B2=%BOOST_SRC%\b2.exe"
set "CLANG64=%TOOLCHAIN%\bin\aarch64-linux-android24-clang++"

rem ── make sure user‑config.jam points at the NDK compiler ───────────
if not exist "%USERPROFILE%\user-config.jam" (
  echo using clang : android : "%CLANG64%" : ^<compileflags^>"-fPIC" ^<linkflags^>"-fPIC" ^<arch^>arm ^<address-model^>64 ^<target-os^>android ; > "%USERPROFILE%\user-config.jam"
)

rem ── build Boost (only first time) ──────────────────────────────────
if not exist "%BOOST_PREFIX%\include\boost\config.hpp" (
  if not exist "%BOOST_SRC%\Jamroot" (
    echo ERROR: boost source directory "%BOOST_SRC%" not found.
    goto :eof
  )
  cd /d "%BOOST_SRC%"

  if not exist "%BOOST_B2%" (
    call bootstrap.bat || goto :eof
  )

    b2 -j%NUMBER_OF_PROCESSORS% ^
        toolset=clang-android ^
        target-os=android architecture=arm address-model=64 ^
        cxxstd=17 link=static runtime-link=static threading=multi ^
        --with-system --with-atomic ^
        --hash ^
        install --prefix="%BOOST_PREFIX%" || goto :eof
)

rem ── clone libtorrent once ──────────────────────────────────────────
if not exist "C:\Dev\libtorrent" (
  git clone --branch RC_2_0 --depth 1 https://github.com/arvidn/libtorrent.git C:\Dev\libtorrent || goto :eof
)

cd /d C:\Dev\libtorrent

rem ── build libtorrent with b2  ──────────────────────────────────────
%BOOST_B2% -j%NUMBER_OF_PROCESSORS% ^
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
   --prefix="%LBT_PREFIX%" install || goto :eof

echo.
echo libtorrent arm64‑v8a build complete.
echo ► libraries in %LBT_PREFIX%\lib
echo ► headers   in %LBT_PREFIX%\include
endlocal
