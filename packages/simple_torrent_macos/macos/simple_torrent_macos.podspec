Pod::Spec.new do |s|
  s.name = 'simple_torrent_macos'
  s.version = '2.0.0'
  s.summary = 'macOS implementation of simple_torrent.'
  s.description = 'The endorsed macOS implementation of simple_torrent using a bundled native C ABI.'
  s.homepage = 'https://github.com/Leapward-Koex/simple_torrent'
  s.license = { :file => '../LICENSE' }
  s.author = { 'Leapward-Koex' => 'opensource@leapward.co.nz' }
  s.source = { :path => '.' }

  s.osx.deployment_target = '12.0'
  s.dependency 'FlutterMacOS'
  s.swift_version = '5.9'
  s.static_framework = true
  s.source_files = 'simple_torrent_macos/Sources/simple_torrent_macos/**/*.swift'
  s.vendored_frameworks = 'simple_torrent_macos/Frameworks/SimpleTorrentNative.xcframework'
  s.resource_bundles = {
    'simple_torrent_macos_privacy' => [
      'simple_torrent_macos/Sources/simple_torrent_macos/PrivacyInfo.xcprivacy'
    ]
  }
  s.libraries = 'c++'
  s.frameworks = 'CoreFoundation', 'Security', 'SystemConfiguration'
end
