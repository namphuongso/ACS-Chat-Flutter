# chat_native_platform_interface

Cầu nối duy nhất tới ACS Chat SDK realtime. Không UI, không business logic.

## Trạng thái nền tảng

| Nền tảng | Trạng thái |
|---|---|
| Android | Implemented — đã build APK thành công với SDK `azure-communication-chat:2.1.0` (2026-08-06) |
| iOS | Implemented — đã build thành công với pod `AzureCommunicationChat:1.3.7` (2026-08-06) |

API native đã được đối chiếu trực tiếp với source SDK thật (Maven Central +
GitHub Azure SDK). Chi tiết verify + checklist test tay xem
[`REALTIME_PROGRESS.md`](../../REALTIME_PROGRESS.md).

## Version SDK Azure đang dùng

### Android (`android/build.gradle`)
- `com.azure.android:azure-communication-chat:2.1.0` (version mới nhất trên Maven Central, verify 2026-08-06)
- `com.azure.android:azure-communication-common:1.2.1` (version mà chat 2.1.0 khai báo)

### iOS (`ios/chat_native_platform_interface.podspec`)
- `AzureCommunicationChat ~> 1.3.7` (version mới nhất trên CocoaPods)
- `AzureCore 1.0.0-beta.16` (khai báo trực tiếp vì plugin có chạm vào `Iso8601Date`)

## Yêu cầu host app

### Android
- **minSdk ≥ 24** (ACS Chat SDK yêu cầu).
- Thêm block `packaging` loại trùng `META-INF/NOTICE.md` trong
  `android/app/build.gradle.kts` (ACS SDK kéo theo jakarta jars). Xem ví dụ
  trong `example/android/app/build.gradle.kts`.

### iOS
- `Podfile`: `platform :ios, '13.0'` (ACS Chat SDK yêu cầu). Xem ví dụ trong
  `example/ios/Podfile`.

## Cách test

1. Android: `cd example && flutter build apk --debug`.
2. iOS: `cd example && flutter build ios --debug --simulator`.
3. Test tích hợp chạy trên **thiết bị/emulator thật** (Android/iOS), vì
   `startRealtimeNotifications` cần network thật.

Kịch bản bắt buộc test tay (chưa có automated test cho phần native):
- Nhận tin nhắn mới khi app đang mở (foreground).
- Mất mạng giữa chừng → có mạng lại → có tiếp tục nhận tin không (reconnect).
- App vào background → quay lại foreground → gọi lại `initialize` có
  hoạt động đúng không, có leak connection cũ không.
- Token ACS hết hạn → refresh → re-init → realtime chạy tiếp.

## Follow-up (cảnh báo từ build, chưa phải blocker)

- Flutter cảnh báo plugin này **áp dụng Kotlin Gradle Plugin (KGP) trực tiếp** —
  phiên bản Flutter tương lai sẽ fail. Cần migrate sang Built-in Kotlin
  (plugin Gradle convention mới).
- Flutter cảnh báo plugin **chưa hỗ trợ Swift Package Manager** cho iOS —
  phiên bản Flutter tương lai sẽ fail. Cần thêm hỗ trợ SPM khi cần.

## Theo dõi breaking change

Azure Communication Services báo trước thay đổi breaking ≥1 năm (theo
kế hoạch gốc mục 7.5). Theo dõi qua:
- Azure Communication Services release notes (Microsoft Learn).
- GitHub `Azure/azure-sdk-for-android` và `Azure/azure-sdk-for-ios` — tag
  release + CHANGELOG.

## Ranh giới trách nhiệm (nhắc lại từ kế hoạch gốc mục 3)

Package này CHỈ làm 1 việc: init token → `startRealtimeNotifications` →
forward `chatMessageReceived` qua `EventChannel`. KHÔNG thêm:
- Gửi tin nhắn (đã có ở `chat_core` qua REST)
- Load lịch sử/pagination (đã có ở `chat_core` qua REST)
- Bất kỳ UI nào
