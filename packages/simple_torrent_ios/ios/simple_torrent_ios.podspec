Pod::Spec.new do |s|
  s.name = 'simple_torrent_ios'
  s.version = '2.0.0'
  s.summary = 'iOS implementation of simple_torrent.'
  s.description = 'The endorsed iOS implementation of simple_torrent using a bundled native C ABI.'
  s.homepage = 'https://github.com/Leapward-Koex/simple_torrent'
  s.license = { :file => '../LICENSE' }
  s.author = { 'Leapward-Koex' => 'opensource@leapward.co.nz' }
  s.source = { :path => '.' }

  s.ios.deployment_target = '15.0'
  s.dependency 'Flutter'
  s.swift_version = '5.9'
  s.static_framework = true
  s.source_files = 'simple_torrent_ios/Sources/simple_torrent_ios/**/*.swift'
  s.vendored_frameworks = 'Frameworks/SimpleTorrentNative.xcframework'
  s.resource_bundles = {
    'simple_torrent_ios_privacy' => [
      'simple_torrent_ios/Sources/simple_torrent_ios/PrivacyInfo.xcprivacy'
    ]
  }
  s.libraries = 'c++'
  s.frameworks = 'CoreFoundation', 'Security', 'SystemConfiguration'
end
