Pod::Spec.new do |s|
  s.name           = 'WatchBridge'
  s.version        = '1.0.0'
  s.summary        = 'WatchConnectivity inbox for HeartThreshold recordings'
  s.description    = 'Moves finished watch recordings into the phone inbox and acknowledges them.'
  s.license        = { :type => 'MIT' }
  s.author         = 'HeartThreshold'
  s.homepage       = 'https://github.com/justcabyr/heartthreshold'
  s.platforms      = { :ios => '16.4' }
  s.source         = { :git => 'https://github.com/justcabyr/heartthreshold.git' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.frameworks = 'WatchConnectivity'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  }
  s.source_files = '**/*.{h,m,mm,swift}'
end
