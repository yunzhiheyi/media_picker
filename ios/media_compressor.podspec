#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'media_compressor'
  s.version          = '1.0.0'
  s.summary          = 'Flutter plugin for image/video compression and media picking.'
  s.description      = <<-DESC
Image/video compression and album picker. Chat presets: 720p video, long-edge 2048 image.
                       DESC
  s.homepage         = 'https://github.com/yunzhiheyi/media_compressor'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'yunzhiheyi' => 'https://github.com/yunzhiheyi' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'media_compressor_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
