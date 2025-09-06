#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint simple_torrent.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'simple_torrent'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{swift,h,m,mm}'
  s.public_header_files = 'Classes/**/*.h'
  s.private_header_files = 'Classes/**/*.hpp', '../shared/torrent_core/**/*.hpp'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'simple_torrent_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  
  # Enable C++ compilation
  s.library = 'c++'
  
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES',
    'GCC_ENABLE_CPP_RTTI' => 'YES',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../shared" "$(PODS_TARGET_SRCROOT)/../shared/third_party/libtorrent/include" "$(PODS_TARGET_SRCROOT)/../shared/third_party/boost" "/usr/local/opt/openssl@3/include"',
    'LIBRARY_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../build_scripts/toolchains/build-macos-universal/boost-stage/lib" "$(PODS_TARGET_SRCROOT)/../build_scripts/toolchains/build-macos-universal/libtorrent-build" "/usr/local/opt/openssl@3/lib"',
    'OTHER_LDFLAGS' => [
      '-ltorrent-rasterbar',
      '-lboost_system',
      '-lboost_atomic', 
      '-lboost_thread',
      '-lboost_chrono',
      '-lboost_regex',
      '-lboost_filesystem',
      '-lboost_date_time',
      '/usr/local/opt/openssl@3/lib/libssl.a',
      '/usr/local/opt/openssl@3/lib/libcrypto.a',
      '-framework', 'SystemConfiguration'
    ].join(' ')
  }
  s.swift_version = '5.0'

  # Link against libtorrent and boost static libraries
  s.osx.vendored_libraries = [
    '../build_scripts/toolchains/build-macos-universal/libtorrent-build/libtorrent-rasterbar.a',
    '../build_scripts/toolchains/build-macos-universal/boost-stage/lib/libboost_system.a',
    '../build_scripts/toolchains/build-macos-universal/boost-stage/lib/libboost_atomic.a',
    '../build_scripts/toolchains/build-macos-universal/boost-stage/lib/libboost_thread.a',
    '../build_scripts/toolchains/build-macos-universal/boost-stage/lib/libboost_chrono.a',
    '../build_scripts/toolchains/build-macos-universal/boost-stage/lib/libboost_regex.a',
    '../build_scripts/toolchains/build-macos-universal/boost-stage/lib/libboost_filesystem.a',
    '../build_scripts/toolchains/build-macos-universal/boost-stage/lib/libboost_date_time.a'
  ]
end
