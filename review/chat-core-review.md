# Chat Core Package Code Review (`packages/chat_core`)

> **Ngày review:** 2026-08-21  
> **Phạm vi review:** `packages/chat_core` (~6.287 LOC, 73 files: 88 dòng barrel, 497 dòng core, 638 dòng auth_token & contact, 1.488 dòng conversation_list, 2.893 dòng thread, 686 dòng test).  
> **Tiêu chuẩn review:** Theo `review/prompt.md` (Senior Flutter Architect / SDK Engineer & Code Reviewer).  
> **Bản chất package:** Pure Dart package (không phụ thuộc Flutter UI, độc lập với rendering pipeline).

---

## 1. Executive Summary

| Tiêu chí | Điểm | Nhận xét chi tiết |
|---|:---:|---|
| **Architecture** | **7.0/10** | Clean Architecture phân tầng chuẩn (Domain entities, Repository interfaces, 29 Use Cases riêng biệt, Data layer). Tuy nhiên, barrel file làm rò rỉ toàn bộ Data layer, coupling với `chat_native_platform_interface`, và logic sinh văn bản tiếng Việt bị trộn vào Data layer. |
| **Maintainability** | **6.5/10** | Comment lịch sử giải thích bug rất chi tiết và có giá trị; tuy nhiên 3 Data Source chính (`native_realtime_datasource_impl.dart`, `message_remote_datasource_impl.dart`, `conversation_remote_datasource_impl.dart`) có kích thước lớn (500–750 dòng), chứa nhiều logic phân tích cú pháp lặp lại. |
| **Readability** | **7.0/10** | Naming chuẩn theo Dart guidelines, domain entities rõ ràng, bất biến (immutable); nhưng logic xử lý event đa hình trong WebSocket khá phức tạp và khó theo dõi. |
| **Performance** | **6.5/10** | Có single-flight request dedup cho token, stream-to-disk upload file; nhưng bị lãng phí CPU do format pretty JSON mọi WebSocket event ngay cả khi tắt log, và vòng lặp $O(N^2)$ quét tìm `RoomUpdated` trong lịch sử tin nhắn. |
| **API Efficiency** | **7.0/10** | Single-flight `_inFlight` token, dedup `lastVisibleMessageId` tốt; nhưng thiếu cơ chế catch-up/sync tin nhắn sau khi reconnect WebSocket, và `getRoomReactions` không có debounce ở core. |
| **Memory Safety** | **7.0/10** | Hầu hết controller/stream/subscription được giải phóng khi gọi `dispose()`; tuy nhiên broadcast StreamController trong realtime datasource không tự hủy nếu không có listener lắng nghe. |
| **Crash Safety** | **7.5/10** | Xử lý phòng thủ tốt với `whereType<Map>()`, `DateTime.tryParse()`, fallback giá trị mặc định; rủi ro tiềm ẩn ở các đoạn ép kiểu `cast<String, dynamic>()` trên payload JSON lồng nhau. |
| **Testability** | **6.0/10** | Kiến trúc Clean Architecture với interface đầy đủ giúp các class cực kỳ dễ mock/test; tuy nhiên thực tế chỉ có 4 file test (~686 LOC, ~10% độ phủ), thiếu hoàn toàn test cho Realtime, REST Datasource, Network Client và Utils. |
| **Extensibility** | **6.0/10** | `MessageType` mở dạng string value rất tốt cho việc mở rộng; nhưng văn bản hiển thị sự kiện hệ thống bị hardcode tiếng Việt trong data layer khiến consumer không thể đa ngôn ngữ hóa (i18n). |
| **UI Customizability** | **N/A** | `chat_core` là tầng data/domain. Cung cấp entity mở (`metadata` Map) giúp UI layer tự do tùy biến render. |
| **Public API Design** | **5.5/10** | Barrel `chat_core.dart` export tất cả data models và datasource implementations; `ChatModuleConfig` yêu cầu `acsEndpoint` bắt buộc nhưng thực tế không dùng (dead config); tên class mang nhãn "ACS/Native" nhưng thực chất chạy WebSocket backend. |
| **Production Readiness** | **6.5/10** | **🟡 READY WITH MINOR FIXES** (cho nội bộ app) / **⚠️ READY WITH MAJOR FIXES** (nếu đóng gói phát hành SDK công khai). |

---

## 2. Architecture Assessment

```text
Host Application / chat_ui
         │
         ▼ (imports chat_core.dart)
┌────────────────────────────────────────────────────────────────────────┐
│                        packages/chat_core                              │
│                                                                        │
│  [DOMAIN LAYER] (Pure Dart - Public Contract)                          │
│  ├─ Entities: ChatUser, ChatMember, Conversation, Message,             │
│  │            PinnedMessage, MessageReader, MessageResource,           │
│  │            MessageReaction, ChatAccessToken                         │
│  ├─ Repository Interfaces: ConversationRepository, MessageRepository,  │
│  │                         AuthTokenRepository, ContactRepository      │
│  └─ Use Cases (29 single-purpose use cases)                            │
│                                                                        │
│  [DATA LAYER] (Implementation Details - Should be Internal)            │
│  ├─ Models: ConversationModel, MessageModel, ChatUserModel...          │
│  ├─ Repositories: ConversationRepositoryImpl, MessageRepositoryImpl,   │
│  │                AuthTokenRepositoryImpl, ContactRepositoryImpl       │
│  ├─ Remote DataSources: JsonApiClient (REST Backend),                  │
│  │                      NativeRealtimeDataSourceImpl (WebSocket),      │
│  │                      MessageRemoteDataSourceImpl, PollingEngine     │
│  └─ Local DataSources (Interfaces): ConversationLocalDataSource,       │
│                                     MessageLocalDataSource             │
└────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Điểm mạnh kiến trúc (KEEP)

1. **Clean Layering thuần túy**: `chat_core` không import bất kỳ package Flutter nào (`package:flutter/*`). Hoàn toàn là pure Dart, dễ chạy test unit, dễ tái sử dụng trên CLI hoặc backend Dart nếu cần.
2. **Domain Entities bất biến (Immutable)**: Toàn bộ entity (`Conversation`, `Message`, `ChatUser`, `ChatMember`...) đều sử dụng `const` constructor và hỗ trợ `copyWith()`, bảo vệ state khỏi side-effect ngoài ý muốn.
3. **Use Case 1-trách-nhiệm**: 29 use case được phân chia độc lập, rõ ràng theo nghiệp vụ (`SendMessageUseCase`, `ListConversationsUseCase`, `AddParticipantsUseCase`...).
4. **Single-Flight Request Deduplication**: `AuthTokenRepositoryImpl` cài đặt bộ đệm `_inFlight` bằng `Map<String, Future<ChatAccessToken>>` để gộp các request lấy token đồng thời vào 1 network call duy nhất.
5. **Cache-First & Offline Degradation**: `ConversationRepositoryImpl` và `MessageRepositoryImpl` cài đặt pattern đọc cache trước khi mạng lỗi hoặc tải ban đầu, bảo đảm ứng dụng vẫn hiển thị dữ liệu khi mất kết nối.
6. **Robust Polling Fallback Engine**: `PollingEngine` cài đặt Jitter ngẫu nhiên lúc khởi tạo + Exponential Backoff khi gặp lỗi liên tiếp/429.

---

### 2.2 Điểm yếu & Architectural Smells

#### A. Rò rỉ Data Layer qua Barrel File (`chat_core.dart`)
- **Hiện trạng:** `lib/chat_core.dart` export tất cả Data Models (`MessageModel`, `ConversationModel`), Data Sources (`ConversationRemoteDataSourceImpl`, `NativeRealtimeDataSourceImpl`), và Repositories (`MessageRepositoryImpl`...).
- **Vấn đề:** Khiến layer bên ngoài (`chat_ui`) phụ thuộc trực tiếp vào implementation thay vì interface. Ví dụ, `ThreadMessagesNotifier` trực tiếp khởi tạo `MessageModel` (data model) thay vì thao tác trên domain entity `Message`.
- **Hệ quả:** Mọi thay đổi về JSON parsing hoặc cấu trúc nội bộ của data model sẽ trở thành breaking change đối với client.

#### B. Trộn lẫn trách nhiệm Presentation Text vào Data Layer (Chặn i18n)
- **Hiện trạng:** `NativeRealtimeDataSourceImpl._handleRoomEvent` và `MessageModel.fromAcsJson` trực tiếp ghép các chuỗi tiếng Việt như:
  - `'**$actorName** đã phong **$targetName** làm Admin'`
  - `'**$actorName** đã chuyển quyền Trưởng phòng cho **$targetName**'`
  - `'Phòng chat đã bị giải tán'`
  - `'(tin nhắn đã bị xoá)'`
- **Vấn đề:** Data Layer vi phạm Single Responsibility Principle khi kiêm nhiệm việc định dạng ngôn ngữ người dùng (Presentation/Localization).
- **Hệ quả:** 
  1. Không thể dịch ứng dụng sang tiếng Anh hoặc các ngôn ngữ khác.
  2. Logic tạo câu bị duplicate ở 2 file khác nhau (`NativeRealtimeDataSourceImpl` và `MessageModel.fromAcsJson`), dẫn đến nguy cơ lệch wording giữa tin nhắn từ lịch sử (REST) và tin nhắn nhận tức thời (WebSocket).

#### C. Lớp "Di sản ACS" gây nhầm lẫn cấu hình và phụ thuộc rác
- **Hiện trạng:** 
  - `ChatModuleConfig.acsEndpoint` được đánh dấu `required`, nhưng không có dòng code nào trong `chat_core` hay `chat_ui` đọc giá trị này.
  - `NativeRealtimeDataSourceImpl` nhận `ChatNativePlatformInterface? platform` trong constructor chỉ để không lỗi signature cũ, nhưng bên trong hoàn toàn dùng `WebSocketChannel` thuần Dart.
  - Constant `ChatApiEndpoints.acsThreadMessages` bị bỏ hoang.
- **Hệ quả:** Người tích hợp SDK phải truyền tham số vô nghĩa, gây hiểu lầm rằng SDK đang gọi trực tiếp tới Azure ACS SDK.

---

## 3. Critical Issues (P0 / P1)

### P0-1 — Realtime mất kết nối vĩnh viễn với Room sau khi Resume từ Background

```text
Issue: leaveActiveRoom() xóa sạch _activeRoomIds làm hỏng cơ chế re-enter room khi WebSocket reconnect
File: lib/features/thread/data/datasources/native_realtime_datasource_impl.dart
Class: NativeRealtimeDataSourceImpl
Method: leaveActiveRoom() (dòng 572-586) & _handleSocketData() (dòng 151-154)
Severity: P0
Category: Lifecycle / Realtime Bug

Current behavior:
Khi người dùng chuyển app sang background hoặc màn hình tắt, UI gọi leaveActiveRoom().
Hàm này gửi event 'leave_room' lên WebSocket và xóa sạch danh sách _activeRoomIds:
  _activeRoomIds.clear();

Khi app quay lại foreground, nếu kết nối WebSocket đã bị hệ điều hành đóng khi ngủ (rất phổ biến):
Hàm reconnect được kích hoạt -> socket mở lại -> nhận event type == 'connected':
  for (final roomId in _activeRoomIds) {
    _send({'type': 'enter_room', 'roomId': roomId});
  }
Vì _activeRoomIds đã bị clear() trước đó, vòng lặp chạy trên Set rỗng -> Không gửi bất kỳ 'enter_room' nào.

Problem:
Người dùng đang ở trong màn hình chat, nhưng server không nhận được lệnh enter_room.
Toàn bộ tin nhắn mới của người khác trong phòng sẽ KHÔNG được gửi về máy người dùng qua WebSocket.

Why it is dangerous:
Lỗi nghiêm trọng, xảy ra ngầm không báo lỗi (silent failure).
Người dùng tưởng rằng không có tin nhắn mới, phải thoát hẳn ra danh sách hội thoại rồi mở lại mới nhận được tin.

Reproduction scenario:
1. Mở một phòng chat 1-1 hoặc nhóm.
2. Nhấn Home để ẩn app xuống background trong 45 giây (hoặc tắt Wifi/bật lại để socket reconnect).
3. Mở lại app (Foreground).
4. Dùng tài khoản khác gửi tin nhắn vào phòng đó.
5. Máy hiện tại hoàn toàn im lặng, không có tin nhắn mới xuất hiện.

Recommended solution:
1. Phân biệt giữa "Tập hợp các phòng đang được theo dõi" (_watchedRooms / stream active) và "Trạng thái hiển thị tạm thời".
2. Trong watchNewMessages, lưu roomId vào _watchedRooms.
3. Khi leaveActiveRoom(), chỉ xóa _lastVisibleMessageId và gửi leave_room tạm thời, KHÔNG xóa danh sách phòng đang watch.
4. Khi socket reconnect thành công (type == 'connected'), tự động gửi lại 'enter_room' cho tất cả _watchedRooms.
```

---

### P1-2 — Format Pretty JSON thực thi trên mọi WebSocket Event gây nghẽn Main Isolate

```text
Issue: JsonEncoder.withIndent chạy trên mọi event WebSocket nhận được trước khi kiểm tra ChatLogger.enabled
File: lib/features/thread/data/datasources/native_realtime_datasource_impl.dart
Class: NativeRealtimeDataSourceImpl
Method: _handleSocketData (dòng 143-144)
Severity: P1
Category: Performance / CPU Overhead

Current behavior:
  void _handleSocketData(dynamic raw) {
    ...
    final decoded = jsonDecode(raw.toString());
    if (decoded is! Map) return;
    final event = decoded.cast<String, dynamic>();
    final prettyJson = const JsonEncoder.withIndent('  ').convert(event); // <-- Luôn chạy!
    ChatLogger.log('WebSocket event:\n$prettyJson');
    ...
  }

Problem:
Ngay cả khi ChatLogger.enabled == false (môi trường Release/Production), đối tượng JsonEncoder 
vẫn được gọi để format toàn bộ JSON tree của mỗi event thành chuỗi nhiều dòng có thụt lề.
Sau đó ChatLogger.log() mới kiểm tra "if (!enabled) return;".

Why it is dangerous:
Trong các nhóm chat lớn hoặc khi nhận lượng lớn tin nhắn/sự kiện dồn dập (burst), 
việc parse và format string liên tục trên Main Isolate gây drop frame (jank) và cấp phát rác bộ nhớ (GC pressure) không cần thiết.

Recommended solution:
Kiểm tra cờ log trước khi encode, hoặc truyền callback vào ChatLogger:
  if (ChatLogger.enabled) {
    ChatLogger.log('WebSocket event:\n${const JsonEncoder.withIndent('  ').convert(event)}');
  }
```

---

### P1-3 — Thuật toán Quét Lịch sử $O(N^2)$ trong `listMessages` để Phát hiện Thay đổi Phòng

```text
Issue: Vòng lặp lồng O(N^2) tìm kiếm RoomUpdated trong MessageRemoteDataSourceImpl
File: lib/features/thread/data/datasources/message_remote_datasource_impl.dart
Class: MessageRemoteDataSourceImpl
Method: listMessages (dòng 145-186)
Severity: P1
Category: Performance / Data Processing

Current behavior:
Trong listMessages, để xác định xem sự kiện 'RoomUpdated' có làm đổi tên hay đổi avatar không,
code chạy 2 vòng for lồng nhau:
  for (var i = 0; i < rawItems.length; i++) {
    if (eventType == 'RoomUpdated') {
      for (var j = i + 1; j < rawItems.length; j++) {
        // Tìm event RoomUpdated liền trước để so sánh name/avatar
      }
    }
  }

Problem:
Mỗi trang 50–100 tin nhắn có chứa nhiều sự kiện cập nhật phòng sẽ kích hoạt quét mảng nhiều lần.
Đây là xử lý nặng nề ở tầng Data Source của client để bù đắp cho việc Backend không trả cờ isNameChanged/isAvatarChanged.

Why it is dangerous:
Làm chậm thời gian parse dữ liệu khi tải lịch sử tin nhắn hoặc khi cuộn trang (pagination) liên tục.

Recommended solution:
1. Tối ưu thuật toán thành $O(N)$: Chỉ cần duyệt một lượt từ dưới lên hoặc lưu lại trạng thái `lastSeenRoomName` / `lastSeenAvatarUrl` trong quá trình duyệt.
2. Tốt nhất là thống nhất với Backend để trả sẵn cờ `isNameChanged` / `isAvatarChanged` trong payload event.
```

---

### P1-4 — `AuthTokenRepositoryImpl._refresh` Retry Cố định Cả Khi Gặp Lỗi 401/403 Không Thể Phục Hồi

```text
Issue: Retry vô điều kiện 3 lần với delay 3s khi fetch token thất bại
File: lib/features/auth_token/data/repositories/auth_token_repository_impl.dart
Class: AuthTokenRepositoryImpl
Method: _refresh (dòng 62-79)
Severity: P1
Category: Network / API Efficiency / Latency

Current behavior:
  Future<ChatAccessToken> _refresh(String roomId) async {
    int retries = 3;
    while (true) {
      try {
        final token = await _dataSource.fetchToken(roomId);
        _cached[roomId] = token;
        return token;
      } catch (e) {
        retries--;
        if (retries <= 0) rethrow;
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

Problem:
Nếu lỗi trả về là 401 (Hết hạn JWT của App), 403 (Bị cấm vào phòng), hoặc 404 (Phòng không tồn tại),
hàm vẫn kiên trì đợi 3 giây và gọi lại đủ 3 lần (tổng cộng mất >9 giây) trước khi báo lỗi cho UI.

Why it is dangerous:
Làm treo UI (loading spinner xoay 9-10 giây) trong khi lỗi đã rõ ràng ngay từ lần gọi đầu tiên.
Tạo thêm 2 request rác lên server khi server đã từ chối xác thực.

Recommended solution:
Chỉ retry khi gặp lỗi mạng tạm thời (SocketException, TimeoutException) hoặc lỗi 5xx từ server.
Nếu bắt được `ChatApiException` với `statusCode == 401 || statusCode == 403 || statusCode == 404`, ném lỗi ra ngay lập tức (`rethrow`).
```

---

### P1-5 — Ngoại lệ `ChatApiException` Bị Gán Status Code `200` Khi Dữ Liệu Rỗng

```text
Issue: Ném ChatApiException với statusCode = 200 cho lỗi parse dữ liệu
File: lib/features/conversation_list/data/datasources/conversation_remote_datasource_impl.dart
Class: ConversationRemoteDataSourceImpl
Method: getOrCreateDirectConversation (dòng 46-52), uploadRoomAvatar (dòng 285-290), uploadFileViaSas (dòng 360-366, 451-456)
Severity: P1
Category: Error Handling / Architecture Consistency

Current behavior:
  if (data == null) {
    throw ChatApiException(
      statusCode: 200,
      code: 'CREATE_ROOM_NULL_DATA',
      message: 'Không thể tạo phòng chat...',
    );
  }

Problem:
`ChatApiException` là lớp đại diện cho lỗi HTTP status code theo thiết kế (mục 11.2 api-docs).
Việc gán `statusCode: 200` cho một Exception làm sai lệch logic xử lý lỗi ở các tầng trên (ví dụ: code kiểm tra `if (e.statusCode >= 400)` sẽ bị lọt lưới).

Recommended solution:
Tách thành các lớp Exception có ngữ nghĩa rõ ràng:
- `ChatApiException`: Lỗi từ HTTP response ($status \ge 400$).
- `ChatParseException` hoặc `ChatEmptyDataException`: Lỗi do server trả format không hợp lệ hoặc thiếu field bắt buộc dù status 200.
```

---

## 4. API Efficiency & Network Review

### 4.1 Tổng hợp các điểm chưa tối ưu về API & Network

1. **Thiếu cơ chế Sync / Catch-up sau khi Reconnect WebSocket**:
   - Khi mạng bị ngắt 1–2 phút rồi có lại, WebSocket tự kết nối lại và gửi `enter_room`.
   - Tuy nhiên, client **không có cơ chế yêu cầu server bù đắp các tin nhắn bị lỡ trong khoảng thời gian mất mạng**. Client chỉ dựa vào tin nhắn mới phát sinh sau thời điểm kết nối, dẫn đến nguy cơ mất tin nhắn (message gap) nếu user không tự pull-to-refresh.
2. **Không có in-flight deduplication cho `getRoomReactions` và `getPinnedMessages`**:
   - Khi nhiều component trong UI cùng mount và gọi `getPinnedMessages` hoặc `getRoomReactions`, mỗi component sẽ bắn một request riêng biệt lên backend mà không được gộp qua cơ chế single-flight như `getAccessToken`.
3. **`uploadFileViaSas` dùng `http.StreamedRequest` không hỗ trợ hủy ngang (Cancellation)**:
   - Khi user upload một file video lớn (50–100MB), nếu user thoát màn hình chat, stream upload vẫn tiếp tục chạy ngầm trong `putRequest.send()` cho đến khi hết timeout (lên tới 600s), làm lãng phí băng thông và pin của thiết bị.

---

## 5. Memory & Resource Lifecycle Issues

### 5.1 Phân tích Vòng đời và Rò rỉ Tài nguyên (Leak Analysis)

```text
┌───────────────────────────────┬────────────────────────────────┬───────────────────────────────┐
│ Resource                      │ Lifecycle Management           │ Đánh giá Rủi ro               │
├───────────────────────────────┼────────────────────────────────┼───────────────────────────────┤
│ WebSocketChannel              │ NativeRealtimeDataSourceImpl   │ An toàn khi gọi dispose();    │
│                               │ _closeSocket() đóng sink       │ rủi ro nếu app không dispose  │
├───────────────────────────────┼────────────────────────────────┼───────────────────────────────┤
│ _threadControllers (Map)      │ NativeRealtimeDataSourceImpl   │ StreamController broadcast    │
│                               │ close() trong stopWatching()   │ không tự đóng nếu bỏ quên     │
├───────────────────────────────┼────────────────────────────────┼───────────────────────────────┤
│ _activePolling (Map)          │ MessageRemoteDataSourceImpl    │ Được stop & close khi dispose │
│                               │ PollingEngine quản lý timer    │ An toàn                       │
├───────────────────────────────┼────────────────────────────────┼───────────────────────────────┤
│ Heartbeat & Reconnect Timers  │ NativeRealtimeDataSourceImpl   │ Được cancel trước khi gán mới │
│                               │ và khi disconnect              │ An toàn                       │
├───────────────────────────────┼────────────────────────────────┼───────────────────────────────┤
│ http.Client                   │ JsonApiClient / DataSourceImpl │ Có phương thức dispose()      │
│                               │ gọi _http.close()              │ An toàn                       │
└───────────────────────────────┴────────────────────────────────┴───────────────────────────────┘
```

#### Vấn đề P2-1: `_threadControllers` giữ Broadcast Controller khi listener unsubscribe mà không gọi `stopWatching`
- Trong Dart, `StreamController.broadcast()` không tự đóng khi không còn listener nào lắng nghe (`hasListener == false`).
- Nếu một consumer (màn hình hoặc service) lắng nghe `watchNewMessages()` nhưng khi thoát không gọi `stopWatching(threadId)`, controller đó sẽ nằm vĩnh viễn trong `_threadControllers` của Data Source.
- **Khuyến nghị:** Cân nhắc sử dụng `StreamController.broadcast(onCancel: ...)` để tự động dọn dẹp hoặc theo dõi số lượng subscriber.

---

## 6. Crash & Reliability Issues

### 6.1 Bảng Kiểm tra An toàn Mã nguồn (Safety Audit)

| Ký hiệu / Thao tác | Vị trí phát hiện | Đánh giá | Nguy cơ |
|---|---|:---:|---|
| **Ép kiểu `!`** | `conversation_remote_datasource_impl.dart:310`, `_config.apiKey!` | An toàn | Đã được guard bằng `if (_config.apiKey != null && ...)` trước đó. |
| **Ép kiểu `.cast<K,V>()`** | Hầu hết các file model & datasource | ⚠️ Cảnh báo | Nếu JSON trả về Map có key không phải String (vd int), `.cast<String, dynamic>()` sẽ quăng `TypeError` runtime. |
| **Truy cập index `[0]`** | `pinned_message_model.dart:34-36` | An toàn | Đã kiểm tra `parts.length == 3` trước khi đọc index 0, 1, 2. |
| **`DateTime.parse()`** | `chat_access_token_model.dart:23` | ⚠️ Cảnh báo | Dùng `DateTime.parse(json['tokenUtcExp'] as String)`. Nếu server trả null hoặc chuỗi sai format sẽ crash. Nên đổi sang `DateTime.tryParse()`. |
| **`jsonDecode()`** | `chat_logger.dart:66`, `message_model.dart:334` | An toàn | Đã bọc cẩn thận trong `try { ... } catch (_)`. |
| **`throw UnimplementedError`** | Không có trong `chat_core` | An toàn | Không sử dụng pattern này trong tầng core. |

---

## 7. Realtime & ACS Assessment

### 7.1 Ma trận Hiện trạng Thực tế vs Khái niệm ACS

| Chức năng | Tên gọi trong Code | Cơ chế Vận hành Thực tế | Đánh giá |
|---|---|---|---|
| **Realtime Messaging** | `NativeRealtimeDataSourceImpl` | Kết nối WebSocket tới Backend (`/ws/chat/view`) | Hoạt động tốt qua WebSocket, nhưng tên gọi "Native" gây hiểu nhầm. |
| **Token Lấy Lượt Chat** | `AuthTokenRepositoryImpl.getAccessToken` | Gọi API `join-room/{roomId}` của Backend | Hoạt động tốt, có single-flight dedup. |
| **Lấy Lịch sử Tin** | `MessageRemoteDataSourceImpl.listMessages` | Gọi REST API `/api/chat/get-messages` của Backend | Chuẩn xác, không gọi ACS REST trực tiếp. |
| **Đọc / Đã xem** | `NativeRealtimeDataSourceImpl.sendReadMessage` | Gửi payload `{ type: "read", lastVisibleMessageId }` qua WebSocket | Tốt, có chống gửi trùng ID. |
| **Trạng thái Rời phòng** | `NativeRealtimeDataSourceImpl.leaveActiveRoom` | Gửi payload `{ type: "leave_room", roomId }` qua WebSocket | Đang có bug P0-1 làm mất danh sách phòng khi resume. |

---

## 8. Public API & Layer Leak Review

### 8.1 Vấn đề Barrel File `chat_core.dart`

Hiện tại, `lib/chat_core.dart` đang export mọi thứ:
```dart
// ❌ CÁC EXPORT KHÔNG NÊN ĐỂ PUBLIC CHO TOÀN BỘ APP CONSUMER:
export 'core/network/json_api_client.dart';
export 'features/auth_token/data/models/chat_access_token_model.dart';
export 'features/auth_token/data/datasources/auth_token_remote_datasource_impl.dart';
export 'features/conversation_list/data/models/conversation_model.dart';
export 'features/conversation_list/data/datasources/conversation_remote_datasource_impl.dart';
export 'features/thread/data/models/message_model.dart';
export 'features/thread/data/datasources/native_realtime_datasource_impl.dart';
export 'features/thread/data/datasources/polling_engine.dart';
```

#### Đề xuất Kiến trúc Public API chuẩn của `chat_core`:
1. **`lib/chat_core.dart`**: CHỈ export Domain Entities, Domain Repositories (Interfaces), Use Cases, Config, Errors, và Factory khởi tạo chính.
2. **`lib/chat_core_internal.dart`** (hoặc đặt trong `src/`): Chứa Data Models, Remote DataSources, JSON mappers dành riêng cho việc cấu hình Dependency Injection nội bộ (ví dụ bên `chat_ui` hoặc composition root).

---

## 9. Performance Review

| Kịch bản | Tải dữ liệu | Đánh giá Hiệu năng `chat_core` | Điểm nghẽn tiềm ẩn |
|---|---|---|---|
| **Small Chat (1-1, < 100 msgs)** | Nhẹ | Rất mượt, parse nhanh, RAM tiêu thụ < 5MB | Không có |
| **Medium Chat (500 - 1.000 msgs)** | Trung bình | Tốt, cache Hive/RAM phản hồi tức thì | Pretty-print JSON log của WebSocket gây tốn CPU nếu bật debug log |
| **Large Chat (5.000 - 10.000 msgs)** | Nặng | Tải phân trang 50 tin/lần ổn định | Vòng lặp quét $O(N^2)$ `RoomUpdated` và việc decode JSON trên main thread có thể gây giật nhẹ |

---

## 10. Testability & Test Coverage

### 10.1 Hiện trạng Test trong `packages/chat_core/test/`

Tổng số dòng code test: **686 dòng** (chiếm ~10% codebase).
- `test/auth_token_repository_test.dart` (66 dòng): Test dedup và cache token của `AuthTokenRepositoryImpl`.
- `test/group_conversation_test.dart` (286 dòng): Test use cases nhóm (add/remove participants, update info, roles...).
- `test/message_repository_cache_test.dart` (283 dòng): Test lưu cache, merge pin flag, fallback offline.
- `test/message_test.dart` (55 dòng): Test `Message.copyWith` và `MessageType.fromString`.

### 10.2 Các khu vực quan trọng hoàn toàn CHƯA CÓ TEST (0% Coverage):
1. ❌ `NativeRealtimeDataSourceImpl`: Chưa có test cho kết nối WebSocket, Heartbeat timer, Reconnect exponential backoff, Room event parsing.
2. ❌ `JsonApiClient`: Chưa có test cho HTTP headers, Bearer token injection, Multipart upload, Error mapping sang `ChatApiException`.
3. ❌ `MessageRemoteDataSourceImpl` & `ConversationRemoteDataSourceImpl`: Chưa có test cho URL builder, Query param formatting, SAS file upload parsing.
4. ❌ `ChatMimeUtils` & `AcsUserUtils`: Chưa có test cho việc tra cứu MIME type và chuẩn hóa ACS ID.

---

## 11. API Call & Resource Matrix

| Nghiệp vụ | Endpoint / Kênh | Trigger | Có dư thừa? | Khả năng Cache | Deduplicate? | Rủi ro chính |
|---|---|---|:---:|:---:|:---:|---|
| **Lấy Token Hội thoại** | `POST /api/chat/join-room/{id}` | Mở phòng chat | Không | Có (RAM trong hạn `expiresOn`) | **Có** (`_inFlight` Future map) | Retry cố định 3 lần khi lỗi 401 |
| **Danh sách Hội thoại** | `GET /api/chat/get-room-chats` | Mở danh sách, Refresh | Không | Có (Local DB) | Không | Không phân biệt pull-to-refresh vs pagination |
| **Lịch sử Tin nhắn** | `GET /api/chat/get-messages` | Mở thread, Scroll lên | Không | Có (Local DB) | Không | Thiếu sync bù sau khi reconnect |
| **Gửi Tin nhắn** | `POST /api/chat/send-message` | Bấm Gửi | Không | Không | Không | Optimistic local, không có retry queue |
| **Đánh dấu Đã đọc** | WebSocket `{ type: "read" }` | Cuộn thấy tin mới | **Không (Đã tối ưu)** | N/A | **Có** (Bỏ qua nếu trùng `lastVisibleId`) | Mất ID khi pause app |
| **Upload File SAS** | 3 bước: Session $\to$ PUT $\to$ Complete | Gửi ảnh/file/video | Không | Không | Không | Không hủy được PUT request khi back màn hình |
| **Lắng nghe Realtime** | WebSocket `/ws/chat/view` | Suốt vòng đời session app | Không | N/A | **Có** (Dùng chung 1 kết nối WebSocket) | Bug P0-1: Mất phòng khi resume |

---

## 12. Lifecycle Matrix

| Trạng thái / Sự kiện | Hành vi Kỳ vọng | Hành vi Thực tế trong `chat_core` | Đánh giá & Rủi ro |
|---|---|---|---|
| **Khởi tạo SDK** | Cung cấp Config & Auth Token Provider | `ChatModuleConfig` khởi tạo immutably | Tốt. (Cần loại bỏ tham số `acsEndpoint` dư thừa). |
| **Mở Phòng Chat** | Gửi `enter_room` qua WebSocket, tải tin cache + gọi API | Gửi `enter_room`, mở Broadcast Stream, load history | Tốt. |
| **Chuyển sang Background** | Gửi `leave_room`, tạm dừng heartbeat nếu cần | Gửi `leave_room`, gọi `leaveActiveRoom()`, xóa `_activeRoomIds` | **Nguy hiểm (P0-1):** Xóa sạch `_activeRoomIds` làm mất khả năng tự vào lại phòng khi resume. |
| **Quay lại Foreground** | Reconnect nếu đứt, re-enter tất cả active rooms | Reconnect socket, nhưng vòng lặp re-enter chạy trên tập rỗng | **Bug P0-1:** Realtime bị ngắt ngầm. |
| **Hết hạn Phiên (401)** | Kích hoạt callback `onSessionExpired`, dừng reconnect | `_expireSession()` gọi callback, đóng socket, hủy timer | Tốt và an toàn. |
| **Đăng xuất (Logout)** | Hủy toàn bộ kết nối, xóa cache RAM | `dispose()` trên các repository đóng socket và xóa stream | Tốt. |
| **Mất mạng & Có lại** | Exponential backoff + jitter reconnect, sync lại tin | Có backoff + jitter (1, 2, 4, 8, 15, 30s); **thiếu sync tin** | Khá. Cần bổ sung hook sync tin nhắn sau reconnect. |

---

## 13. Critical Scenarios Audit

### Scenario 1: Mở Chat $\to$ Load Messages $\to$ Nhận Event Realtime $\to$ Đóng Chat
- **Luồng:** `watchNewMessages` kích hoạt `enter_room` $\to$ `listMessages` đọc cache + fetch API $\to$ Realtime event emit qua stream $\to$ `stopWatching` gửi `leave_room` và đóng stream.
- **Kết quả:** **PASS** (Hoạt động chính xác và dọn dẹp đầy đủ).

### Scenario 2: Mở Chat $\to$ Đóng Chat $\to$ Mở lại Chat Ngay Lập Tức
- **Luồng:** `stopWatching` đóng controller cũ $\to$ `watchNewMessages` tạo controller mới và gửi lại `enter_room`.
- **Kết quả:** **PASS** (Không bị kẹt controller cũ).

### Scenario 3: Mở Chat $\to$ Background App $\to$ Foreground App
- **Luồng:** `leaveActiveRoom` xóa `_activeRoomIds` $\to$ Socket bị đứt khi ngủ $\to$ Foreground socket reconnect nhưng không gửi `enter_room`.
- **Kết quả:** ❌ **FAIL (Bug P0-1)**.

### Scenario 4: Mở Chat $\to$ Chuyển Conversation $\to$ Quay lại Conversation Cũ
- **Luồng:** `stopWatching(threadA)` rời phòng A $\to$ `watchNewMessages(roomB)` vào phòng B $\to$ quay lại mở lại phòng A.
- **Kết quả:** **PASS** (Chuyển đổi room độc lập).

### Scenario 5: User Scroll Lên (Load More) $\to$ Realtime Message Tới Cùng Lúc
- **Luồng:** `listMessages(cursor: ...)` fetch trang cũ $\to$ `_saveToCache` merge theo ID $\to$ Tin realtime tới qua stream được `_appendToCache` vào đầu danh sách.
- **Kết quả:** **PASS** (`_mergeById` bảo đảm không duplicate tin nhắn).

### Scenario 6: Gửi Tin Nhắn $\to$ Mạng Chậm / Mất Mạng
- **Luồng:** `sendMessage` bắn POST request timeout 15s $\to$ nếu fail ném `ChatApiException`.
- **Kết quả:** **PASS** ở core (trách nhiệm retry optimistic thuộc về notifier ở UI layer).

### Scenario 7: Token Hết Hạn Khi Đang Gọi API
- **Luồng:** `JsonApiClient` nhận 401 $\to$ ném `ChatApiException(statusCode: 401)`.
- **Kết quả:** **PASS** (Client app bắt được 401 để xử lý refresh token toàn cục).

---

## 14. Refactoring Priority Matrix

| Mức độ | Vấn đề | File liên quan | Tác động | Độ phức tạp | Đề xuất giải pháp |
|:---:|---|---|:---:|:---:|---|
| **P0** | Bug mất Realtime sau background $\to$ foreground | `native_realtime_datasource_impl.dart` | Rất lớn | Thấp | Tách riêng `_watchedRoomIds` và tự động gửi lại `enter_room` khi reconnect. |
| **P1** | Pretty JSON log chạy mọi event làm tốn CPU | `native_realtime_datasource_impl.dart` | Trung bình | Rất thấp | Thêm guard `if (ChatLogger.enabled)` trước khi gọi `JsonEncoder`. |
| **P1** | Hardcoded text tiếng Việt trong Data Layer | `message_model.dart`, `native_realtime_datasource_impl.dart` | Lớn (i18n) | Trung bình | Trả raw event type + parameters qua `metadata`, đẩy việc dựng text về UI/Localization layer. |
| **P1** | Quét mảng $O(N^2)$ trong `listMessages` | `message_remote_datasource_impl.dart` | Trung bình | Thấp | Đổi thuật toán duyệt 1 lần $O(N)$ hoặc lưu state tạm thời. |
| **P1** | Retry vô điều kiện 3 lần với lỗi 401/403 | `auth_token_repository_impl.dart` | Trung bình | Thấp | Rethrow ngay nếu gặp `statusCode == 401 \|\| statusCode == 403`. |
| **P1** | Ném `ChatApiException` với status 200 | `conversation_remote_datasource_impl.dart` | Trung bình | Thấp | Tách lớp ngoại lệ `ChatParseException` riêng biệt. |
| **P2** | Dọn dẹp Public API & Barrel file | `chat_core.dart` | Lớn (Kiến trúc) | Trung bình | Ẩn Data Models và Data Sources khỏi public barrel `chat_core.dart`. |
| **P2** | Loại bỏ `acsEndpoint` và dead code ACS | `chat_module_config.dart`, `chat_api_endpoints.dart` | Thấp | Thấp | Đánh dấu `@deprecated` hoặc xóa tham số `acsEndpoint`. |
| **P2** | Bổ sung Unit Test cho Realtime & Network | Thư mục `test/` | Cao (Chất lượng) | Trung bình | Viết test với mock WebSocket và HTTP Client. |

---

## 15. Recommended Target Architecture for `chat_core`

```text
packages/chat_core/
├── lib/
│   ├── chat_core.dart                 <-- PUBLIC API (Chỉ export Config, Entities, Repositories, Use Cases, Errors)
│   ├── src/                           <-- INTERNAL IMPLEMENTATION (Ẩn khỏi consumer)
│   │   ├── core/
│   │   │   ├── config/
│   │   │   ├── network/ (JsonApiClient)
│   │   │   ├── error/ (ChatApiException, ChatDataException)
│   │   │   └── utils/ (ChatLogger, MimeUtils)
│   │   ├── features/
│   │   │   ├── auth_token/ (data/ & domain/)
│   │   │   ├── conversation_list/ (data/ & domain/)
│   │   │   ├── thread/ (data/ & domain/)
│   │   │   └── contact/ (data/ & domain/)
│   │   └── di/ (Dependency Injection helpers / Factory nếu cần)
```

---

## 16. Actionable Migration Plan

### Giai đoạn 1: Sửa lỗi Nghiêm trọng (Critical Bug Fixes) — *Khuyến nghị làm ngay*
1. **Fix Bug P0-1**: Trong `NativeRealtimeDataSourceImpl`, thêm `Set<String> _watchedRoomIds` để lưu giữ danh sách room đang subscribe. Sửa `leaveActiveRoom()` để không xóa danh sách này, và tự động re-enter tất cả watched rooms khi WebSocket kết nối lại.
2. **Fix Performance P1-2**: Bọc kiểm tra `if (ChatLogger.enabled)` trước lệnh `JsonEncoder.withIndent('  ').convert(event)`.
3. **Fix Retry P1-4**: Cập nhật `AuthTokenRepositoryImpl._refresh` để không retry khi gặp lỗi 401/403/404.

### Giai đoạn 2: Tinh chỉnh Xử lý Lỗi & Tối ưu Hóa (Error Handling & Performance)
1. Thay thế vòng lặp $O(N^2)$ trong `MessageRemoteDataSourceImpl.listMessages` bằng thuật toán $O(N)$.
2. Chuẩn hóa các Exception: không ném `ChatApiException(statusCode: 200)`. Tạo `ChatDataException` cho các trường hợp parse dữ liệu rỗng.

### Giai đoạn 3: Tách Biệt Ngôn ngữ (Localization & Clean Domain)
1. Chuyển đổi logic sinh chuỗi hệ thống (System messages text) từ `MessageModel` và `NativeRealtimeDataSourceImpl` về tầng UI (`chat_ui`), chỉ lưu thông tin sự kiện dạng có cấu trúc trong `Message.metadata`.

### Giai đoạn 4: Chuẩn hóa Public API & Tẩy sạch Dead Code ACS
1. Đánh dấu `@deprecated` cho `ChatModuleConfig.acsEndpoint` và loại bỏ import `chat_native_platform_interface` không sử dụng trong `NativeRealtimeDataSourceImpl`.
2. Tái cấu trúc thư mục thành `lib/src/` và dọn dẹp `lib/chat_core.dart` để chỉ export Domain API.

### Giai đoạn 5: Tăng cường Test Coverage
1. Bổ sung bộ test cho `NativeRealtimeDataSourceImpl` (Mock WebSocket stream, giả lập mất mạng, reconnect, heartbeat).
2. Bổ sung test cho `JsonApiClient` và các Data Source parsing.

---

## 17. Production Readiness Verdict

```text
🟡 READY WITH MINOR FIXES  (Đối với ứng dụng nội bộ hiện tại)
⚠️ READY WITH MAJOR FIXES  (Nếu xuất bản thành thư viện/SDK công khai cho bên thứ ba)
```

### Must Fix Before Next Release:
1. Sửa lỗi `leaveActiveRoom()` làm mất realtime sau khi resume app (Bug P0-1).
2. Thêm cờ kiểm tra `ChatLogger.enabled` trước khi format Pretty JSON cho WebSocket event (P1-2).
3. Ngăn chặn retry 3 lần vô ích khi `fetchToken` gặp lỗi 401/403 (P1-4).

### Should Fix:
1. Tách chuỗi hiển thị tiếng Việt ra khỏi Data Layer để hỗ trợ đa ngôn ngữ (i18n).
2. Tối ưu thuật toán quét sự kiện `RoomUpdated` từ $O(N^2) \to O(N)$ trong `listMessages`.
3. Loại bỏ `acsEndpoint` bắt buộc trong cấu hình khởi tạo.

### Nice to Have:
1. Bổ sung cơ chế sync/catch-up tin nhắn tự động sau khi WebSocket reconnect.
2. Tăng độ phủ Unit Test cho các Remote DataSources và Network Client lên $>70\%$.
