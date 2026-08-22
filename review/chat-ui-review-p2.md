# Chat UI Package — Review Kết Quả Fix (Part 2)

> **Ngày review:** 2026-08-23  
> **Commit gốc (review lần 1):** `eb7797a91c1521ae493d846eadc8e4f77402e54e` (file `review/chat-ui-review.md`)  
> **Commit fix:** `3355e8ee1b25515a105215cf1ea5f20a17a36c37` (bao gồm `8f8991d64dc9ebd21b17e89d198d4395f856b426`)  
> **Phạm vi review:** `packages/chat_ui` (~34 files thay đổi, +1.645 / -1.057 LOC trong package).  
> **Tiêu chuẩn review:** Senior Flutter Architect / SDK Engineer & Code Reviewer.

---

## 1. Tổng Quan Kết Quả Fix

| Issue gốc | Mức độ | Trạng thái fix | Đánh giá & Ghi chú |
|---|:---:|:---:|---|
| **P0-1: Rò rỉ `VideoPlayerController` tĩnh trong `VideoMessageContent`** | **P0** | ⚠️ **FIX MỘT PHẦN** | Đã xóa `static _controllerCache` và thêm `dispose()`, nhưng bubble vẫn tạo video player network thay vì thumbnail tĩnh |
| **P1-1: `TapGestureRecognizer` leak trong `RichMessageText`** | **P1** | ✅ **ĐÃ FIX** | Đã chuyển sang `StatefulWidget`, quản lý mảng `_recognizers` và dispose sạch |
| **P1-2: Listener `ScrollController` lặp trong `didChangeDependencies`** | **P1** | ✅ **ĐÃ FIX** | Đã chuyển sang `initState()`, đúng chuẩn lifecycle Flutter |
| **P1-3: Giải mã kích thước ảnh thô bằng `instantiateImageCodec` gây jank** | **P1** | ❌ **CHƯA FIX** | Tách sang `MessageMediaUploadService` nhưng bên trong vẫn giữ nguyên `instantiateImageCodec` trên Main Isolate |
| **P1-4: Treo đồng bộ 4s do Link Preview trước khi gửi tin** | **P1** | ❌ **CHƯA FIX** | `sendMessage()` vẫn `await LinkPreviewFetcher.fetch()` trước khi gán optimistic message |
| **P1-5: Tổng số tài nguyên phòng chat bị cắt cố định $\le 6$** | **P1** | ✅ **ĐÃ FIX** | `roomResourcePreviewProvider` đã ưu tiên đọc `totalCount` từ metadata |
| **P1-6: `VideoResourceThumbnail` khởi tạo controller hàng loạt trong Grid** | **P1** | ❌ **CHƯA FIX** | Vẫn dùng `VideoPlayerController` để seek thumbnail thay vì ảnh server |
| **P1-7: Vòng lặp `loadUntilMessage` quét 8 trang nền** | **P1** | ❌ **CHƯA FIX** | Vẫn còn vòng lặp quét 8 trang (`pagesFetched < 8`) trong `ThreadScreen` |
| **P2-1: Kích hoạt lại `ThreadState` (Model State bất biến)** | **P2** | ✅ **ĐÃ FIX** | `ThreadMessagesNotifier` đã kế thừa `Notifier<ThreadState>`, loại bỏ `state = [...state]` |
| **P2-2: Chia nhỏ God Class `ThreadScreen` & `ThreadMessagesNotifier`** | **P2** | ⚠️ **FIX MỘT PHẦN** | Đã tách `MessageMediaUploadService`, `ThreadReactionsService`, `MessageActionButton` nhưng màn hình vẫn >2.200 dòng |
| **P2-3: Khử trùng lặp logic tin nhắn hệ thống (System Message)** | **P2** | ✅ **ĐÃ FIX** | Chuyển toàn bộ sang dùng `SystemMessageTextBuilder` từ `chat_core` |
| **P2-4: Kết nối cấu hình `ChatUiConfig.onFileTap` (Dead Config)** | **P2** | ✅ **ĐÃ FIX** | `MediaContent` đã đọc `config.onFileTap` và kích hoạt đúng callback |
| **P2-5: Provider Overrides `late final _overrides` trong ThreadScreen** | **P2** | ✅ **ĐÃ FIX** | Đưa overrides trực tiếp vào `ProviderScope` trong `build()` |
| **P2-6: Bổ sung Test Coverage** | **P2** | ❌ **CHƯA FIX** | Chưa viết thêm test cho `chat_ui` (vẫn giữ nguyên 3 file test cũ) |

---

## 2. Đánh Giá Chi Tiết Từng Issue

### 2.1 P0-1 — Rò rỉ Bộ nhớ Native `VideoPlayerController` trong `VideoMessageContent`
- **Hiện trạng ban đầu:** `VideoMessageContent` giữ vĩnh viễn controller trong `static final Map<String, VideoPlayerController> _controllerCache`, không có `dispose()`, làm cạn kiệt Hardware Decoder.
- **Cách fix:**
  - Xóa bỏ `static _controllerCache` và `static _initFuturesCache`.
  - Bổ sung `dispose()` trong `_VideoMessageContentState` với `_controller?.dispose()`.
  - Dọn dẹp controller cũ trước khi khởi tạo controller mới.
- **Đánh giá:** ⚠️ **FIX MỘT PHẦN (CẦN LƯU Ý)**
  - **Điểm tốt:** Đã ngăn chặn rò rỉ bộ nhớ vĩnh viễn (static leak) khi người dùng thoát khỏi màn hình chat hoặc chuyển trang.
  - **Điểm còn tồn tại:** Trong bubble chat, widget vẫn gọi `VideoPlayerController.networkUrl(uri)` và `initialize()` trực tiếp khi render danh sách. Nếu một phòng chat có 10–20 video xuất hiện đồng thời trên viewport hoặc cuộn nhanh trong ListView, thiết bị vẫn có thể bị quá tải hardware codec đồng thời.
  - **Khuyến nghị tiếp theo:** Chuyển sang hiển thị ảnh Thumbnail tĩnh (hoặc Placeholder) trong chat bubble, chỉ khởi tạo `VideoPlayerController` khi người dùng chạm vào video để mở `ChatVideoPlayerDialog`.

---

### 2.2 P1-1 — `TapGestureRecognizer` Tạo Mới Trong `build()` Không Được Dispose
- **Hiện trạng ban đầu:** `RichMessageText` là `StatelessWidget`, tạo `TapGestureRecognizer` mới mỗi lần parse link trong `build()` mà không gọi `dispose()`.
- **Cách fix:**
  - Chuyển `RichMessageText` thành `StatefulWidget`.
  - Quản lý danh sách `final List<TapGestureRecognizer> _recognizers = [];`.
  - Gọi `_clearRecognizers()` trước mỗi lần build và giải phóng sạch trong `dispose()`.
- **Đánh giá:** ✅ **ĐÃ FIX HOÀN TOÀN** — Đúng chuẩn quản lý tài nguyên của Flutter framework, không còn rò rỉ Gesture Arena.

---

### 2.3 P1-2 — Listener của `ScrollController` Bị Gán Lặp Trong `didChangeDependencies`
- **Hiện trạng ban đầu:** `_scrollController.addListener(_maybeLoadMore)` được gọi trong `didChangeDependencies()`, dẫn đến việc bị add nhiều lần khi theme/route thay đổi.
- **Cách fix:**
  - Chuyển `_scrollController.addListener(_maybeLoadMore)` sang `initState()`.
  - Xóa bỏ lệnh add listener trong `didChangeDependencies()`.
- **Đánh giá:** ✅ **ĐÃ FIX HOÀN TOÀN** — Loại bỏ triệt để nguy cơ duplicate request phân trang khi cuộn danh sách hội thoại.

---

### 2.4 P1-3 — Giải Mã Kích Thước Ảnh Gốc Gây Drop Frame Main Isolate
- **Hiện trạng ban đầu:** `ThreadMessagesNotifier.sendImages` đọc toàn bộ byte ảnh và gọi `instantiateImageCodec(bytes)` trên UI thread để lấy `width` / `height`.
- **Cách fix trong commit:** Logic gửi ảnh được bóc tách từ `ThreadMessagesNotifier` sang service mới `MessageMediaUploadService`. Tuy nhiên bên trong `MessageMediaUploadService.sendImages`:
  ```dart
  final bytes = await file.readAsBytes();
  final codec = await instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  width = frame.image.width;
  height = frame.image.height;
  ```
- **Đánh giá:** ❌ **CHƯA FIX BẢN CHẤT**
  - Việc chuyển file giúp code gọn hơn nhưng chưa giải quyết vấn đề hiệu năng.
  - `instantiateImageCodec` vẫn chạy trên Main Isolate và nạp full bytes ảnh vào RAM.
  - **Khuyến nghị:** Sử dụng giải pháp đọc header kích thước nhẹ (như metadata reader) hoặc đưa qua `compute()`.

---

### 2.5 P1-4 — Treo Đồng Bộ Tối Đa 4 Giây Do Cào Link Preview Trước Khi Gửi
- **Hiện trạng ban đầu:** `ThreadMessagesNotifier.sendMessage()` gọi `await LinkPreviewFetcher.fetch(linkUrl)` trước khi tạo optimistic message chèn vào `state`.
- **Cách fix trong commit:** Code tại `thread_messages_notifier.dart:1120-1142` vẫn giữ nguyên:
  ```dart
  if (finalMetaData == null) {
    final urlMatch = RegExp(r'(https?://[^\s<]+)').firstMatch(content);
    if (urlMatch != null) {
      final linkUrl = urlMatch.group(0)!;
      final previewData = await LinkPreviewFetcher.fetch(linkUrl); // <-- Vẫn await trước!
      finalMetaData = previewData.toJson();
    }
  }
  final optimistic = Message(...);
  state = [...state, optimistic];
  ```
- **Đánh giá:** ❌ **CHƯA FIX**
  - Trải nghiệm UX vẫn bị khựng 2–4s khi người dùng gửi tin nhắn có URL do phải chờ fetch HTML trước khi bubble xuất hiện.
  - **Khuyến nghị:** Render bubble optimistic ngay lập tức với `content`, sau đó fetch preview bất đồng bộ và cập nhật metadata sau.

---

### 2.6 P1-5 — Tổng Số Lượng Tài Nguyên Phòng Chat Bị Cắt Cố Định $\le 6$
- **Hiện trạng ban đầu:** `roomResourcePreviewProvider` lấy `.length` của mảng phân trang (vốn chỉ fetch `pageSize: 3`), khiến số lượng hiển thị trên UI luôn $\le 6$.
- **Cách fix:**
  ```dart
  final total = (imageResult.totalCount ?? imageResult.items.length) +
      (videoResult.totalCount ?? videoResult.items.length);
  ```
- **Đánh giá:** ✅ **ĐÃ FIX HOÀN TOÀN** — Đã ưu tiên lấy `totalCount` từ metadata trả về của Backend.

---

### 2.7 P1-6 & P1-7 — Thumbnail Video Grid và Polling Tìm Kiếm
- **P1-6 (`VideoResourceThumbnail`):** ❌ **CHƯA FIX** — Vẫn tiếp tục khởi tạo `VideoPlayerController` để lấy thumbnail cho video trong `room_resources_category_screen`.
- **P1-7 (`loadUntilMessage` & Quét 8 trang nền):** ❌ **CHƯA FIX** — Vẫn giữ vòng lặp quét 8 trang trong `ThreadScreen._performMessageSearch`. Cần chuyển sang Search API ở backend khi có điều kiện.

---

### 2.8 Tái Cấu Trúc Kiến Trúc & State Management (P2 Issues)

#### A. Kích hoạt lại `ThreadState` (Model State bất biến)
- ✅ **Thành công lớn:** `ThreadMessagesNotifier` đã được refactor kế thừa `Notifier<ThreadState>`.
- Toàn bộ các trường `messages`, `pinnedMessages`, `reactionsMap`, `myAcsUserId`, `cursor` đã được gom về một Single Source of Truth.
- Loại bỏ hoàn toàn hack `state = [...state]` trước đây.

#### B. Thống nhất Xử lý Tin nhắn Hệ thống (System Message Builder)
- ✅ **Thành công lớn:** Đã xóa bỏ hơn 400 dòng code ghép chuỗi tiếng Việt hardcoded rải rác trong `ThreadMessagesNotifier`.
- Kết nối đồng bộ với `SystemMessageTextBuilder` từ `chat_core`, đồng thời hỗ trợ cập nhật `updateType` (Name / Avatar / All) khi sửa thông tin phòng.

#### C. Kết nối Cấu hình `ChatUiConfig.onFileTap`
- ✅ **Đã fix:** Trong `MediaContent._handleFileAction`, widget kiểm tra `config.onFileTap != null` và delegate cho host app xử lý, không còn bị dead config.

#### D. Quản lý Overrides trong `ThreadScreen`
- ✅ **Đã fix:** Bỏ biến `late final _overrides`, truyền dynamic overrides vào `ProviderScope` trong `build()` giúp cập nhật chuẩn khi `widget.roomId` thay đổi.

#### E. Tách nhỏ Notifier & Bổ sung Service
- Đã tách `MessageMediaUploadService` (xử lý upload SAS, tracking progress qua `mediaUploadProgressProvider`).
- Đã tách `ThreadReactionsService` (quản lý reaction configs và reaction summaries).
- Thêm dialog hỗ trợ gửi ảnh dung lượng lớn (>100MB) dưới dạng tệp tin (`showSendAsFileDialog`).

---

## 3. Bảng Tổng Hợp So Sánh Trước & Sau Khi Fix

```text
┌──────────────────────────────────────┬────────────────────────┬────────────────────────┐
│ Hạng mục / Tiêu chí                  │ Bản gốc (eb7797a)      │ Bản fix (3355e8e)      │
├──────────────────────────────────────┼────────────────────────┼────────────────────────┤
│ State Model                          │ Notifier<List<Message>>│ Notifier<ThreadState>  │
│ Video Message Controller Cache       │ Static Map (Leak P0)   │ Instance-based/Dispose │
│ Gesture Recognizer Lifecycle         │ Rò rỉ trong build()    │ Quản lý trong State    │
│ Scroll Listener Registration         │ didChangeDependencies  │ initState              │
│ Quản lý Tin nhắn Hệ thống            │ 400+ LOC hardcoded     │ SystemMessageTextBuilder│
│ onFileTap Configuration              │ Bị bỏ quên (Dead)      │ Kích hoạt đầy đủ       │
│ ProviderScope Overrides              │ late final (Stale bug) │ Re-evaluated in build  │
│ Resource Total Count                 │ Luôn <= 6              │ Đọc Backend totalCount │
│ Image Size Decode                    │ Main Isolate Codec     │ Chưa đổi (Vẫn Main)   │
│ Optimistic URL Send Latency          │ Block 2-4s             │ Vẫn block 2-4s        │
└──────────────────────────────────────┴────────────────────────┴────────────────────────┘
```

---

## 4. Điểm Đánh Giá Mới (Scorecard Update)

| Tiêu chí | Điểm cũ | Điểm mới | Nhận xét sau fix |
|---|:---:|:---:|---|
| **Architecture** | 6.0/10 | **7.5/10** | Kích hoạt lại `ThreadState`, tách các Service (`MediaUpload`, `Reactions`), dùng ProviderScope chuẩn. |
| **Maintainability** | 5.5/10 | **7.5/10** | Xóa bỏ trùng lặp system messages, gom logic upload và reaction riêng biệt. |
| **Readability** | 6.5/10 | **7.5/10** | Dọn dẹp Notifier gọn hơn ~300 dòng, code tách bạch rõ ràng. |
| **Performance** | 5.5/10 | **6.5/10** | Đã sửa listener cuộn lặp; vẫn còn điểm nghẽn decode ảnh và thumbnail video grid. |
| **API Efficiency** | 6.0/10 | **7.0/10** | Resource preview đếm chuẩn `totalCount`, hỗ trợ `updateType` đồng bộ với BE. |
| **Memory Safety** | 5.0/10 | **8.0/10** | Giải quyết xong 2 rò rỉ lớn nhất: `_controllerCache` tĩnh và `TapGestureRecognizer`. |
| **Crash Safety** | 7.0/10 | **8.0/10** | Đã xử lý `_overrides` stale, đồng bộ `ThreadState.hashCode`. |
| **Testability** | 4.0/10 | **4.0/10** | Chưa viết thêm test cho package `chat_ui`. |
| **Extensibility** | 5.5/10 | **7.0/10** | `onFileTap` đã hoạt động, system message cho phép inject resolver qua core. |
| **UI Customizability** | 5.0/10 | **5.5/10** | Có thêm config dialog & theme; chưa bổ sung builder delegates (Level B). |
| **Public API Design** | 6.0/10 | **6.5/10** | Clean hơn ở tầng Notifier, barrel file vẫn export một số provider nội bộ. |
| **Production Readiness**| **5.5/10** | **7.5/10** | **✅ READY FOR INTERNAL / STAGING RELEASE** (Đã giải phóng các blocker crash/leak chính). |

---

## 5. Kết Luận & Các Hạng Mục Cần Làm Tiếp (Next Steps)

### Đã hoàn thành xuất sắc:
1. Xóa bỏ hoàn toàn static leak `VideoPlayerController` trong tin nhắn video.
2. Sửa triệt để rò rỉ gesture recognizer trong `RichMessageText`.
3. Tái cấu trúc thành công `ThreadMessagesNotifier` sang `Notifier<ThreadState>`.
4. Chuẩn hóa hiển thị tin nhắn hệ thống qua `SystemMessageTextBuilder`.
5. Sửa lỗi đếm sai số lượng tài nguyên và kích hoạt lại `onFileTap`.

### Cần tối ưu thêm ở phase tiếp theo:
1. **Link Preview UX:** Chèn ngay optimistic bubble khi gửi tin chứa link, cào OpenGraph ngầm ở background.
2. **Decode Kích thước Ảnh:** Thay `instantiateImageCodec` bằng thư viện đọc header ảnh gọn nhẹ để tránh drop frame UI khi chọn nhiều ảnh.
3. **Thumbnail Video Grid:** Sử dụng ảnh tĩnh trả về từ CDN/Server cho video thay vì dùng `VideoPlayerController` trong GridView.
4. **Bổ sung Widget Tests:** Viết test tối thiểu cho `ThreadScreen`, `MessageBubble`, `MediaContent`.
