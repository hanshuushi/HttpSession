# Podfile
use_frameworks!

# ignore all warnings from all pods
inhibit_all_warnings!

target ‘HttpSession’ do
    pod 'ObjectMapper', '~> 3.1.0'
    pod 'AFNetworking', '~> 3.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end


