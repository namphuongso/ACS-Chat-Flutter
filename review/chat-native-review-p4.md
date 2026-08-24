# Chat Native Platform Interface — Review Kết Quả Fix (Part 4)

> **Ngày review:** 2026-08-24
> **Commit gốc (review lần 3):** `e6f54033b5af05e5027cf29900808ba3d65eeb3c` (file `review/chat-native-review-p3.md`)
> **Commit fix:** `b19db9234d9981620c21af6491273bc91bf573e5` (nhánh `feature/phase-02`)
> **Phạm vi review:** Các hạng mục còn mở của P3 — README intro/heading, checklist chết, `MIGRATION_GUIDE_V2.md`, naming tàn dư. Đồng thời đánh giá các thay đổi bổ sung trong cùng commit (exception handling, image decoding, link preview fetch).

---

## 1. Tổng Quan Commit Fix

Commit `b19db92` là một commit refactor tổng hợp với chủ đề *"optimize image decoding, link preview fetch, and REST exception handling"*. Ngoài phạm vi chính là fix 3 hạng mục tài liệu còn mở của P3, commit còn:

| Thay đổi | File | Phạm vi |
|---|---|---|
| Viết lại intro + xoá heading "Native Realtime & Heartbeat" khỏi README gốc | `README.md` | Fix N-Q3-1 |
| Xoá toàn bộ `chat-module-mvp/README.md` (chứa checklist chết) | `chat-module-mvp/README.md` | Fix N-Q3-2 |
| Viết lại `MIGRATION_GUIDE_V2.md` theo WebSocket Realtime | `chat-module-mvp/MIGRATION_GUIDE_V2.md` | Fix N-Q3-3 |
| Thêm class `ChatDataException` + refactor exception handling | `chat_api_exception.dart`, `conversation_remote_datasource_impl.dart` | Bổ sung |
| Tách `ImageDimensionUtils` với header parsing nhanh + fallback decode | `image_dimension_utils.dart` (mới), `message_media_upload_service.dart` | Bổ sung |
| Giới hạn cache LinkPreviewFetcher (100 entries FIFO) + timeout 1500ms + `ref.mounted` guard | `link_preview_fetcher.dart`, `thread_messages_notifier.dart` | Bổ sung |
| Xoá 6 file review cũ (P2/P3 của cả 3 module) | `review/*.md` | Housekeeping |

---

## 2. Bảng Trạng Thái Fix Chi Tiết

| Issue (từ P3) | Mức độ | Trạng thái P3 | Trạng thái tại b19db92 | Đánh giá |
|---|:---:|:---:|:---:|---|
| **N-Q3-1: Intro README quảng bá "ACS SDK native cho Realtime", heading "Native Realtime & Heartbeat"** | P2 | ❌ | ✅ **ĐÃ FIX** | Intro viết lại thành "WebSocket Backend cho kết nối Realtime"; heading cũ xoá hoàn toàn, thay bằng section "Tính năng thư viện hỗ trợ" mô tả đúng WebSocket Realtime |
| **N-Q3-2: Checklist trỏ file không tồn tại `acs_rest_chat_repository.dart`** | P2 | ❌ | ✅ **ĐÃ FIX** | Toàn bộ `chat-module-mvp/README.md` đã xoá — cách xử lý triệt để nhất, không còn tài liệu chết |
| **N-Q3-3: `MIGRATION_GUIDE_V2.md` hướng dẫn `ACS_ENDPOINT` + realtime Native** | P2 | ❌ | ✅ **ĐÃ FIX** | Viết lại toàn bộ: tiêu đề "V2.1 — WebSocket Realtime", block cảnh báo rõ ràng về việc loại bỏ `chat_native_platform_interface` + `acsEndpoint`; mẫu cấu hình chỉ dùng `backendBaseUrl` + `apiKey` |
| **N-Q3-4: Tên file/interface/barrel `native_realtime_datasource*.dart` chưa đổi** | P3 | ⚠️ | ❌ **GIỮ NGUYÊN** | Chưa xử lý — phù hợp với kế hoạch deferred đến bản major |
| **N-Q3-5: Tàn dư naming "Acs": `AcsUserUtils`, `MessageModel.fromAcsJson`, `myAcsUserId`** | P3 | ⚠️ | ❌ **GIỮ NGUYÊN** | Chưa xử lý — phù hợp với kế hoạch deferred đến bản major |

---

## 3. Đánh Giá Chi Tiết

### 3.1 N-Q3-1 — README gốc: Intro + Heading "Native Realtime" — ✅ ĐẠT

**Trước fix (e6f54033):**

```markdown
Module Chat SDK ... Azure Communication Services (ACS) SDK native cho kết nối Realtime ...
### 4. Kết nối Realtime & Tự động khôi phục (Native Realtime & Heartbeat)
```

**Sau fix (b19db92):**

```markdown
Module Chat SDK Flutter phục vụ tích hợp ... WebSocket Backend cho kết nối Realtime ...
## Tính năng thư viện hỗ trợ
- WebSocket Realtime với cơ chế tự động duy trì Heartbeat và Reconnect ...
```

**Đánh giá:** ✅ **ĐẠT**
- Intro dòng 3 đã nói đúng "WebSocket Backend cho kết nối Realtime", mâu thuẫn với tip line 30 đã được khắc phục.
- Section "Phase 02" cũ (chứa heading "Native Realtime & Heartbeat") đã bị xoá toàn bộ, thay bằng một section tính năng gọn gàng hơn mô tả đúng công nghệ WebSocket.
- Tip line 30: "Realtime sử dụng kết nối WebSocket thuần Dart nên không yêu cầu cài đặt native SDK plugin" — nhất quán với intro.

---

### 3.2 N-Q3-2 — Checklist trỏ file chết — ✅ ĐẠT

**Trước fix:** `chat-module-mvp/README.md` tồn tại với checklist item:
> `- [ ] Verify api-version của ACS Chat REST API dùng trong acs_rest_chat_repository.dart...`

File `acs_rest_chat_repository.dart` không tồn tại từ trước đó.

**Sau fix:** Toàn bộ file `chat-module-mvp/README.md` đã bị xoá (`D` trong git diff-tree).

**Đánh giá:** ✅ **ĐẠT**
- Cách xử lý triệt để nhất: xoá hẳn file chứa nội dung lỗi thời thay vì patch từng dòng.
- Nội dung hướng dẫn tích hợp đã chuyển sang `README.md` root (đã viết lại đồng thời trong commit này).
- Không mất thông tin hữu ích — các hướng dẫn khởi tạo, config, deep-link đã có sẵn ở README root.

---

### 3.3 N-Q3-3 — `MIGRATION_GUIDE_V2.md` lỗi thời — ✅ ĐẠT

**Trước fix (e6f54033):**
```markdown
1. Thêm biến ACS_ENDPOINT vào .env...
2. Khi khởi tạo ..., truyền thêm acsEndpoint vào ChatModuleConfig.
Nhận tin nhắn Realtime qua thư viện Native...
```

**Sau fix (b19db92):**
```markdown
> ⚠️ LƯU Ý: Package chat_native_platform_interface và cấu hình acsEndpoint
> hiện tại đã bị loại bỏ / đánh dấu legacy (@deprecated). Ứng dụng chính
> không cần khai báo native SDK hay truyền acsEndpoint nữa.

Ứng dụng chính chỉ cần truyền backendBaseUrl và apiKey...
Sử dụng kết nối WebSocket thuần Dart thông qua WebSocketRealtimeDataSourceImpl.
Không yêu cầu plugin Native Android/iOS riêng.
```

**Đánh giá:** ✅ **ĐẠT**
- Block cảnh báo ngay đầu file giúp host app đọc được ngay rằng ACS Native đã bị gỡ.
- Mã mẫu cấu hình cập nhật đúng: chỉ dùng `backendBaseUrl` + `apiKey`, bỏ `acsEndpoint`.
- Section "Thay đổi luồng gọi API" đã loại bỏ hướng dẫn `generate-acs-token` / `join-room` lấy token (không còn áp dụng khi chuyển sang WebSocket Backend).
- Phần Exception Handling bổ sung mô tả `ChatApiException` (HTTP 4xx/5xx) vs `ChatDataException` (parse/data null) — nhất quán với code thay đổi trong cùng commit.

---

### 3.4 N-Q3-4 & N-Q3-5 — Naming tàn dư — ❌ GIỮ NGUYÊN (đúng kế hoạch deferred)

Tại revision `b19db92`:
- File vật lý vẫn là `native_realtime_datasource.dart` + `native_realtime_datasource_impl.dart`
- Barrel `chat_core.dart` vẫn export 2 file trên
- `acs_user_utils.dart` vẫn tồn tại
- `MessageModel.fromAcsJson` và `myAcsUserId` vẫn giữ nguyên tên cũ

**Đánh giá:** Đây là 2 hạng mục P3 (ưu tiên thấp) đã được đánh dấu deferred đến bản major ở P3. Việc không xử lý trong commit fix này là **đúng kế hoạch**, không phải regression. Sẽ đánh giá lại khi có PR rename riêng.

---

### 3.5 Các Thay Đổi Bổ Sung (ngoài phạm vi P3)

#### 3.5.1 `ChatDataException` — ✅ ĐẠT

Thêm subclass `ChatDataException` kế thừa `ChatApiException` với default `statusCode: 422`.

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

**Điểm tốt:**
- Trước đây, dữ liệu null/sai format ném `ChatApiException(statusCode: 200)` — gây hiểu nhầm vì HTTP 200 là thành công.
- Sau fix, 5 chỗ trong `conversation_remote_datasource_impl.dart` chuyển sang `ChatDataException(code: '...', message: '...')` — ngữ nghĩa đúng: lỗi dữ liệu chứ không phải lỗi HTTP.
- Default `statusCode: 422` (Unprocessable Entity) phù hợp với ngữ nghĩa "dữ liệu không thể xử lý".

#### 3.5.2 `ImageDimensionUtils` — ✅ ĐẠT (có ghi chú phụ)

Tách logic đọc kích thước ảnh ra util riêng với chiến lược 2 tầng:
1. **Header parsing nhanh** (chỉ đọc 2048 bytes đầu file) cho PNG, JPEG (SOF scan), GIF, WebP (VP8/VP8L/VP8X)
2. **Fallback** `instantiateImageCodec` nếu header parse thất bại hoặc format không hỗ trợ

**Điểm tốt:**
- Giảm I/O đáng kể: trước đây đọc toàn bộ file vào memory (`file.readAsBytes()`) rồi decode; giờ chỉ cần đọc 2048 bytes cho ~95% ảnh phổ biến.
- Hỗ trợ đầy đủ các format ảnh phổ biến trong chat: PNG, JPEG, GIF, WebP (cả lossy VP8, lossless VP8L, extended VP8X).
- Fallback an toàn nếu header parse fail (ảnh corrupt hoặc format lạ).
- Có test riêng cho non-existent file và PNG header parse.

**Ghi chú phụ (không blocking):**
- JPEG parser chỉ scan trong 2048 bytes đầu; nếu EXIF/thumbnail data quá lớn (>2KB) đẩy SOF marker ra ngoài phạm vi, sẽ fallthrough sang fallback decode — chấp nhận được vì fallback vẫn trả kết quả đúng.
- WebP VP8L bit-packing parsing phức tạp nhưng implementation đúng spec; nếu sai sẽ fallback an toàn.

#### 3.5.3 LinkPreviewFetcher cache limit — ✅ ĐẠT

Thêm giới hạn cache 100 entries với eviction FIFO:

```dart
if (_cache.length >= 100) {
  _cache.remove(_cache.keys.first);
}
_cache[cleanUrl] = result;
```

**Đánh giá:** ✅ **ĐẠT** — Trước đây cache tăng trưởng không giới hạn (memory leak tiềm ẩn trong app chạy lâu). Dart `LinkedHashMap` giữ insertion order nên `.keys.first` luôn là entry cũ nhất. FIFO đơn giản nhưng đủ tốt cho use case này; LRU phức tạp hơn mà lợi ích không đáng kể ở quy mô 100 entries.

#### 3.5.4 ThreadMessagesNotifier — timeout + `ref.mounted` — ✅ ĐẠT

```dart
final previewData = await LinkPreviewFetcher.fetch(linkUrl)
    .timeout(const Duration(milliseconds: 1500));
finalMetaData = previewData.toJson();
if (ref.mounted) {
  final updatedMessages = _messages
      .map((m) => m.id == optimisticId ? m.copyWith(metadata: finalMetaData) : m)
      .toList();
  state = state.copyWith(messages: updatedMessages);
}
```

**Điểm tốt:**
- Timeout 1500ms ngăn chặn UI treo chờ link preview fetch (bên trong `LinkPreviewFetcher.fetch` đã có timeout 4s riêng, nhưng timeout ngoài này đảm bảo tổng thời gian chờ tối đa 1.5s kể cả DNS resolve chậm).
- `ref.mounted` guard tránh setState sau dispose — quan trọng khi user rời màn hình trong lúc đang fetch.
- Metadata được update lên optimistic message ngay khi fetch xong (trước đây chỉ đợi response từ server gửi tin nhắn mới hiển thị).

**Ghi chú phụ (không blocking):**
- `_messages` được capture sau khi `await` — giữa lúc fetch (tối đa 1.5s), nếu có message khác được thêm/xoá bởi luồng khác thì danh sách vẫn đúng vì map by `optimisticId`. An toàn.

---

### 3.6 Housekeeping — Xoá file review cũ

Commit đồng thời xoá 6 file:
- `review/chat-core-review-p2.md`, `review/chat-core-review-p3.md`
- `review/chat-native-review-p2.md`, `review/chat-native-review-p3.md`
- `review/chat-ui-review-p2.md`, `review/chat-ui-review-p3.md`

**Đánh giá:** Neutral — dọn dẹp workspace, không ảnh hưởng runtime. Các file này được restore lại trên nhánh `docs/p1` hiện hành.

---

## 4. Vấn Đề Còn Tồn Tại Sau Vòng Này

| ID | Mức độ | Vấn đề | Vị trí | Khuyến nghị |
|---|:---:|---|---|---|
| **N-Q4-1** | P3 | Tên file `native_realtime_datasource*.dart`, interface `NativeRealtimeDataSource`, barrel export chưa đổi | `chat_core/lib/features/thread/data/datasources/`, `chat_core.dart` | Deferred đến bản major — giữ nguyên kế hoạch |
| **N-Q4-2** | P3 | Tàn dư naming "Acs": `AcsUserUtils`, `MessageModel.fromAcsJson`, `myAcsUserId` | `core/utils/acs_user_utils.dart`, `message_model.dart` | Deferred đến bản major — giữ nguyên kế hoạch |

**Không có vấn đề P1/P2 nào còn mở trong phạm vi `chat_native_platform_interface`.**

---

## 5. Kết Luận

```text
✅ HOÀN TẤT — Toàn bộ hạng mục P2 của P3 đã fix, P3 giữ nguyên kế hoạch deferred
```

> **Đánh giá tổng thể:**
> Commit `b19db92` giải quyết triệt để cả 3 điểm sót tài liệu của P3:
>
> 1. **N-Q3-1** — README intro + heading đã viết lại đúng WebSocket Backend, nhất quán toàn văn bản.
> 2. **N-Q3-2** — File chứa checklist chết xoá hẳn, hướng dẫn tích hợp tập trung về README root.
> 3. **N-Q3-3** — Migration guide viết lại hoàn chỉnh với block cảnh báo rõ ràng, mã mẫu đúng, loại bỏ hướng dẫn ACS_ENDPOINT/join-room token.
>
> Các thay đổi bổ sung (ChatDataException, ImageDimensionUtils, LinkPreview cache limit, timeout/mounted guard) đều là cải tiến hợp lý với implementation chất lượng tốt và có test đi kèm.
>
> **Hạng mục còn lại (N-Q4-1, N-Q4-2):** toàn bộ là naming cleanup P3, đã có kế hoạch xử lý đồng loạt trong PR rename ở bản major. Không cần action thêm ở phase hiện tại.

---

*Bạn có muốn tôi tạo thêm file review cho `chat-core` và `chat-ui` ở cùng commit này không?*
