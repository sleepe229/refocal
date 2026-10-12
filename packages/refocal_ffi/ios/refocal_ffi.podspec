# iOS: libenh is shipped as enh.xcframework, built from native/ on macOS
# (native/tools/build_xcframework.sh, TODO 0.1 — needs a Mac; macos.yml).
Pod::Spec.new do |s|
  s.name             = 'refocal_ffi'
  s.version          = '0.0.1'
  s.summary          = 'Dart FFI bridge to the Refocal native core.'
  s.homepage         = 'https://github.com/refocal/refocal'
  s.license          = { :type => 'Apache-2.0', :file => '../../../LICENSE' }
  s.author           = { 'Refocal contributors' => 'https://github.com/refocal' }
  s.source           = { :path => '.' }
  s.vendored_frameworks = 'Frameworks/enh.xcframework'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
