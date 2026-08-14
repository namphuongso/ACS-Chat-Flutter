# ACS-Chat-Flutter

Module Chat SDK được xây dựng trên nền tảng Flutter phục vụ tích hợp cho dự án **NPP-Mobile**. Dự án áp dụng Clean Architecture kết hợp với Riverpod để quản lý State, Azure Communication Services (ACS) SDK native cho kết nối Realtime, và Hive để lưu Cache dữ liệu offline.

---

## 📦 Hướng dẫn Cài đặt & Tích hợp vào Dự án Host (NPP-Mobile)

Để tích hợp Chat Module vào ứng dụng chính (`NPP-Mobile`), khai báo các package dưới dạng **Git Dependency** trong tệp `pubspec.yaml` của dự án Host:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Chat Core (Domain, Data & Repositories)
  chat_core:
    git:
      url: git@github.com:namphuongso/ACS-Chat-Flutter.git
      path: chat-module-mvp/packages/chat_core
      ref: development

  # Chat UI (Giao diện màn hình & Component Widgets)
  chat_ui:
    git:
      url: git@github.com:namphuongso/ACS-Chat-Flutter.git
      path: chat-module-mvp/packages/chat_ui
      ref: development

  # Plugin kết nối Realtime Native (Android & iOS ACS SDK)
  chat_native_platform_interface:
    git:
      url: git@github.com:namphuongso/ACS-Chat-Flutter.git
      path: chat-module-mvp/packages/chat_native_platform_interface
      ref: development
```

> 💡 **Mẹo**: Nếu sử dụng kết nối HTTPS thay vì SSH key, bạn có thể đổi URL thành `https://github.com/namphuongso/ACS-Chat-Flutter.git`. Tùy theo giai đoạn release, bạn có thể thay `ref: development` bằng `ref: main` hoặc `tag: v2.0.0`.

---

## 🚀 Khởi tạo & Sử dụng nhanh trong App

### 1. Khởi tạo Chat Module tại `main.dart`
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chat_core/chat_core.dart';
import 'package:chat_ui/chat_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Chat Core & Storage Hive local cache
  await ChatCore.initialize();

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
```

### 2. Định nghĩa Cấu hình Giao diện & API (`ChatUiConfig`)
```dart
final chatConfig = ChatUiConfig(
  backendBaseUrl: 'https://namphuong-api-dev.azurewebsites.net',
  apiKey: '8492f144615571ac043b943e58471ba3bc37d7a59d065b1e6ff2d0106c1a1dc2',
  roomBackgroundColor: const Color(0xFFF5F6F8),
  inputBarBackgroundColor: Colors.white,
  sentBubbleColor: const Color(0xFF007AFF),
  receivedBubbleColor: Colors.white,
);
```

### 3. Điều hướng mở Màn hình Danh sách Chat (`ChatListPage`)
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

---

## ✨ Các tính năng & Cập nhật mới (Phase 02)

### 1. Quản lý Phòng chat nhóm & Thông tin phòng (Group Chat & Room Management)
- **Tạo nhóm & Xem thành viên**: Hỗ trợ tạo phòng chat nhiều người, xem danh sách thành viên chi tiết trong phòng chat.
- **Đổi tên & Đổi Avatar nhóm**: Cho phép cập nhật tên phòng chat nhóm và tải ảnh đại diện nhóm mới (`avatarUrl`).
- **Thao tác quản trị phòng**: Rời khỏi phòng chat nhóm, ghim (pin) và bỏ ghim (unpin) tin nhắn quan trọng trong phòng.

### 2. Thả cảm xúc tin nhắn (Message Reactions)
- **Cảm xúc đa dạng**: Thả / gỡ / thay đổi biểu tượng cảm xúc (Like, Love, Haha, Wow, Sad, Angry) tương thích đầy đủ API backend (`reactionId`, `reactionCode`).
- **Hiển thị trực tiếp**: Cập nhật danh sách icon cảm xúc phản hồi ngay trên bong bóng tin nhắn (Message Bubble) theo thời gian thực.

### 3. Tải lên Media & Tài liệu qua Azure Blob SAS (SAS File & Media Upload)
- **Upload nhiều tệp đồng thời**: Hỗ trợ chọn và tải lên nhiều hình ảnh cùng lúc hoặc các tệp tài liệu (PDF, Word, Excel, PowerPoint, ZIP, TXT) qua đường dẫn Azure Blob SAS token.
- **Tiến trình tải lên Realtime**: Hiển thị phần trăm tiến trình upload chi tiết cho từng tệp (`MediaUploadProgress`) trên thanh thông báo `UploadProgressBanner`.
- **Giao diện hiển thị đa dạng**:
  - Render bộ ảnh dạng lưới mượt mà (Grid 1–4+ ảnh).
  - Trình xem ảnh toàn màn hình (Full-screen Carousel Image Preview).
  - Thẻ tài liệu đính kèm (Document File Card) với biểu tượng theo định dạng file, tên tệp và dung lượng thực tế (`KB / MB`).

### 4. Kết nối Realtime & Tự động khôi phục (Native Realtime & Heartbeat)
- **Lắng nghe sự kiện tức thì**: Nhận tin nhắn mới, tin nhắn hệ thống (thành viên gia nhập, đổi tên nhóm) và cảm xúc thả tin nhắn theo thời gian thực.
- **Heartbeat & Tự động Reconnect**: Tự động duy trì heartbeat định kỳ tới server và khôi phục kết nối WebSocket ngay khi có mạng trở lại.

### 5. Format Log JSON (Pretty Print Logging)
- **Theo dõi Request / Response**: Sử dụng `ChatLogger` định dạng JSON красивый (Pretty Print) cho toàn bộ API HTTP (Headers, Query, Body, Status code) và các event WebSocket thô, giúp lập trình viên kiểm thử dễ dàng.

---

## 🛠️ Tổng quan tính năng Phase 01

### 1. Quản lý Tin nhắn (Message Management)
- **Cập nhật & Xóa tin nhắn**: Bổ sung `UpdateMessageUseCase` và `DeleteMessageUseCase` với giao diện chỉnh sửa/xóa trực tiếp trên tin nhắn của bản thân.
- **Tương thích API**: Khai báo và tích hợp các endpoint REST API trong `chat_api_endpoints.dart`.

### 2. Cấu hình Giao diện động (Dynamic UI Styling)
- **ChatUiConfig**: Cấu hình linh hoạt màu sắc bong bóng chat, hình nền phòng chat, thanh nhập tin nhắn và màu sắc icon từ ứng dụng chính.
- **Customizable Themes**: Cho phép ghi đè thông qua `chatUiConfigProvider` để đồng bộ hoàn toàn với thiết kế của Host App.

### 3. Trải nghiệm người dùng (UX/UI Improvements)
- **SearchField Debounce**: Widget tìm kiếm hỗ trợ debounce 350ms tối ưu số lượt gọi API.
- **Skeleton Loading**: Hiệu ứng Shimmer Loading (`SkeletonBox`, `MessageListSkeleton`, `ConversationListSkeleton`) chuyển cảnh tự nhiên.
- **Tùy chỉnh TabBar**: Thanh chuyển đổi giữa **Chat gần đây** và **Danh bạ** phẳng, mượt mà trong `ChatListPage`.

### 4. Cache Offline & Tốc độ tải (Local Caching)
- **HiveIdentityStore**: Cache danh tính người dùng (`myAcsUserId`) xuống Hive storage để hiển thị đúng vị trí bong bóng chat (isMe) kể cả khi chưa có mạng.
- **Hive Local Datasource**: Cache dữ liệu cuộc hội thoại (`HiveConversationLocalDatasource`) và tin nhắn (`HiveMessageLocalDatasource`) xem offline.