# ACS-Chat-Flutter

Module Chat SDK được xây dựng trên nền tảng Flutter phục vụ tích hợp cho dự án NPP-Mobile. Dự án áp dụng Clean Architecture kết hợp với Riverpod để quản lý State và Hive để lưu Cache dữ liệu offline.

## Các tính năng và cập nhật mới (Phase 01)

### 1. Quản lý Tin nhắn (Message Management)
- **Cập nhật và Xóa tin nhắn**: Bổ sung `UpdateMessageUseCase` và `DeleteMessageUseCase` kết hợp với giao diện tương tác trực tiếp (edit/delete) trên tin nhắn của bản thân.
- **API Endpoints**: Khai báo và tích hợp các endpoint mới cho việc chỉnh sửa và xóa tin nhắn trong `chat_api_endpoints.dart`.

### 2. Cấu hình Giao diện động (Dynamic UI Styling)
- **ChatUiConfig**: Cung cấp cấu hình màu sắc, phông nền linh hoạt cho bong bóng chat (sent/received bubbles), nền màn hình chat, khung nhập tin nhắn và thanh tìm kiếm từ phía host app (NPP-Mobile).
- **customizable themes**: Cho phép ghi đè cấu hình thông qua `chatUiConfigProvider` để đồng bộ phong cách thiết kế của host app mà không cần can thiệp trực tiếp vào mã nguồn module.

### 3. Tối ưu hóa Trải nghiệm người dùng (UX/UI Improvements)
- **SearchField**: Widget tìm kiếm chung hỗ trợ tính năng debounce (mặc định 350ms) giúp giảm tần suất gọi API hoặc bộ lọc liên tục khi người dùng gõ từ khóa.
- **Skeleton Loaders**: Bổ sung hiệu ứng Shimmer Loading (`SkeletonBox`, `MessageListSkeleton`, `ConversationListSkeleton`) thay thế cho các vòng xoay loading truyền thống, giúp giao diện chuyển cảnh mượt mà hơn.
- **TabBar Customization**: Loại bỏ hoàn toàn lớp nền xám tối và hiệu ứng splash/highlight mặc định khi chuyển đổi tab giữa **Chat gần đây** và **Danh bạ** trong `ChatListPage`.

### 4. Hệ thống Cache Offline & Đồng bộ danh tính (Local Caching)
- **HiveIdentityStore**: Lưu trữ trực tiếp `myAcsUserId` xuống Hive dưới dạng local cache theo tài khoản người dùng (`currentUserId`). Khôi phục danh tính tức thì ngay khi mở màn hình chat để ngăn chặn tình trạng tin nhắn hiển thị sai phía (isMe sai lệch) trước khi kết nối mạng hoàn tất.
- **Hive Local Datasource**: Tối ưu hóa việc tải dữ liệu từ cache cục bộ cho cả danh sách cuộc hội thoại (`HiveConversationLocalDatasource`) và tin nhắn (`HiveMessageLocalDatasource`).