#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint multi_screen_presentation.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'multi_screen_presentation'
  s.version          = '1.0.8'
  s.summary          = 'A comprehensive Flutter plugin to manage presentation windows on secondary screens with customizable properties.'
  s.description      = <<-DESC
  A comprehensive Flutter plugin to manage presentation windows on secondary screens with customizable properties.
                       DESC
  s.homepage         = 'https://github.com/Noamcreator/multi_screen_presentation'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Noam' => 'noam.bourmault@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'multi_screen_presentation/Sources/multi_screen_presentation/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'multi_screen_presentation_privacy' => ['multi_screen_presentation/Sources/multi_screen_presentation/PrivacyInfo.xcprivacy']}
end
