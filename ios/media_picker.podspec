# Flutter resolves iOS pods by the Dart package name. Keep this podspec aligned
# with `name: media_picker` while retaining the existing native implementation.
Pod::Spec.new do |s|
  s.name             = 'media_picker'
  s.version          = '1.0.0'
  s.summary          = 'Flutter media picker with Hero preview and compression.'
  s.description      = <<-DESC
Image/video selection, Hero preview, and compression APIs.
                       DESC
  s.homepage         = 'https://github.com/yunzhiheyi/media_picker'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'yunzhiheyi' => 'https://github.com/yunzhiheyi' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'media_picker_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
