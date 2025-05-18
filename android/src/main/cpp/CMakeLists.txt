cmake_minimum_required(VERSION 3.18)
project(torrent_plugin LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)

# ───── 1. Header search paths ───────────────────────────────────────────
set(LIBTORRENT_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libtorrent)
set(BOOST_ROOT      ${CMAKE_CURRENT_SOURCE_DIR}/third_party/boost)

# ───── 2. Import the **shared** libtorrent (.so) built by b2 ────────────
#        (copy or symlink it into jniLibs/<abi>/ as libtorrent-rasterbar.so)
add_library(libtorrent SHARED IMPORTED)
set_target_properties(libtorrent PROPERTIES
    IMPORTED_LOCATION
        ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libtorrent-rasterbar.so.2.0.11
    INTERFACE_INCLUDE_DIRECTORIES
        ${LIBTORRENT_ROOT}/include
)

# ───── 3. Your plugin’s native code ─────────────────────────────────────
set(PLUGIN_SRC
    ${CMAKE_CURRENT_SOURCE_DIR}/torrent_core.cpp      # JNI layer (tiny)
    ${CMAKE_CURRENT_SOURCE_DIR}/torrent_plugin.cpp                   # platform-neutral libtorrent logic
)
add_library(torrent_plugin SHARED ${PLUGIN_SRC})

target_include_directories(torrent_plugin
    PRIVATE
        ${LIBTORRENT_ROOT}/include
        ${BOOST_ROOT}
)

# ───── 4. Android system libraries (conditionally) ──────────────────────
find_library(log_lib  log)
find_library(dl_lib   dl)
find_library(cpp_lib  c++_shared)

find_library(atomic_lib atomic)   # may be NOTFOUND on 64‑bit

# ───── 5. Final link line ───────────────────────────────────────────────
#     No separate try_signal/boost_system needed – they’re inside the .so.
target_link_libraries(torrent_plugin
    PRIVATE
        libtorrent
        ${cpp_lib}
        ${log_lib}
        ${dl_lib}
)

if(atomic_lib)
    target_link_libraries(torrent_plugin PRIVATE ${atomic_lib})
endif()
