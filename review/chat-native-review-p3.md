# Chat Native Platform Interface — Review Kết Quả Fix (Part 3)

> **Ngày review:** 2026-08-23
> **Commit gốc (review lần 2):** `3355e8ee1b25515a105215cf1ea5f20a17a36c37` (file `review/chat-native-review-p2.md`)
> **Commit fix:** `e6f54033b5af05e5027cf29900808ba3d65eeb3c` (nhánh `feature/phase-02`)
> **Phạm vi review:** Tàn dư của `chat_native_platform_interface` sau khi package đã bị xoá — đặt tên `NativeRealtimeDataSource*`, README, `MIGRATION_GUIDE_V2.md`, cấu hình deprecated, barrel file.

---

## 1. Tổng Quan Commit Fix

Package `chat_native_platform_interface` đã bị xoá hoàn toàn từ commit `3355e8ee` (đánh giá ĐẠT ở P2). Vì vậy phạm vi review vòng này là **2 hạng mục còn mở của P2**:

| Hạng mục mở từ P2 | Trạng thái P2 | Thay đổi tại e6f5403 |
|---|:---:|---|
| Đổi tên class `NativeRealtimeDataSourceImpl` → `WebSocketRealtimeDataSourceImpl` | ⚠️ Fix một phần | Đổi tên class thật + typedef tương thích ngược + cập nhật doc comment |
| Cập nhật README / tài liệu | ❌ Chưa fix | Xoá dependency block khỏi README gốc, viết lại phần lớn `chat-module-mvp/README.md` |

Commit đồng thời siết validation response REST trong `chat_core` (thuộc phạm vi `chat-core-review-p2.md` — không đánh giá lại ở đây).

---

## 2. Bảng Trạng Thái Fix Chi Tiết

| Issue (từ P2) | Mức độ | Trạng thái P2 | Trạng thái tại e6f5403 | Đánh giá |
|---|:---:|:---:|:---:|---|
| **Đổi tên class `NativeRealtimeDataSourceImpl` → `WebSocketRealtimeDataSourceImpl`** | P2 | ⚠️ Fix một phần (chỉ thêm typedef ngược) | ✅ **ĐÃ FIX** | Class thật đã mang tên mới, tên cũ là alias — đúng chiều khuyến nghị |
| **README gốc: xoá block dependency package đã xoá** | P2 | ❌ | ✅ **ĐÃ FIX** | Block `chat_native_platform_interface` + tip line đã cập nhật |
| **`chat-module-mvp/README.md`: viết lại kiến trúc** | P2 | ❌ | ⚠️ **FIX PHẦN LỚN** | Tiêu đề/kiến trúc/bootstrap/checklist ACS SDK đã sửa; còn sót checklist trỏ file không tồn tại |
| **README gốc: đoạn intro vẫn mô tả "ACS SDK native cho Realtime"** | P2 | ❌ | ❌ **VẪN SÓT** | `README.md:3` mâu thuẫn trực tiếp với tip line 31 |
| **`MIGRATION_GUIDE_V2.md`: ghi nhận việc loại bỏ package** | P2 | ❌ (khuyến nghị) | ❌ **CHƯA FIX** | Vẫn hướng dẫn cấu hình `ACS_ENDPOINT` + realtime "qua thư viện Native" |
| **§3.1 Naming: interface `NativeRealtimeDataSource`, tên file, `AcsUserUtils`** | P2 | ⚠️ | ⚠️ **FIX MỘT PHẦN** | Interface có alias `WebSocketRealtimeDataSource` + doc mới; tên file & `AcsUserUtils` chưa đổi |
| **§3.2 Barrel file export tên cũ** | P3 | ⚠️ | ❌ **CHƯA FIX** | `chat_core.dart:76-77` vẫn export `native_realtime_datasource*.dart` |
| **Deprecated `acsEndpoint` trong `ChatModuleConfig`** | P2 | ✅ | ✅ **GIỮ NGUYÊN** | `chat_module_config.dart:7,25-27` vẫn optional + `@deprecated`, không regression |

---

## 3. Đánh Giá Chi Tiết

### 3.1 Đổi Tên Realtime DataSource — ✅ ĐẠT (hoàn tất nửa còn lại của P2)

**Trước fix (3355e8e) — typedef ngược, class vẫn tên cũ:**

```dart
// native_realtime_datasource_impl.dart
typedef WebSocketRealtimeDataSourceImpl = NativeRealtimeDataSourceImpl;

class NativeRealtimeDataSourceImpl implements NativeRealtimeDataSource { ... }
```

**Sau fix (e6f5403):**

```dart
// native_realtime_datasource.dart
typedef WebSocketRealtimeDataSource = NativeRealtimeDataSource;

/// Nguồn dữ liệu realtime qua kết nối WebSocket Backend.
abstract class NativeRealtimeDataSource { ... }

// native_realtime_datasource_impl.dart
/// Alias tương thích ngược cho tên cũ.
typedef NativeRealtimeDataSourceImpl = WebSocketRealtimeDataSourceImpl;

/// Realtime app-wide qua backend WebSocket.
class WebSocketRealtimeDataSourceImpl implements NativeRealtimeDataSource { ... }
```

**Đánh giá:** ✅ **ĐẠT**
- Đúng khuyến nghị review lần 1: **tên mới là class thật, tên cũ là alias** — đảo ngược lại cách làm ngược ở `3355e8e`.
- Doc comment cả 2 file đã mô tả đúng thực tế (WebSocket Backend), không còn nói về EventChannel/ACS token.
- **Không breaking:** điểm khởi tạo duy nhất `chat_ui/.../shared_providers.dart:61` vẫn dùng `NativeRealtimeDataSourceImpl(...)` và resolve qua alias — đã verify toàn repo không còn chỗ nào gãy.
- **Phần còn lại (chấp nhận được, xử lý ở bản major):** tên file vật lý vẫn là `native_realtime_datasource*.dart`, interface vẫn tên `NativeRealtimeDataSource` (alias mới chỉ che tên, chưa đổi thật), `AcsUserUtils` và `MessageModel.fromAcsJson` vẫn giữ prefix "Acs". Chuỗi naming này nên được dọn đồng loạt trong một PR đổi tên riêng để tránh breaking diện rộng.

---

### 3.2 README / Tài Liệu — ⚠️ FIX PHẦN LỚN, CÒN 3 ĐIỂM SÓT

#### ✅ Đã làm đúng:
- **`README.md` gốc:** xoá hoàn toàn block khai báo dependency `chat_native_platform_interface` (fix đúng khuyến nghị #1 của P2 — host app không còn bị hướng dẫn thêm package chết); tip line bổ sung rõ: *"Realtime sử dụng kết nối WebSocket thuần Dart nên không yêu cầu cài đặt thêm native SDK plugin"*.
- **`chat-module-mvp/README.md`:** tiêu đề đổi sang "Clean Architecture + WebSocket Realtime"; danh sách package còn 2 (`chat_core`, `chat_ui`); bỏ mục sinh Android project cho `example/`; bỏ các checklist item verify ACS SDK Android/iOS; mô tả `melos bootstrap` cập nhật đúng.

#### ❌ Điểm sót 1 — Intro README gốc vẫn mô tả kiến trúc cũ (`README.md:3`):
> "...Azure Communication Services (ACS) SDK native cho kết nối Realtime, và Hive để lưu Cache dữ liệu offline."

Câu này mâu thuẫn trực tiếp với tip line 31 (WebSocket thuần Dart) và với thực tế package ACS đã xoá. Host app đọc intro sẽ hiểu nhầm vẫn cần ACS SDK. heading `README.md:103` "(Native Realtime & Heartbeat)" cũng cùng vấn đề (nội dung bên trong đã mô tả WebSocket đúng, chỉ heading sai).

#### ❌ Điểm sót 2 — Checklist trỏ vào file không còn tồn tại (`chat-module-mvp/README.md:30-35`):
> "- [ ] Verify `api-version` của ACS Chat REST API dùng trong `chat_core/lib/data/rest/acs_rest_chat_repository.dart`..."

Đã verify tại revision `e6f54033`: **file `acs_rest_chat_repository.dart` không tồn tại** (thư mục `lib/data/rest/` không còn; `git ls-tree` chỉ ra `acs_user_utils.dart` là file duy nhất mang prefix "acs"). Checklist item này là tài liệu chết, cần xoá hoặc viết lại theo REST client hiện hành.

#### ❌ Điểm sót 3 — `MIGRATION_GUIDE_V2.md` chưa cập nhật (khuyến nghị #3 của P2):
- Dòng 10-11, 18: vẫn hướng dẫn thêm biến môi trường `ACS_ENDPOINT` và truyền `acsEndpoint` vào `ChatModuleConfig` — field này hiện đã `@deprecated`.
- Dòng 46: vẫn mô tả nhận tin Realtime *"qua thư viện Native"*.
- Là tài liệu migration chính thức, để nguyên sẽ khiến đội tích hợp làm theo cấu hình đã bị loại bỏ. Cần thêm section "V2 → V2.1: Gỡ ACS Native, chuyển WebSocket Backend" hoặc đánh dấu cả file là legacy.

---

### 3.3 Các Hạng Mục Khác

- **Deprecated `acsEndpoint`:** giữ nguyên trạng thái ĐẠT của P2 — optional, default `''`, field có `@deprecated` + doc note "Di sản". Không có regression.
- **CODEOWNERS / `melos.yaml` / pubspec:** không còn tham chiếu package đã xoá (CODEOWNERS entry đã xoá từ `3355e8ee`). Lưu ý phụ: `melos.yaml` vẫn liệt kê `- example` trong `packages:` dù không tồn tại thư mục `example/` ở root — đây là trạng thái có sẵn từ trước (đã có từ `eb7797a`), không phải regression, có thể tiện tay dọn.
- **`issue.md`:** còn nhắc `chat_native_platform_interface` (dòng 4, 94, 96) — đây là tài liệu ghi nhận issue lịch sử, **không cần sửa**.

---

## 4. Vấn Đề Còn Tồn Tại Sau Vòng Này

| ID | Mức độ | Vấn đề | Vị trí | Khuyến nghị |
|---|:---:|---|---|---|
| **N-Q3-1** | P2 | Intro README gốc vẫn quảng bá "ACS SDK native cho Realtime", heading mục 4 ghi "Native Realtime" | `README.md:3`, `README.md:103` | Sửa intro sang "WebSocket Backend thuần Dart"; heading → "WebSocket Realtime & Heartbeat" |
| **N-Q3-2** | P2 | Checklist trỏ file không tồn tại `acs_rest_chat_repository.dart` | `chat-module-mvp/README.md:30-35` | Xoá item chết hoặc viết lại theo REST client hiện tại |
| **N-Q3-3** | P2 | `MIGRATION_GUIDE_V2.md` vẫn hướng dẫn cấu hình `ACS_ENDPOINT` + realtime Native | `chat-module-mvp/MIGRATION_GUIDE_V2.md:10-18,46` | Thêm section migration gỡ ACS hoặc treo nhãn legacy toàn file |
| **N-Q3-4** | P3 | Tên file vật lý `native_realtime_datasource*.dart`, interface `NativeRealtimeDataSource`, barrel `chat_core.dart:76-77` chưa đổi | `chat_core` | Đổi tên đồng loạt file + interface + export trong một PR major (kèm alias tương thích như đã làm với class impl) |
| **N-Q3-5** | P3 | Tàn dư naming "Acs": `AcsUserUtils`, `MessageModel.fromAcsJson`, `myAcsUserId` | `core/utils/acs_user_utils.dart`, `message_model.dart:21` | Đánh giá đổi tên ở bản major; nếu BE vẫn dùng format JSON gốc ACS thì thêm doc comment giải thích |

---

## 5. Kết Luận

```text
⚠️ GẦN HOÀN TẤT — Phần code của P2 đã khép lại, phần tài liệu còn 3 điểm sót
```

> **Đánh giá tổng thể:**
> Vòng fix này giải quyết đúng và gọn hạng mục khó nhất còn lại của P2 — rename class `WebSocketRealtimeDataSourceImpl` đúng chiều khuyến nghị, có typedef tương thích ngược, không gây breaking (đã verify điểm khởi tạo duy nhất tại `shared_providers.dart:61`). Tài liệu được dọn phần lớn: dependency chết đã gỡ khỏi README gốc, README module viết lại theo kiến trúc WebSocket.
>
> **Điểm cần hoàn thiện (toàn bộ thuộc nhóm tài liệu/naming, không có rủi ro runtime):**
> 1. **N-Q3-1:** Intro `README.md` vẫn mô tả ACS SDK native — cần sửa ngay vì là dòng đầu tiên host app đọc.
> 2. **N-Q3-2 & N-Q3-3:** Checklist trỏ file chết và `MIGRATION_GUIDE_V2.md` lỗi thời — gây nhiễu cho đội tích hợp.
> 3. **N-Q3-4 & N-Q3-5:** Dọn nốt chuỗi naming "Native/Acs" (file, interface, barrel, utils) trong một PR đổi tên riêng ở bản major kế tiếp.
