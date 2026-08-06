# chat_native_platform_interface

Cầu nối duy nhất tới ACS Chat SDK realtime. Không UI, không business logic.

## Trạng thái nền tảng

| Nền tảng | Trạng thái |
|---|---|
| Android | Implemented (MVP) |
| iOS | **Chưa implement** — cần thêm `ios/Classes/*.swift` tương tự
        `android/src/main/kotlin/.../ChatNativePlugin.kt`, đăng ký lại
        trong `pubspec.yaml` (`flutter.plugin.platforms.ios`) |

## Version SDK Azure đang dùng

- `com.azure.android:azure-communication-chat:2.1.0` (⚠️ chưa verify —
  xem TODO trong `android/build.gradle`, kiểm tra lại version mới nhất
  trên Maven Central trước khi build thật)
- `com.azure.android:azure-communication-common:1.2.0` (⚠️ tương tự)

## Cách test

1. Build package riêng: `cd android && ./gradlew build` (cần Android SDK cài sẵn).
2. Test tích hợp qua `example/` app — chạy trên **thiết bị/emulator Android
   thật**, không phải chỉ đọc code, vì `startRealtimeNotifications()`
   cần network thật để verify hoạt động đúng.
3. Kịch bản bắt buộc test tay (chưa có automated test cho phần native):
   - Nhận tin nhắn mới khi app đang mở (foreground).
   - Mất mạng giữa chừng → có mạng lại → có tiếp tục nhận tin không (reconnect).
   - App vào background → quay lại foreground → gọi lại `initialize` có
     hoạt động đúng không, có leak connection cũ không.

## Theo dõi breaking change

Azure Communication Services báo trước thay đổi breaking ≥1 năm (theo
kế hoạch gốc mục 7.5). Theo dõi qua:
- Azure Communication Services release notes (Microsoft Learn).
- GitHub `Azure/azure-sdk-for-android` — tag release + CHANGELOG.

## Ranh giới trách nhiệm (nhắc lại từ kế hoạch gốc mục 3)

Package này CHỈ làm 1 việc: init token → `startRealtimeNotifications()` →
forward `chatMessageReceived` qua `EventChannel`. KHÔNG thêm:
- Gửi tin nhắn (đã có ở `chat_core` qua REST)
- Load lịch sử/pagination (đã có ở `chat_core` qua REST)
- Bất kỳ UI nào
