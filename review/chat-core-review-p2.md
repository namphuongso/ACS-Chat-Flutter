# Chat Core Package — Review Kết Quả Fix (Part 2)

> **Ngày review:** 2026-08-22
> **Commit gốc (review lần 1):** `eb7797a91c1521ae493d846eadc8e4f77402e54e`
> **Commit fix:** `3355e8ee1b25515a105215cf1ea5f20a17a36c37`
> **Phạm vi:** `packages/chat_core` + các thay đổi liên quan trong `packages/chat_ui`

---

## 1. Tổng Quan Kết Quả Fix

| Issue gốc | Mức độ | Trạng thái fix | Đánh giá |
|---|:---:|:---:|---|
| P0-1: Mất Realtime sau background → foreground | P0 | ✅ ĐÃ FIX | Đúng hướng, cần lưu ý edge case |
| P1-2: Pretty JSON log chạy mọi event | P1 | ✅ ĐÃ FIX | Chính xác theo khuyến nghị |
| P1-3: Quét mảng O(N²) trong `listMessages` | P1 | ✅ ĐÃ FIX | O(N) + hỗ trợ `updateType` từ BE |
| P1-4: Retry vô điều kiện khi 401/403/404 | P1 | ✅ ĐÃ FIX | Chính xác theo khuyến nghị |
| P1-5: `ChatApiException` với statusCode 200 | P1 | ❌ CHƯA FIX | Vẫn còn 5 chỗ |
| Hardcoded Vietnamese text trong Data Layer | P1 | ⚠️ FIX MỘT PHẦN | Tập trung 1 chỗ + hook `customResolver` |
| Barrel file export toàn bộ Data layer | P2 | ⚠️ FIX TỐI THIỂU | Chỉ bỏ 1 export |
| Loại bỏ `acsEndpoint` & dead code ACS | P2 | ✅ ĐÃ FIX | Deprecated + xoá dependency |
| Bổ sung Unit Test | P2 | ⚠️ FIX TỐI THIỂU | Chỉ cập nhật test hiện có |

---

## 2. Đánh Giá Chi Tiết Từng Issue

### 2.1 P0-1 — Mất Realtime sau Background → Foreground

**Cách fix:**
- Thêm `Set<String> _watchedRoomIds` song song với `_activeRoomIds`.
- `watchNewMessages()` thêm roomId vào cả 2 set.
- `leaveActiveRoom()` chỉ clear `_activeRoomIds`, giữ nguyên `_watchedRoomIds`.
- Khi reconnect (`type == 'connected'`), gửi `enter_room` cho `{..._activeRoomIds, ..._watchedRoomIds}`.
- `stopWatching(threadId)` xoá roomId khỏi cả 2 set (đúng: user chủ động rời thread).

**Đánh giá:** ✅ **ĐẠT** — Đúng theo khuyến nghị của review lần 1.

**Lưu ý / Edge case mới:**

1. **`_isAppPaused` chỉ reset trong `watchNewMessages()`:** Nếu user background → foreground → ở lại màn danh sách hội thoại (không mở thread), `_isAppPaused` vẫn `true`. Tuy nhiên `sendReadMessage` chỉ gọi từ thread context nên không ảnh hưởng thực tế. Chấp nhận được.

2. **`leaveActiveRoom()` gửi `leave_room` cho cả `_watchedRoomIds` nhưng không xoá:** Server sẽ nhận `leave_room` nhưng client vẫn giữ room trong `_watchedRoomIds`. Khi reconnect sẽ gửi lại `enter_room`. Đây là hành vi đúng (server-side leave chỉ là tối ưu bandwidth, client-side watch là để re-enter).

3. **`_threadIdsByRoom` không được clear trong `leaveActiveRoom()`:** Không gây lỗi vì `_isAppPaused` chặn `sendReadMessage`, nhưng nếu sau này có logic khác đọc `_threadIdsByRoom` sau khi pause thì cần xem xét.

---

### 2.2 P1-2 — Pretty JSON Log Chạy Mọi Event

**Cách fix:**
```dart
if (ChatLogger.enabled) {
  final prettyJson = const JsonEncoder.withIndent('  ').convert(event);
  ChatLogger.log('WebSocket event:\n$prettyJson');
}
```

**Đánh giá:** ✅ **ĐẠT** — Chính xác theo khuyến nghị. Không còn CPU overhead khi log tắt.

---

### 2.3 P1-3 — Quét Mảng O(N²) trong `listMessages`

**Cách fix:**
- Đổi vòng lặp từ `for (i = 0; i < length; i++)` + nested `for (j = i+1; ...)` thành **1 vòng lặp ngược** `for (i = length-1; i >= 0; i--)` với biến `nextPayload` lưu trạng thái event RoomUpdated liền kề phía trước (theo thứ tự thời gian).
- **Ưu tiên đọc `updateType` từ backend** (`payload['updateType']`): nếu có `name`/`avatar`/`all` thì set cờ trực tiếp, không cần so sánh.
- Fallback so sánh `roomName`/`avatarUrl` với `nextPayload` chỉ chạy khi không có `updateType`.

**Đánh giá:** ✅ **ĐẠT** — Thuật toán O(N), đồng thời tận dụng field `updateType` từ BE (giải pháp tối ưu nhất theo review lần 1).

**Lưu ý nhỏ:**
- `updateType.contains('name')` có thể match chuỗi không mong muốn (vd: `"rename"`). Nên dùng `==` hoặc `split` nếu BE trả nhiều giá trị. Rủi ro thấp vì BE kiểm soát giá trị.

---

### 2.4 P1-4 — Retry Vô Điều Kiện Khi 401/403/404

**Cách fix:**
```dart
} catch (e) {
  ChatLogger.error('join-room attempt failed (roomId=$roomId)', error: e);
  if (e is ChatApiException &&
      (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 404)) {
    rethrow;
  }
  retries--;
  ...
}
```

**Đánh giá:** ✅ **ĐẠT** — Chính xác theo khuyến nghị. Lỗi không phục hồi được rethrow ngay, không tốn 9s chờ.

---

### 2.5 P1-5 — `ChatApiException` với statusCode 200

**Đánh giá:** ❌ **CHƯA FIX**

Vẫn còn 5 chỗ trong `conversation_remote_datasource_impl.dart` ném `ChatApiException(statusCode: 200, ...)`:
- Dòng 48, 123, 306, 381, 472

**Khuyến nghị giữ nguyên:** Tách thành `ChatDataException` / `ChatParseException` cho lỗi parse/dữ liệu rỗng.

---

### 2.6 Hardcoded Vietnamese Text trong Data Layer (i18n)

**Cách fix:**
- Tạo `SystemMessageTextBuilder` (`domain/services/system_message_text.dart`, 379 dòng) — **single source of truth** cho việc sinh text tin hệ thống.
- Dùng chung cho cả 3 nguồn: REST history (`MessageModel.fromAcsJson`), Realtime (`NativeRealtimeDataSourceImpl`), và enrich tin thiếu text.
- Cung cấp **`customResolver` hook** (static callback) cho phép host app override toàn bộ text → hỗ trợ i18n.
- Xoá toàn bộ logic sinh text inline rải rác trong `MessageModel` và `NativeRealtimeDataSourceImpl`.

**Đánh giá:** ⚠️ **FIX MỘT PHẦN — CHẤP NHẬN ĐƯỢC**

- ✅ Đã giải quyết vấn đề **duplicate logic** giữa REST và WebSocket (nguy cơ lệch wording).
- ✅ Đã có cơ chế override cho i18n (`customResolver`).
- ⚠️ Text mặc định vẫn là tiếng Việt nằm trong core (chưa đẩy hoàn toàn về UI layer như khuyến nghị gốc). Tuy nhiên `customResolver` là giải pháp thực dụng, không breaking.
- ⚠️ `customResolver` là **static mutable state** — cần đảm bảo set trước khi bất kỳ message nào được parse. Nếu set muộn, các message đã parse trước đó sẽ giữ text cũ.

---

### 2.7 Barrel File / Public API

**Cách fix:**
- Bỏ export `message_resource_model.dart` khỏi barrel.
- Thêm export `system_message_text.dart` và `room_update_type.dart`.

**Đánh giá:** ⚠️ **FIX TỐI THIỂU** — Barrel vẫn export toàn bộ Data Models, Data Sources, Repository Impls. Vấn đề layer leak vẫn còn nguyên.

---

### 2.8 Loại Bỏ `acsEndpoint` & Dead Code ACS

**Cách fix:**
- `acsEndpoint`: từ `required` → `@deprecated this.acsEndpoint = ''` (optional, có default).
- Xoá hoàn toàn dependency `chat_native_platform_interface` khỏi `pubspec.yaml`.
- Xoá `ChatNativePlatformInterface? platform` và `AuthTokenRepository? authTokenRepository` khỏi constructor `NativeRealtimeDataSourceImpl`.
- Thêm `typedef WebSocketRealtimeDataSourceImpl = NativeRealtimeDataSourceImpl` để migration tên.
- Xoá package `chat_native_platform_interface` khỏi repo.

**Đánh giá:** ✅ **ĐẠT** — Sạch sẽ, không còn phụ thuộc rác. Deprecated thay vì xoá ngay là cách tiếp cận đúng cho backward compatibility.

---

### 2.9 Bổ Sung Unit Test

**Cách fix:**
- Cập nhật mock trong `group_conversation_test.dart` và `message_repository_cache_test.dart` cho signature mới.
- Thêm mock `getRoomUpdateTypes()` trả dữ liệu mẫu.

**Đánh giá:** ⚠️ **FIX TỐI THIỂU** — Không có test mới cho Realtime, Network Client, hay DataSource parsing. Coverage vẫn ~10%.

---

## 3. Các Thay Đổi Ngoài Phạm Vi Review (Phát Sinh Thêm)

### 3.1 `AcsUserUtils.normalizeAcsId` — Thay đổi hành vi

**Trước:** Cắt lấy phần **trước** dấu `_` đầu tiên.
**Sau:** Cắt lấy phần **sau** dấu `_` cuối cùng.

```dart
// Trước: "8:acs:guid_suffix" → "guid"
// Sau:   "8:acs:guid_suffix" → "suffix"
```

**Đánh giá:** ⚠️ **CẦN XÁC NHẬN** — Đây là thay đổi hành vi (behavioral change). Nếu format ACS ID thực tế là `8:acs:<guid>_<userId>` thì fix đúng. Nếu là `8:acs:<userId>_<suffix>` thì fix sai. Cần verify với dữ liệu thực tế từ backend.

### 3.2 `sendReadMessage` mở rộng target rooms

- Nhận thêm `roomId` optional.
- Gửi `read` đến **tất cả** rooms trong `_activeRoomIds ∪ _watchedRoomIds ∪ _threadIdsByRoom.keys`.
- Thêm `_isAppPaused` guard: không gửi read khi app background.

**Đánh giá:** ✅ Hợp lý. Gửi read cho tất cả active rooms đảm bảo không bỏ sót. `_isAppPaused` chống gửi read "ma" khi app ở background.

### 3.3 `watchListMessages()` bỏ tham số `roomId`

**Đánh giá:** ✅ Đúng — realtime là client-level, không cần roomId để watch list.

### 3.4 `MessageModel.fromAcsJson` cải thiện parsing

- Hỗ trợ `EventType`, `event_type` (case-insensitive).
- `parseEventDate()`: tự thêm `Z` nếu thiếu timezone → parse UTC đúng.
- `RoomUpdated` event dùng `eventId` từ server thay vì timestamp-based ID → chống duplicate.

**Đánh giá:** ✅ Cải thiện tốt, tăng robustness.

### 3.5 `PaginatedResult` thêm `totalCount`

**Đánh giá:** ✅ Hữu ích cho UI hiển thị tổng số tin nhắn.

### 3.6 `data == true` → `data != false`

Nhiều chỗ trong `ConversationRemoteDataSourceImpl` đổi từ strict `== true` sang lenient `!= false`.

**Đánh giá:** ⚠️ **CẨN THẬN** — `data != false` trả `true` cho cả `null`, `0`, `"string"`,... Nếu backend trả `null` khi lỗi, client sẽ hiểu nhầm là thành công. Nên giữ `== true` hoặc parse rõ ràng.

### 3.7 Soft-delete trong cache thay vì xoá hẳn

`MessageRepositoryImpl.deleteMessage` giờ cập nhật `deletedOn` trong cache thay vì xoá message khỏi list.

**Đánh giá:** ✅ Đúng — giữ tin soft-delete để UI hiển thị "(tin nhắn đã bị xoá)" thay vì biến mất.

### 3.8 `RoomUpdateType` entity + `getRoomUpdateTypes` API + `updateType` param

Thêm luồng: UI lấy danh sách loại cập nhật phòng từ BE → user chọn → truyền `updateType` khi gọi `updateRoomInfo`.

**Đánh giá:** ✅ Feature mới hoàn chỉnh, đi đúng Clean Architecture (entity → repository → use case → datasource).

---

## 4. Vấn Đề Mới Phát Sinh Từ Fix

| # | Vấn đề | Mức độ | File |
|---|---|:---:|---|
| N1 | `updateType.contains('name')` có thể false-positive | Thấp | `message_remote_datasource_impl.dart` |
| N2 | `data != false` quá lenient, `null` cũng thành `true` | Trung bình | `conversation_remote_datasource_impl.dart` |
| N3 | `AcsUserUtils.normalizeAcsId` đổi hành vi chưa rõ đúng/sai | Trung bình | `acs_user_utils.dart` |
| N4 | `SystemMessageTextBuilder.customResolver` là static mutable — race condition nếu set muộn | Thấp | `system_message_text.dart` |
| N5 | `parseEventDate` giả định server gửi UTC không có suffix — cần xác nhận | Thấp | `message_model.dart` |

---

## 5. Điểm Số Cập Nhật

| Tiêu chí | Trước fix | Sau fix | Thay đổi |
|---|:---:|:---:|:---:|
| Architecture | 7.0 | 7.5 | +0.5 (bỏ native dependency, thêm SystemMessageTextBuilder) |
| Maintainability | 6.5 | 7.5 | +1.0 (centralize text logic, giảm ~200 dòng inline) |
| Readability | 7.0 | 7.5 | +0.5 |
| Performance | 6.5 | 7.5 | +1.0 (fix P1-2, P1-3) |
| API Efficiency | 7.0 | 7.5 | +0.5 (fix P1-4) |
| Memory Safety | 7.0 | 7.0 | — |
| Crash Safety | 7.5 | 7.5 | — |
| Testability | 6.0 | 6.0 | — (không thêm test mới đáng kể) |
| Extensibility | 6.0 | 7.0 | +1.0 (customResolver hook) |
| Public API Design | 5.5 | 6.0 | +0.5 (deprecated acsEndpoint, bỏ 1 export) |
| **Production Readiness** | **6.5** | **7.5** | **+1.0** |

---

## 6. Kết Luận

### Đã làm tốt:
1. Fix P0-1 đúng cách, có thêm `_isAppPaused` bảo vệ bổ sung.
2. Fix P1-2, P1-3, P1-4 chính xác theo khuyến nghị.
3. Xoá sạch dependency `chat_native_platform_interface` — giảm phức tạp đáng kể.
4. `SystemMessageTextBuilder` là cải tiến kiến trúc tốt: single source of truth + extensibility hook.
5. Tận dụng `updateType` từ backend — giảm logic suy luận phía client.

### Cần làm tiếp (ưu tiên giảm dần):
1. **P1-5:** Tách `ChatApiException(statusCode: 200)` thành exception riêng.
2. **N2:** Xem lại `data != false` → nên giữ strict check hoặc parse rõ ràng.
3. **N3:** Xác nhận hành vi mới của `normalizeAcsId` với dữ liệu thực tế.
4. **Test coverage:** Bổ sung test cho `NativeRealtimeDataSourceImpl` (reconnect, re-enter rooms) và `SystemMessageTextBuilder`.
5. **Barrel file:** Dọn dẹp public API (P2, làm khi có thời gian).

### Verdict:
```text
🟢 READY CHO RELEASE NỘI BỘ (các issue P0/P1 quan trọng đã được fix)
🟡 CẦN FIX P1-5 + XÁC NHẬN N3 TRƯỚC KHI PHÁT HÀNH SDK CÔNG KHAI
```
