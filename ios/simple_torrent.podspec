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
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  
  # Enable C++ compilation
  s.library = 'c++'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES',
    'GCC_ENABLE_CPP_RTTI' => 'YES',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../shared" "$(PODS_TARGET_SRCROOT)/../shared/third_party/libtorrent/include" "$(PODS_TARGET_SRCROOT)/../shared/third_party/boost"',
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]' => '"$(PODS_TARGET_SRCROOT)/../shared/lib/ios/device" "$(PODS_TARGET_SRCROOT)/../shared/lib/ios/device/boost"',
    'LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]' => '"$(PODS_TARGET_SRCROOT)/../shared/lib/ios/simulator" "$(PODS_TARGET_SRCROOT)/../shared/lib/ios/simulator/boost"',
    'OTHER_LDFLAGS' => [
      '-ltorrent-rasterbar',
      '-lboost_system',
      '-lboost_atomic',
      '-lboost_thread',
      '-lboost_chrono',
      '-lboost_regex',
      '-lboost_filesystem',
      '-lboost_date_time',
      '-framework', 'SystemConfiguration'
    ].join(' '),
    'SWIFT_OBJC_BRIDGING_HEADER' => '$(PODS_TARGET_SRCROOT)/Classes/simple_torrent-Bridging-Header.h'
  }
  s.swift_version = '5.0'

  # Link against libtorrent and boost static libraries
  # Use platform-specific libraries for device vs simulator
  s.ios.vendored_libraries = [
    '../shared/lib/ios/device/libtorrent-rasterbar.a',
    '../shared/lib/ios/device/boost/libboost_system.a',
    '../shared/lib/ios/device/boost/libboost_atomic.a',
    '../shared/lib/ios/device/boost/libboost_thread.a',
    '../shared/lib/ios/device/boost/libboost_chrono.a',
    '../shared/lib/ios/device/boost/libboost_regex.a',
    '../shared/lib/ios/device/boost/libboost_filesystem.a',
    '../shared/lib/ios/device/boost/libboost_date_time.a',
    '../shared/lib/ios/simulator/libtorrent-rasterbar.a',
    '../shared/lib/ios/simulator/boost/libboost_system.a',
    '../shared/lib/ios/simulator/boost/libboost_atomic.a',
    '../shared/lib/ios/simulator/boost/libboost_thread.a',
    '../shared/lib/ios/simulator/boost/libboost_chrono.a',
    '../shared/lib/ios/simulator/boost/libboost_regex.a',
    '../shared/lib/ios/simulator/boost/libboost_filesystem.a',
    '../shared/lib/ios/simulator/boost/libboost_date_time.a'
  ]

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'simple_torrent_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
