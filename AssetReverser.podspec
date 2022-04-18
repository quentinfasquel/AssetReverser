Pod::Spec.new do |s|
  s.name = 'AssetReverser'
  s.version = '0.0.2'
  s.license = 'MIT'
  s.summary = 'Video `Reverser` in Swift'
  s.homepage = 'https://github.com/quentinfasquel/AssetReverser'
#  s.social_media_url = ''
  s.authors = { 'Quentin Fasquel' => '' }
  s.source = { :git => 'https://github.com/quentinfasquel/AssetReverser.git', :tag => s.version }
  s.platform = :ios
  s.ios.deployment_target = '10.0'
  s.frameworks = 'AVFoundation'
  s.source_files = 'Sources/AssetReverser/*.swift'
  s.swift_version = '5.0'
end
