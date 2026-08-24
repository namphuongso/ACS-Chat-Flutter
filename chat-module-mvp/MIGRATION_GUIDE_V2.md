# Hướng dẫn di chuyển và tích hợp Chat Module (Bản cập nhật V2.1 — WebSocket Realtime)

Tài liệu này ghi chú lại các thay đổi quan trọng trong thư viện `chat-module-mvp` sau khi được nâng cấp sang cơ chế kết nối WebSocket thuần Dart và loại bỏ phụ thuộc Native ACS SDK.

> ⚠️ **LƯU Ý:** Package `chat_native_platform_interface` và cấu hình `acsEndpoint` hiện tại đã **bị loại bỏ / đánh dấu legacy (`@deprecated`)**. Ứng dụng chính không cần khai báo native SDK hay truyền `acsEndpoint` nữa.

---

## 1. Yêu cầu cấu hình mới từ Ứng dụng chính (NPP-Mobile)

Ứng dụng chính chỉ cần truyền `backendBaseUrl` và `apiKey` (nếu có) khi khởi tạo `ChatUiConfig` hoặc `ChatModuleConfig`.

**Mã mẫu tích hợp:**
```dart
final chatConfig = ChatUiConfig(
  backendBaseUrl: AppConfig.authBaseUrl, // Đường dẫn backend API
  apiKey: AppConfig.chatApiKey,          // API key (nếu ứng dụng yêu cầu)
);
```

---

## 2. Thay đổi kết nối Realtime & REST API

1. **Kết nối Realtime**:
   - Sử dụng kết nối WebSocket thuần Dart thông qua `WebSocketRealtimeDataSourceImpl`.
   - Tự động duy trì Heartbeat và tự kết nối lại (Reconnect) khi mạng khôi phục.
   - Không yêu cầu plugin Native Android/iOS riêng.

2. **Tạo phòng chat & quản lý phòng**:
   - `POST /chat/create-room` với body `{"participantIds": [...]}`.
   - Ghim phòng (`pinRoom`), chuyển quyền trưởng phòng (`transferOwnership`), phân quyền quản trị (`setRoleAdmin`).

---

## 3. Cập nhật Model Dữ liệu & Exception

1. **Model**:
   - Đọc các trường `created`, `modified`, `isRead` và `lastMessage` trực tiếp từ JSON phản hồi REST.
2. **Exception Handling**:
   - Lỗi kết nối HTTP status code 4xx/5xx ném `ChatApiException`.
   - Lỗi dữ liệu rỗng / sai format parse ném `ChatDataException` (`statusCode: 422`).

---

## 4. Kiểm thử luồng gửi và nhận tin nhắn

Luồng gửi tin nhắn (`/chat/send-message`), upload file/media qua Azure Blob SAS URL, và nhận tin nhắn WebSocket Realtime đã được tích hợp hoàn chỉnh.
