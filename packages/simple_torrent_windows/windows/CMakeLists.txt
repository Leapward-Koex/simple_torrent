cmake_minimum_required(VERSION 3.14)

project(simple_torrent_windows LANGUAGES CXX)
cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "simple_torrent_windows_plugin")
set(NATIVE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/lib/x64")
set(NATIVE_DLL "${NATIVE_ROOT}/simple_torrent_native.dll")
set(NATIVE_IMPLIB "${NATIVE_ROOT}/simple_torrent_native.lib")
set(NATIVE_HEADER
    "${CMAKE_CURRENT_SOURCE_DIR}/include/simple_torrent_native.h")

foreach(required_file IN ITEMS "${NATIVE_DLL}" "${NATIVE_IMPLIB}" "${NATIVE_HEADER}")
  if(NOT EXISTS "${required_file}")
    message(FATAL_ERROR
      "Missing bundled native artifact: ${required_file}. "
      "Run tool/native.ps1 build windows from the repository root.")
  endif()
endforeach()

add_library(simple_torrent_native SHARED IMPORTED GLOBAL)
set_target_properties(simple_torrent_native PROPERTIES
  IMPORTED_LOCATION "${NATIVE_DLL}"
  IMPORTED_IMPLIB "${NATIVE_IMPLIB}"
  INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/include")

add_library(${PLUGIN_NAME} SHARED
  "include/simple_torrent_windows/simple_torrent_plugin_c_api.h"
  "simple_torrent_plugin_c_api.cpp"
  "simple_torrent_plugin.cpp"
  "simple_torrent_plugin.h")

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE
  FLUTTER_PLUGIN_IMPL WIN32_LEAN_AND_MEAN NOMINMAX
  WINVER=0x0A00 _WIN32_WINNT=0x0A00)
target_compile_options(${PLUGIN_NAME} PRIVATE
  /W4 /WX- /utf-8 /Brepro "/pathmap:${CMAKE_SOURCE_DIR}=.")
target_link_options(${PLUGIN_NAME} PRIVATE /Brepro)
target_include_directories(${PLUGIN_NAME}
  INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include"
  PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  simple_torrent_native)

# Flutter copies this one release C ABI DLL beside either Debug or Release apps.
set(simple_torrent_windows_bundled_libraries
  "${NATIVE_DLL}"
  PARENT_SCOPE)
