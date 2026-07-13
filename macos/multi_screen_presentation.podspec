#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint media_metadata.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'multi_screen_presentation'
  s.version          = '1.0.0'
  s.summary          = 'Multi-screen presentation windows for Flutter macOS.'
  s.description      = <<-DESC
  Native window management, screen enumeration and Flutter-to-Flutter data bridge.
                       DESC
  s.homepage         = 'https://github.com/Noamcreator/multi_screen_presentation'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Noam' => 'noam.bourmault@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'multi_screen_presentation/Sources/multi_screen_presentation/**/*'

  s.resource_bundles = {
    'multi_screen_presentation_privacy' => ['multi_screen_presentation/Sources/multi_screen_presentation/PrivacyInfo.xcprivacy']
  }

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
