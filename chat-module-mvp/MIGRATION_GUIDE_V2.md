# Hướng dẫn di chuyển và tích hợp Chat Module (Bản cập nhật API mới)

Tài liệu này ghi chú lại các thay đổi quan trọng trong thư viện `chat-module-mvp` sau khi được nâng cấp để đồng bộ với bộ tài liệu API mới nhất (đặc biệt là cơ chế lấy token theo từng phòng). Các lập trình viên phụ trách ứng dụng chính (NPP-Mobile) và Backend cần lưu ý các điểm sau để tích hợp thành công.

## 1. Yêu cầu cấu hình mới từ Ứng dụng chính (NPP-Mobile)

Thư viện hiện tại không còn tự đọc `endpoint` từ API trả về (do API `join-room` đã lược bỏ trường này). Thay vào đó, ứng dụng chính phải truyền tĩnh địa chỉ này vào thư viện.

**Hành động cần làm:**
1. Thêm biến `ACS_ENDPOINT` vào tệp `.env` của ứng dụng chính (ví dụ: `ACS_ENDPOINT=https://namphuong-acs.communication.azure.com`).
2. Khi khởi tạo cấu hình cho thư viện Chat, hãy truyền thêm tham số `acsEndpoint` vào `ChatModuleConfig`.

**Mã mẫu tích hợp:**
```dart
chatModuleConfigProvider.overrideWithValue(
  ChatModuleConfig(
    backendBaseUrl: AppConfig.authBaseUrl, // Đường dẫn BE nội bộ
    acsEndpoint: AppConfig.acsEndpoint,    // Đường dẫn ACS lấy từ .env
  )
)
```

## 2. Thay đổi luồng gọi API (Cần lưu ý cho Backend và Tester)

Thư viện đã thay đổi các API endpoint sử dụng nội bộ để khớp với chuẩn mới. Vui lòng đảm bảo Backend đã deploy các API này:

1. **Tạo phòng chat**:
   - Trước đây: `POST /conversations/direct`
   - Hiện tại: `POST /chat/create-room` với body `{"pid": "user_id"}`
2. **Lấy Token kết nối (Tham gia phòng)**:
   - Trước đây: `POST /chat/generate-acs-token` (cấp token chung)
   - Hiện tại: `POST /chat/join-room/{roomId}` (cấp token riêng cho từng phòng)
   - *Lưu ý: Bất cứ khi nào người dùng mở một phòng chat, thư viện sẽ tự động gọi API `join-room` này để lấy token và mở luồng nhận tin nhắn realtime.*

## 3. Cập nhật Model Dữ liệu (Dành cho Backend)

Thư viện đã được cập nhật logic để đọc chính xác các field dữ liệu mà Backend trả về dựa theo tài liệu API mới nhất. Backend vui lòng đảm bảo phản hồi JSON của các API `create-room` và `get-room-chats` đúng nguyên trạng các trường sau:

- Dùng `created` thay vì `createdAt`.
- Dùng `modified` thay vì `updatedAt`.
- Dùng `isRead` (boolean) để đánh dấu trạng thái tin nhắn (thư viện sẽ tự map sang unreadCount).
- Dùng `lastMessage` (string thuần) thay vì trả về một object phức tạp.
- Trả về danh sách `members` khi tạo phòng.

## 4. Kiểm thử luồng gửi và nhận tin nhắn
Hiện tại luồng Gửi tin nhắn (`/chat/send-message`) và nhận tin nhắn Realtime qua thư viện Native đã được đấu nối chuẩn xác. Ứng dụng chính có thể tiến hành test luồng này. Mọi thao tác chỉnh sửa/xoá tin nhắn đang được tạm gác lại ở giai đoạn này theo yêu cầu ưu tiên.
