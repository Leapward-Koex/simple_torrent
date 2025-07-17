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
  s.source_files = 'Classes/**/*', '../shared/torrent_core/**/*'
  s.public_header_files = 'Classes/**/*.h', '../shared/torrent_core/**/*.hpp'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../shared/third_party/libtorrent/include" "$(PODS_TARGET_SRCROOT)/../shared/third_party/boost"',
    'LIBRARY_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../shared/lib/ios"',
    'OTHER_LDFLAGS' => '-ltorrent-rasterbar'
  }
  s.swift_version = '5.0'
  s.requires_arc = true

  # Link against libtorrent
  s.vendored_libraries = '../shared/lib/ios/libtorrent-rasterbar.a'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'simple_torrent_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
