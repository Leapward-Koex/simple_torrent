cmake_minimum_required(VERSION 3.21)

if(POLICY CMP0144)
  cmake_policy(SET CMP0144 NEW)
  # Keep the policy enabled inside the pinned libtorrent subproject too.
  set(CMAKE_POLICY_DEFAULT_CMP0144 NEW)
endif()

project(simple_torrent_native VERSION 2.0.0 LANGUAGES C CXX)

set(SIMPLE_TORRENT_LIBRARY_TYPE "SHARED" CACHE STRING
    "Native library type: SHARED for Android/Windows, STATIC for Apple")
set_property(CACHE SIMPLE_TORRENT_LIBRARY_TYPE PROPERTY STRINGS SHARED STATIC)

# STN_* names are the stable command-line contract used by tool/native.*.
option(STN_BUILD_SHARED "Build the native C ABI as a shared library" ON)
option(STN_BUILD_TESTS "Build maintainer-only native C ABI tests" OFF)
if(DEFINED STN_BUILD_SHARED)
  if(STN_BUILD_SHARED)
    set(SIMPLE_TORRENT_LIBRARY_TYPE "SHARED")
  else()
    set(SIMPLE_TORRENT_LIBRARY_TYPE "STATIC")
  endif()
endif()

if(ANDROID)
  set(_android_adapter_default ON)
else()
  set(_android_adapter_default OFF)
endif()
option(SIMPLE_TORRENT_ANDROID_ADAPTER
       "Compile the Android JNI adapter into libsimple_torrent_native"
       ${_android_adapter_default})
option(STN_ANDROID_JNI "Compile the Android JNI adapter" ${_android_adapter_default})
if(STN_ANDROID_JNI)
  set(SIMPLE_TORRENT_ANDROID_ADAPTER ON)
endif()

set(STN_LIBTORRENT_SOURCE "" CACHE PATH "Extracted pinned libtorrent source")
set(LIBTORRENT_ROOT "" CACHE PATH "Installed libtorrent prefix")
set(BOOST_ROOT "" CACHE PATH "Extracted Boost source/include root")
set(OPENSSL_ROOT "" CACHE PATH "Installed static OpenSSL prefix")
set(LIBTORRENT_LIBRARY "" CACHE FILEPATH "Explicit static libtorrent library")
set(OPENSSL_SSL_LIBRARY "" CACHE FILEPATH "Explicit static OpenSSL SSL library")
set(OPENSSL_CRYPTO_LIBRARY "" CACHE FILEPATH "Explicit static OpenSSL crypto library")
set(STN_CA_BUNDLE_FILE "" CACHE FILEPATH
    "Pinned PEM CA bundle to embed in Apple artifacts")

if(NOT OPENSSL_ROOT AND OPENSSL_ROOT_DIR)
  set(OPENSSL_ROOT "${OPENSSL_ROOT_DIR}")
endif()
if(NOT LIBTORRENT_ROOT AND STN_LIBTORRENT_SOURCE)
  set(LIBTORRENT_ROOT "${STN_LIBTORRENT_SOURCE}")
endif()

if((NOT LIBTORRENT_ROOT AND NOT STN_LIBTORRENT_SOURCE) OR
   NOT BOOST_ROOT OR NOT OPENSSL_ROOT)
  message(FATAL_ERROR
    "STN_LIBTORRENT_SOURCE (or LIBTORRENT_ROOT), BOOST_ROOT, and "
    "OPENSSL_ROOT_DIR (or OPENSSL_ROOT) are required. "
    "Use tool/native.ps1 or tool/native.sh; consumers never invoke this CMake project.")
endif()

if(EXISTS "${BOOST_ROOT}/boost/version.hpp")
  set(BOOST_INCLUDE_DIR "${BOOST_ROOT}")
elseif(EXISTS "${BOOST_ROOT}/include/boost/version.hpp")
  set(BOOST_INCLUDE_DIR "${BOOST_ROOT}/include")
else()
  # Boost is a checksummed source input, not a target-sysroot package. Android
  # and Apple cross toolchains otherwise re-root even these explicit hints.
  find_path(BOOST_INCLUDE_DIR
    NAMES boost/version.hpp
    HINTS "${BOOST_ROOT}" "${BOOST_ROOT}/include"
    PATH_SUFFIXES include
    NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH REQUIRED)
endif()
# libtorrent's own FindBoost invocation must consume the same canonical header
# tree instead of trying to rediscover it through a cross-compilation sysroot.
set(Boost_INCLUDE_DIR "${BOOST_INCLUDE_DIR}" CACHE PATH
    "Pinned Boost include directory" FORCE)
set(BOOST_INCLUDEDIR "${BOOST_INCLUDE_DIR}" CACHE PATH
    "Pinned Boost include directory hint" FORCE)

set(OPENSSL_ROOT_DIR "${OPENSSL_ROOT}")
set(OPENSSL_USE_STATIC_LIBS TRUE)
find_package(OpenSSL REQUIRED)
set(OPENSSL_INCLUDE_DIR "${OPENSSL_INCLUDE_DIR}")
set(OPENSSL_SSL_LIBRARY "${OPENSSL_SSL_LIBRARY}")
set(OPENSSL_CRYPTO_LIBRARY "${OPENSSL_CRYPTO_LIBRARY}")

if(STN_LIBTORRENT_SOURCE)
  if(NOT EXISTS "${STN_LIBTORRENT_SOURCE}/CMakeLists.txt")
    message(FATAL_ERROR
      "STN_LIBTORRENT_SOURCE is not an extracted libtorrent source tree: "
      "${STN_LIBTORRENT_SOURCE}")
  endif()
  set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
  set(build_tests OFF CACHE BOOL "" FORCE)
  set(build_examples OFF CACHE BOOL "" FORCE)
  set(build_tools OFF CACHE BOOL "" FORCE)
  set(python-bindings OFF CACHE BOOL "" FORCE)
  set(deprecated-functions OFF CACHE BOOL "" FORCE)
  set(logging OFF CACHE BOOL "" FORCE)
  set(encryption ON CACHE BOOL "" FORCE)
  set(dht ON CACHE BOOL "" FORCE)
  set(static_runtime ON CACHE BOOL "" FORCE)
  set(Boost_ROOT "${BOOST_ROOT}")
  set(Boost_NO_SYSTEM_PATHS ON)
  add_subdirectory("${STN_LIBTORRENT_SOURCE}"
                   "${CMAKE_CURRENT_BINARY_DIR}/libtorrent-build"
                   EXCLUDE_FROM_ALL)
  set(LIBTORRENT_LINK_ITEM torrent-rasterbar)
  set(LIBTORRENT_INCLUDE_DIR "${STN_LIBTORRENT_SOURCE}/include")
else()
  find_path(LIBTORRENT_INCLUDE_DIR
    NAMES libtorrent/session.hpp
    HINTS "${LIBTORRENT_ROOT}" "${LIBTORRENT_ROOT}/include"
    PATH_SUFFIXES include
    NO_DEFAULT_PATH REQUIRED)
  if(NOT LIBTORRENT_LIBRARY)
    find_library(LIBTORRENT_LIBRARY
      NAMES torrent-rasterbar libtorrent-rasterbar
      HINTS "${LIBTORRENT_ROOT}/lib" "${LIBTORRENT_ROOT}/lib64"
      NO_DEFAULT_PATH REQUIRED)
  endif()
  set(LIBTORRENT_LINK_ITEM "${LIBTORRENT_LIBRARY}")
endif()

set(SIMPLE_TORRENT_NATIVE_SOURCES
  src/embedded_ca_bundle.cpp
  src/simple_torrent_native.cpp
  src/torrent_manager.cpp)

if(STN_CA_BUNDLE_FILE)
  if(NOT EXISTS "${STN_CA_BUNDLE_FILE}")
    message(FATAL_ERROR "STN_CA_BUNDLE_FILE does not exist: ${STN_CA_BUNDLE_FILE}")
  endif()
  file(READ "${STN_CA_BUNDLE_FILE}" _stn_ca_bundle_hex HEX)
  if(_stn_ca_bundle_hex STREQUAL "")
    message(FATAL_ERROR "STN_CA_BUNDLE_FILE is empty: ${STN_CA_BUNDLE_FILE}")
  endif()
  string(REGEX REPLACE "([0-9a-fA-F][0-9a-fA-F])" "0x\\1,"
         _stn_ca_bundle_bytes "${_stn_ca_bundle_hex}")
  file(WRITE
    "${CMAKE_CURRENT_BINARY_DIR}/simple_torrent_embedded_ca_bundle.inc"
    "${_stn_ca_bundle_bytes}\n")
endif()
if(SIMPLE_TORRENT_ANDROID_ADAPTER)
  if(NOT ANDROID)
    message(FATAL_ERROR "SIMPLE_TORRENT_ANDROID_ADAPTER requires an Android toolchain")
  endif()
  list(APPEND SIMPLE_TORRENT_NATIVE_SOURCES
    platform/android/simple_torrent_android.cpp)
endif()

add_library(simple_torrent_native ${SIMPLE_TORRENT_LIBRARY_TYPE}
  ${SIMPLE_TORRENT_NATIVE_SOURCES}
  include/simple_torrent_native.h)

target_compile_features(simple_torrent_native PRIVATE cxx_std_17)
set_target_properties(simple_torrent_native PROPERTIES
  CXX_EXTENSIONS OFF
  POSITION_INDEPENDENT_CODE ON
  OUTPUT_NAME simple_torrent_native
  C_VISIBILITY_PRESET hidden
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)

target_include_directories(simple_torrent_native
  PUBLIC "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${LIBTORRENT_INCLUDE_DIR}"
    "${BOOST_INCLUDE_DIR}"
    "${OPENSSL_INCLUDE_DIR}")

target_compile_definitions(simple_torrent_native PRIVATE
  SIMPLE_TORRENT_NATIVE_BUILD=1
  TORRENT_LINKING_STATIC=1
  BOOST_ALL_NO_LIB=1)
if(STN_CA_BUNDLE_FILE)
  target_compile_definitions(simple_torrent_native PRIVATE
    SIMPLE_TORRENT_EMBEDDED_CA_BUNDLE=1)
endif()

target_link_libraries(simple_torrent_native PRIVATE
  ${LIBTORRENT_LINK_ITEM}
  OpenSSL::SSL
  OpenSSL::Crypto)

find_package(Threads REQUIRED)
target_link_libraries(simple_torrent_native PRIVATE Threads::Threads)

if(MSVC)
  set_property(TARGET simple_torrent_native PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  target_compile_options(simple_torrent_native PRIVATE
    /W4 /WX- /utf-8 /Brepro /experimental:deterministic
    "/pathmap:${CMAKE_BINARY_DIR}=build"
    "/pathmap:${CMAKE_SOURCE_DIR}=."
    "/pathmap:${STN_LIBTORRENT_SOURCE}=third_party/libtorrent"
    "/pathmap:${BOOST_ROOT}=third_party/boost"
    "/pathmap:${OPENSSL_ROOT}=third_party/openssl")
  target_link_options(simple_torrent_native PRIVATE
    /Brepro "/PDBALTPATH:%_PDB%")
  target_compile_definitions(simple_torrent_native PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS
    WINVER=0x0A00 _WIN32_WINNT=0x0A00)
  target_link_libraries(simple_torrent_native PRIVATE
    ws2_32 iphlpapi crypt32 advapi32 user32 bcrypt)
else()
  target_compile_options(simple_torrent_native PRIVATE
    -Wall -Wextra -Wpedantic
    "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build"
    "-ffile-prefix-map=${CMAKE_SOURCE_DIR}=."
    "-ffile-prefix-map=${STN_LIBTORRENT_SOURCE}=third_party/libtorrent"
    "-ffile-prefix-map=${BOOST_ROOT}=third_party/boost"
    "-ffile-prefix-map=${OPENSSL_ROOT}=third_party/openssl")
endif()

if(TARGET torrent-rasterbar)
  if(MSVC)
    target_compile_options(torrent-rasterbar PRIVATE
      /Brepro /experimental:deterministic
      "/pathmap:${CMAKE_BINARY_DIR}=build"
      "/pathmap:${CMAKE_SOURCE_DIR}=."
      "/pathmap:${STN_LIBTORRENT_SOURCE}=third_party/libtorrent"
      "/pathmap:${BOOST_ROOT}=third_party/boost"
      "/pathmap:${OPENSSL_ROOT}=third_party/openssl")
  else()
    target_compile_options(torrent-rasterbar PRIVATE
      "-ffile-prefix-map=${CMAKE_SOURCE_DIR}=."
      "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build"
      "-ffile-prefix-map=${STN_LIBTORRENT_SOURCE}=third_party/libtorrent"
      "-ffile-prefix-map=${BOOST_ROOT}=third_party/boost"
      "-ffile-prefix-map=${OPENSSL_ROOT}=third_party/openssl")
  endif()
endif()

if(ANDROID)
  if(NOT CMAKE_ANDROID_STL_TYPE STREQUAL "c++_static")
    message(FATAL_ERROR
      "Android artifacts must use -DANDROID_STL=c++_static so the single .so is self-contained")
  endif()
  target_link_options(simple_torrent_native PRIVATE
    "LINKER:-z,defs" "LINKER:--exclude-libs,ALL")
  find_library(ANDROID_LOG_LIBRARY log REQUIRED)
  find_library(ANDROID_DL_LIBRARY dl REQUIRED)
  target_link_libraries(simple_torrent_native PRIVATE
    "${ANDROID_LOG_LIBRARY}" "${ANDROID_DL_LIBRARY}")
  find_library(ANDROID_ATOMIC_LIBRARY atomic)
  if(ANDROID_ATOMIC_LIBRARY)
    target_link_libraries(simple_torrent_native PRIVATE
      "${ANDROID_ATOMIC_LIBRARY}")
  endif()
endif()

if(APPLE AND SIMPLE_TORRENT_LIBRARY_TYPE STREQUAL "STATIC")
  find_library(SECURITY_FRAMEWORK Security REQUIRED)
  find_library(SYSTEM_CONFIGURATION_FRAMEWORK SystemConfiguration REQUIRED)
  target_link_libraries(simple_torrent_native PRIVATE
    "${SECURITY_FRAMEWORK}" "${SYSTEM_CONFIGURATION_FRAMEWORK}")

  # A normal CMake static archive does not absorb its static dependencies.
  # Merge them so each XCFramework slice remains truly self-contained.
  set(SIMPLE_TORRENT_COMBINED_ARCHIVE
      "${CMAKE_CURRENT_BINARY_DIR}/libsimple_torrent_native_combined.a")
  if(TARGET torrent-rasterbar)
    set(_libtorrent_archive "$<TARGET_FILE:torrent-rasterbar>")
  else()
    set(_libtorrent_archive "${LIBTORRENT_LIBRARY}")
  endif()
  add_custom_command(
    OUTPUT "${SIMPLE_TORRENT_COMBINED_ARCHIVE}"
    COMMAND /usr/bin/libtool -static -o "${SIMPLE_TORRENT_COMBINED_ARCHIVE}"
      "$<TARGET_FILE:simple_torrent_native>"
      "${_libtorrent_archive}"
      "${OPENSSL_SSL_LIBRARY}"
      "${OPENSSL_CRYPTO_LIBRARY}"
    DEPENDS simple_torrent_native
    VERBATIM)
  add_custom_target(simple_torrent_native_combined ALL
    DEPENDS "${SIMPLE_TORRENT_COMBINED_ARCHIVE}")
endif()

include(GNUInstallDirs)
install(TARGETS simple_torrent_native
  ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(FILES include/simple_torrent_native.h
  DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}")

if(STN_BUILD_TESTS)
  enable_testing()
  add_executable(simple_torrent_native_session_suspension_test
    test/session_suspension_test.cpp)
  target_compile_features(simple_torrent_native_session_suspension_test
    PRIVATE cxx_std_17)
  target_link_libraries(simple_torrent_native_session_suspension_test
    PRIVATE simple_torrent_native)
  add_test(
    NAME simple_torrent_native.session_suspension
    COMMAND simple_torrent_native_session_suspension_test)
  set_tests_properties(simple_torrent_native.session_suspension
    PROPERTIES TIMEOUT 30)
endif()
