# Chat Core Package — Review Kết Quả Fix (Part 4)

> **Ngày review:** 2026-08-24  
> **Commit gốc (review lần 3):** `e6f54033b5af05e5027cf29900808ba3d65eeb3c`  
> **Commit fix:** `b19db9234d9981620c21af6491273bc91bf573e5` (nhánh `feature/phase-02`)  
> **Phạm vi review chính:** `packages/chat_core` — 2 file thay đổi: `core/error/chat_api_exception.dart`, `features/conversation_list/data/datasources/conversation_remote_datasource_impl.dart`.  
> **Tiêu chuẩn review:** Senior Flutter Architect / SDK Engineer & Code Reviewer.

---

## 1. Tổng Quan Kết Quả Fix

| Issue từ P3 | Mức độ | Trạng thái tại `e6f5403` | Trạng thái tại `b19db92` | Đánh giá |
|---|:---:|:---:|:---:|---|
| **N-C3-1 / P1-5: `ChatApiException(statusCode: 200)` cho lỗi dữ liệu** | P1 | ❌ Chưa fix | ✅ **ĐÃ FIX CƠ BẢN** | 5/5 điểm chuyển sang `ChatDataException`; không còn `statusCode: 200` trong `chat_core`. |
| **N2: Strict validation response REST** | TB | ✅ Đã fix | ✅ **GIỮ NGUYÊN** | Không thấy regression. |
| **Đổi tên `WebSocketRealtimeDataSourceImpl`** | P2 | ✅ Đã fix | ✅ **GIỮ NGUYÊN** | Alias tương thích vẫn hoạt động theo thiết kế P3. |
| **Deprecated `acsEndpoint`** | P2 | ✅ Giữ nguyên | ✅ **GIỮ NGUYÊN** | Không regression. |
| **N-C3-4: Thiếu test success/failure contract** | P2/P3 | ⚠️ Mở | ❌ **VẪN MỞ** | Không có test mới cho `ChatDataException` và datasource hội thoại. |
| **Barrel export toàn bộ Data layer** | P2 | ⚠️ Mở | ❌ **VẪN MỞ** | `chat_core.dart` vẫn export datasource/repository impl. |
| **N3: Hành vi `normalizeAcsId` cần verify BE** | TB/P2 | ⚠️ Mở | ⚠️ **VẪN MỞ** | Logic không đổi. |
| **Hardcoded Vietnamese text (i18n)** | P1 chấp nhận được | ⚠️ Mở | ⚠️ **VẪN MỞ** | Các message lỗi mới tiếp tục dùng tiếng Việt. |
| **N-C3-3: Naming native/websocket bất đối xứng** | P3 | ⚠️ Mở | ❌ **VẪN MỞ** | Dời sang bản major như kế hoạch trước. |
| **N1 / N4 / N5: false-positive, static resolver, giả định UTC** | Thấp | ⚠️ Mở | ❌ **KHÔNG ĐỔI** | Giữ nguyên từ P3. |

**Nhận xét nhanh:** Commit này đã xử lý trọn vẹn mục tiêu chính của vòng P4 là loại bỏ exception dữ liệu giả định HTTP `200`. Fix hướng đúng, tối thiểu và giữ tương thích ngược; tuy nhiên chưa có test khóa hành vi và thiết kế `statusCode` của exception mới còn một điểm cần làm rõ.

---

## 2. Đánh Giá Chi Tiết

### 2.1 Tách `ChatDataException` ✅ ĐẠT CƠ BẢN

**Thay đổi:**

```dart
class ChatDataException extends ChatApiException {
  ChatDataException({
    required super.code,
    required super.message,
    super.statusCode = 422,
  });

  @override
  String toString() => 'ChatDataException($code): $message';
}
```

Vị trí: `chat-module-mvp/packages/chat_core/lib/core/error/chat_api_exception.dart:35`.

**Các điểm đã chuyển đổi:**

| Method | Lỗi dữ liệu | Vị trí tại `b19db92` |
|---|---|---|
| `getOrCreateDirectConversation` | `CREATE_ROOM_NULL_DATA` | `conversation_remote_datasource_impl.dart:47` |
| `createGroupConversation` | `CREATE_ROOM_NULL_DATA` | `conversation_remote_datasource_impl.dart:121` |
| `uploadRoomAvatar` | `UPLOAD_EMPTY_URL` | `conversation_remote_datasource_impl.dart:303` |
| `uploadFileViaSas` | `SAS_URL_MISSING` | `conversation_remote_datasource_impl.dart:377` |
| `uploadFileViaSas` | `FINAL_FILE_URL_MISSING` | `conversation_remote_datasource_impl.dart:467` |

**Đánh giá:**

- ✅ Đúng yêu cầu P3: lỗi “HTTP thành công nhưng payload không dùng được” không còn bị mô tả sai là HTTP `200`.
- ✅ `ChatDataException extends ChatApiException` giúp giữ tương thích ngược: consumer đang catch `ChatApiException` vẫn nhận được lỗi.
- ✅ Override `toString()` giúp log phân biệt rõ lỗi dữ liệu và lỗi transport/API.
- ✅ Class được export sẵn qua barrel hiện tại nên caller của package có thể dùng trực tiếp khi cần catch riêng.
- ✅ Kiểm tra tĩnh tại commit: `chat_core` không còn occurrence `statusCode: 200`.

**Lưu ý thiết kế:** xem finding `N-C4-1` bên dưới về giá trị `statusCode = 422` tổng hợp.

---

## 3. Vấn Đề Mới / Lưu Ý Của Vòng Này

| ID | Mức độ | Vấn đề | Vị trí | Khuyến nghị |
|---|:---:|---|---|---|
| **N-C4-1** | P3 | `ChatDataException` mặc định gán `statusCode = 422`, trong khi doc comment nói đây không phải lỗi HTTP 4xx/5xx. Giá trị này là trạng thái tổng hợp nhưng dễ bị telemetry/retry logic hiểu nhầm là HTTP response thật. | `chat_api_exception.dart:35-45` | Nếu chấp nhận breaking change, tách hẳn hierarchy: `ChatException` cha, `ChatApiException` có HTTP status, `ChatDataException` không status. Nếu giữ tương thích MVP, thêm contract rõ ràng: ví dụ `bool get isHttpError => false`, tài liệu hóa rõ `422` là synthetic status và thêm test tránh drift. |
| **N-C4-2** | P2 | Chưa có test chuyên biệt cho contract mới: `data == null` phải ném `ChatDataException`, không phải `ChatApiException(statusCode: 200)`; các lỗi HTTP thật vẫn phải giữ `ChatApiException`. | `chat_core/test/` | Thêm test cho `getOrCreateDirectConversation`, `createGroupConversation` và ít nhất một flow upload để khóa type + code + status semantics. |
| **N-C4-3** | P3 | Commit trộn nhiều phạm vi: fix `chat_core`, tối ưu image/link preview/upload ở `chat_ui`, sửa docs và xóa toàn bộ review P2/P3. Điều này giảm khả năng trace review history trên nhánh hiện tại. | Toàn bộ commit | Tách commit theo module hoặc ít nhất giữ review history. Khi thêm `p4`, cân nhắc merge lại các report cũ hoặc lưu archive trước khi xóa. |

---

## 4. Trạng Thái Các Issue Carryover

| ID | Trạng thái | Ghi chú tại `b19db92` |
|---|:---:|---|
| **N3 — `normalizeAcsId`** | ⚠️ Mở | Logic cắt `8:acs:` và phần sau `_` giữ nguyên; vẫn cần verify với dữ liệu thật từ ACS/BE trước khi phát hành SDK công khai. |
| **N1 — `updateType.contains('name')`** | ⚠️ Mở | `message_remote_datasource_impl.dart:156` vẫn có thể false-positive với chuỗi chứa substring. |
| **N4 — `customResolver` static mutable** | ⚠️ Mở | `system_message_text.dart` không thay đổi. |
| **N5 — `parseEventDate` giả định UTC** | ⚠️ Mở | `message_model.dart:79` vẫn cần chốt contract timezone với BE. |
| **Barrel layer leak** | ⚠️ Mở | `chat_core.dart:68-90` vẫn export data sources, impls và repository implementations. |
| **Test coverage realtime/system message** | ⚠️ Mở | Không có test reconnect/re-enter rooms hoặc `SystemMessageTextBuilder`. |

---

## 5. Điểm Số Cập Nhật (Scorecard P4)

| Tiêu chí | P3 (`e6f5403`) | P4 (`b19db92`) | Thay đổi |
|---|:---:|:---:|---|
| Architecture | 7.5 | **7.5** | — |
| Maintainability | 7.5 | **7.5** | Exception rõ hơn, nhưng thiếu test khóa contract. |
| Readability | 7.5 | **7.5** | — |
| Performance | 7.5 | **7.5** | — |
| API Efficiency | 8.0 | **8.5** | +0.5: semantic lỗi dữ liệu chính xác hơn. |
| Memory Safety | 7.0 | **7.0** | — |
| Crash Safety | 7.5 | **7.5** | — |
| Testability | 6.0 | **6.0** | Chưa thêm test cho thay đổi này. |
| Extensibility | 7.0 | **7.5** | +0.5: có thể phân biệt lỗi dữ liệu qua subtype. |
| Public API Design | 6.5 | **6.5** | Subtype hữu ích; trừ điểm do synthetic status và barrel leak. |
| **Production Readiness** | **7.5** | **7.5** | Sẵn sàng nội bộ tốt hơn, chưa đủ điều kiện SDK công khai. |

---

## 6. Kiểm Tra Đã Thực Hiện

- ✅ So sánh `git diff e6f5403..b19db92` cho phạm vi liên quan và xác nhận chỉ 2 file `chat_core` thay đổi: +18/-10.
- ✅ `git diff --check` cho 2 file `chat_core`: pass.
- ✅ Tìm kiếm tại commit: không còn `statusCode: 200` trong `chat_core`.
- ✅ Xác nhận 5/5 call site đã dùng `ChatDataException`.
- ✅ Tìm kiếm consumer ngoài `chat_core` tại commit: chưa thấy catch riêng `ChatDataException`, nên việc kế thừa `ChatApiException` giữ tương thích là phù hợp giai đoạn MVP.
- ⚠️ **Không chạy được `dart pub get`, `dart analyze`, `dart test`** trong môi trường review vì runtime cần ghi cache/SDK ngoài sandbox và cơ chế phê duyệt execution bị từ chối. Đây là giới hạn môi trường, không phải lỗi phát hiện từ source. Nên chạy lại locally trước khi merge.

---

## 7. Kết Luận

### Đã làm tốt trong vòng này:
1. ✅ Khép lại P1 duy nhất còn mở từ P3: hết exception dữ liệu mang `statusCode: 200`.
2. ✅ Thiết kế fix nhỏ, tập trung và giữ backward compatibility.
3. ✅ Log lỗi rõ nghĩa hơn nhờ `ChatDataException` và `toString()` riêng.

### Cần làm tiếp (ưu tiên giảm dần):
1. **P2:** Thêm unit test khóa contract `ChatDataException` cho null/missing payload và test `ChatApiException` cho HTTP failure thật.
2. **P3:** Làm rõ `statusCode = 422` là synthetic hay chuyển sang error hierarchy không phụ thuộc HTTP status.
3. **P2:** Verify `normalizeAcsId` và timezone parsing với contract BE/ACS thật.
4. **P3:** Giữ review history hoặc archive trước khi xóa các report cũ.
5. **P2/P3:** Bổ sung coverage realtime reconnect/re-enter rooms, system message builder và REST failure contracts.
6. **Major:** Dọn barrel public API và đổi tên native → websocket đồng bộ interface/file.

### Verdict:
```text
🟢 READY CHO RELEASE NỘI BỘ (fix P1 chính xác, không thấy blocker mới)
🟡 CẦN TEST + CHỐT ERROR/TIMEZONE CONTRACT TRƯỚC KHI PHÁT HÀNH SDK CÔNG KHAI
```
