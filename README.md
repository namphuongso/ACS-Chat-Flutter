# ACS-Chat-Flutter

Module Chat SDK Flutter phục vụ tích hợp cho dự án NPP-Mobile. SDK áp dụng Clean Architecture, Riverpod quản lý State, WebSocket Backend cho kết nối Realtime và Hive lưu Cache dữ liệu offline.

## Cài đặt & Tích hợp

Khai báo các package dưới dạng Git Dependency trong tệp `pubspec.yaml` của dự án Host:

```yaml
dependencies:
  flutter:
    sdk: flutter

  chat_core:
    git:
      url: git@github.com:namphuongso/ACS-Chat-Flutter.git
      path: chat-module-mvp/packages/chat_core
      ref: development

  chat_ui:
    git:
      url: git@github.com:namphuongso/ACS-Chat-Flutter.git
      path: chat-module-mvp/packages/chat_ui
      ref: development
```

Lưu ý:
- Có thể dùng URL HTTPS `https://github.com/namphuongso/ACS-Chat-Flutter.git` nếu không dùng SSH key.
- Có thể thay `ref: development` bằng `ref: main` hoặc `tag: vX.Y.Z` tùy môi trường release.
- Realtime sử dụng kết nối WebSocket thuần Dart nên không yêu cầu cài đặt native SDK plugin.

## Khởi tạo & Setup

### 1. Khởi tạo Chat Core tại main.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chat_core/chat_core.dart';
import 'package:chat_ui/chat_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ChatCore.initialize();

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
```

### 2. Định nghĩa cấu hình ChatUiConfig

```dart
final chatConfig = ChatUiConfig(
  backendBaseUrl: 'https://api-domain.com',
  apiKey: 'YOUR_API_KEY',
  roomBackgroundColor: const Color(0xFFF5F6F8),
  inputBarBackgroundColor: Colors.white,
  sentBubbleColor: const Color(0xFF007AFF),
  receivedBubbleColor: Colors.white,
);
```

### 3. Mở màn hình danh sách cuộc trò chuyện ChatListPage

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => ChatListPage(
      currentUserId: 'CURRENT_USER_ID',
      config: chatConfig,
    ),
  ),
);
```

### 4. Mở trực tiếp một phòng chat cụ thể ThreadScreen

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => ThreadScreen(
      roomId: 'TARGET_ROOM_ID',
      threadId: 'TARGET_THREAD_ID',
      currentUserId: 'CURRENT_USER_ID',
      config: chatConfig,
    ),
  ),
);
```

### 5. Điều hướng từ Push Notification hoặc Deep Link

```dart
final deepLinkData = ChatDeepLinkData.fromMap(notificationPayload);
if (deepLinkData != null) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ThreadScreen(
        roomId: deepLinkData.roomId,
        threadId: deepLinkData.threadId,
        currentUserId: 'CURRENT_USER_ID',
        config: chatConfig,
      ),
    ),
  );
}
```

## Tính năng thư viện hỗ trợ

- Chat 1-1 và Chat nhóm (Direct Chat & Group Chat).
- WebSocket Realtime với cơ chế tự động duy trì Heartbeat và Reconnect khi khôi phục kết nối mạng.
- Quản lý phòng chat: tạo nhóm, xem thành viên, đổi tên nhóm, đổi avatar nhóm, ghim tin nhắn, chuyển quyền trưởng phòng, bổ nhiệm quản trị viên, rời phòng chat.
- Gửi tin nhắn đa phương tiện qua Azure Blob SAS URL: hình ảnh (bộ lưới 1-4+ ảnh, carousel xem toàn màn hình), video, tệp tài liệu (PDF, Word, Excel, PowerPoint, ZIP, TXT) kèm tiến trình upload realtime.
- Tự động hiển thị thẻ xem trước liên kết (Link Preview Card) khi gửi tin nhắn chứa đường dẫn URL.
- Thả biểu tượng cảm xúc tin nhắn (Message Reactions: Like, Love, Haha, Wow, Sad, Angry).
- Lưu trữ và truy xuất cache offline dữ liệu cuộc trò chuyện và tin nhắn với Hive Local Storage.
- Tùy biến giao diện linh hoạt qua `ChatUiConfig` (màu bong bóng chat, màu nền phòng chat, thanh nhập liệu, theme icon).
- Format log HTTP Request/Response và WebSocket event dạng JSON Pretty Print với `ChatLogger`.