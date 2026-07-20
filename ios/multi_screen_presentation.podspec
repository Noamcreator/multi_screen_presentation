Pod::Spec.new do |s|
  s.name             = 'multi_screen_presentation'
  s.version          = '1.0.7'
  s.summary          = 'A comprehensive Flutter plugin to manage presentation windows on secondary screens with customizable properties.'
  s.homepage         = 'https://github.com/Noamcreator/multi_screen_presentation'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Noam' => 'noam.bourmault@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = '../Sources/multi_screen_presentation/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
