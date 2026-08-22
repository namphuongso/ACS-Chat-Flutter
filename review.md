# Code Review Result

## Tổng Kết

- **Đánh giá tuân thủ:** Nhánh `feature/phase-02` đã tái cấu trúc toàn diện, bám sát và tuân thủ chặt chẽ kiến trúc Clean Architecture + Feature-Based quy định trong [Project-guildline_and_structure_chat.md](file:///Users/namphuong/Documents/hieutt/ACS-Chat-Flutter/chat-module-mvp/Project-guildline_and_structure_chat.md).
- **Blocker:** **0** blocker (Tất cả unit tests và `flutter analyze` đều pass 100%, không có lỗi crash runtime).
- **Mức độ rủi ro tổng thể:** **Low** (Mã nguồn đã được module hoá, test tự động bao phủ các luồng cache/token/realtime/message).

---

## Findings & Resolved Actions

### [RESOLVED] Dọn dẹp export data model trong barrel file `chat_core.dart`

- **File/Line:** [chat_core.dart](file:///Users/namphuong/Documents/hieutt/ACS-Chat-Flutter/chat-module-mvp/packages/chat_core/lib/chat_core.dart)
- **Liên quan guideline:** Mục 2.1 (Cấu trúc `chat_core`).
- **Trạng thái:** **Đã xử lý (Fixed)**.
- **Chi tiết:** Đã xoá bỏ `export 'features/thread/data/models/message_resource_model.dart';` khỏi barrel file `chat_core.dart`. Lớp `chat_ui` chỉ tương tác với Domain Entity `MessageResource`.

---

### [RESOLVED] Hỗ trợ hook tùy biến chuỗi thông báo hệ thống / đa ngôn ngữ (i18n)

- **File/Line:** [system_message_text.dart](file:///Users/namphuong/Documents/hieutt/ACS-Chat-Flutter/chat-module-mvp/packages/chat_core/lib/features/thread/domain/services/system_message_text.dart#L12-L35)
- **Liên quan guideline:** Mục 3.1 (Domain Layer - Quản lý chuỗi thông báo hệ thống).
- **Trạng thái:** **Đã xử lý (Fixed)**.
- **Chi tiết:** Đã bổ sung `SystemMessageCustomResolver? customResolver` vào `SystemMessageTextBuilder` cho phép app host ghi đè chuỗi thông báo theo ngôn ngữ động hoặc cấu hình dịch tuỳ chỉnh.

---

### [RECOMMENDATION] Tách thêm các sub-widgets cho MessageInput trong Phase tiếp theo

- **File/Line:** [message_input.dart](file:///Users/namphuong/Documents/hieutt/ACS-Chat-Flutter/chat-module-mvp/packages/chat_ui/lib/features/thread/presentation/widgets/message_input.dart)
- **Liên quan guideline:** Mục 3.3 (Presentation Layer) trong `Project-guildline_and_structure_chat.md`.
- **Trạng thái:** **Khuyến nghị cho Phase 3**.
- **Chi tiết:** `ThreadScreen` và `MessageBubble` đã được tách nhỏ thành 15+ sub-widgets độc lập. Phần gallery trong `MessageInput` đang hoạt động ổn định và có thể tách thành `gallery_panel.dart` khi triển khai thêm tính năng chọn album/camera nâng cao.

---

## Guideline Compliance

| Hạng mục kiểm tra | Đánh giá | Ghi chú |
|---|---|---|
| **Cấu trúc thư mục/module** | **PASS** | Tách biệt hoàn toàn `chat_core` (Domain + Data, không dính Flutter) và `chat_ui` (Presentation + Riverpod). |
| **Code đơn giản** | **PASS** | Tách trách nhiệm rõ ràng: Upload Media (`MessageMediaUploadService`), Reaction (`ThreadReactionsService`), Realtime (`NativeRealtimeDataSourceImpl`). |
| **Clean code** | **PASS** | Không có `// ignore` lạm dụng, không `print()`, sử dụng `ChatLogger` toàn diện, tuân thủ immutable state. |
| **API data validation** | **PASS** | Kiểm tra an toàn `is Map`, `is List`, fallback URL decode, an toàn timestamp UTC/Local, an toàn null-safety. |
| **Error handling** | **PASS** | Không nuốt lỗi âm thầm; có retry, queue pending tin nhắn đã đọc (`_pendingReadMessageId`), fallback cache khi offline. |
| **Loading/empty/error UI** | **PASS** | Có shimmer / loading indicator, empty state khi tìm kiếm / tải tệp, toast báo lỗi thân thiện. |
| **Type safety** | **PASS** | Không dùng kiểu `dynamic` không kiểm soát, sử dụng Enum mở cho `MessageType` và record type cho pagination. |
| **Maintainability/extensibility** | **PASS** | Dễ mở rộng tính năng mới, phân tách use cases chuẩn Clean Architecture. |

---

## Crash / Wrong Behavior Risks

- Không phát hiện rủi ro crash runtime hoặc sai lệch hành vi chức năng trên toàn bộ nhánh `feature/phase-02`.
- Đã kiểm thử và giải quyết triệt để:
  1. Trùng lặp thông báo hệ thống khi cập nhật phòng chat.
  2. Bị kẹt cờ `_isAppPaused` khi đóng dialog/overlay reaction picker.
  3. Bỏ sót tệp đính kèm khi gửi nhiều file hoặc ảnh dung lượng lớn (> 100MB).
  4. Lỗi gửi trạng thái đọc (`sendReadMessage`) khi socket reconnect ngầm từ background.

---

## Required Fixes Before Merge

- **Không có required fix bắt buộc trước khi merge.** Nhánh `feature/phase-02` đã đạt tiêu chuẩn chất lượng để merge vào nhánh `Development`.

---

## Test Recommendations

- **Đã chạy và xác nhận tự động:**
  - `melos run analyze`: 0 errors, 0 warnings trên toàn bộ 2 packages (`chat_core`, `chat_ui`).
  - `melos run test`: 100% pass toàn bộ test suite (AuthToken dedup/cache, MessageRepository cache/offline fallback, Group Conversation, ChatDeepLinkData, RichMessageText, LastMessagePreview).
- **Kiểm thử thủ công khuyến nghị (Manual QA Checklist):**
  - Mở phòng chat, đưa app xuống background rồi quay lại foreground -> kiểm tra socket reconnect và packet `read` gửi chính xác.
  - Cập nhật tên nhóm và ảnh đại diện nhóm -> kiểm tra chỉ hiện 1 tin nhắn hệ thống duy nhất tương ứng với `updateType`.
  - Tải lên đồng thời nhiều hình ảnh và tài liệu dung lượng lớn -> kiểm tra render đầy đủ danh sách card tệp tin và tiến trình upload.
