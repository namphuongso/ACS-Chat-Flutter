#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'chat_native_platform_interface'
  s.version          = '0.1.0'
  s.summary          = 'Cầu nối duy nhất tới ACS Chat SDK realtime (iOS).'
  s.description      = <<-DESC
Cầu nối duy nhất tới ACS Chat SDK realtime (Trouter) qua native.
KHÔNG có UI, KHÔNG có business logic — chỉ forward event tin nhắn mới
qua EventChannel (đúng ranh giới trách nhiệm mục 3 kế hoạch gốc).
                       DESC
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'BSD' }
  s.author           = { 'Your Company' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'chat_native_platform_interface/Classes/**/*'
  s.dependency 'Flutter'
  # Version SDK đã verify 2026-08-06: AzureCommunicationChat 1.3.7 là mới
  # nhất trên CocoaPods. AzureCore khai báo trực tiếp vì plugin có chạm
  # vào type Iso8601Date/RequestStringConvertible (xem REALTIME_PROGRESS.md).
  s.dependency 'AzureCommunicationChat', '~> 1.3.7'
  s.dependency 'AzureCore', '1.0.0-beta.16'
  # ACS iOS SDK yêu cầu iOS 13.0+
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
