Pod::Spec.new do |s|
  s.name             = 'multi_screen_presentation'
  s.version          = '1.0.2'
  s.summary          = 'Multi-screen presentation (iPad UIScene external display).'
  s.homepage         = 'https://github.com/Noamcreator/multi_screen_presentation'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Noam' => 'noam.bourmault@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = '../Sources/multi_screen_presentation/**/*
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
