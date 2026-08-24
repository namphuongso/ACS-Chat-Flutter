# Chat Core Package — Comprehensive Code Review (Part 5)

> **Ngày review:** 2026-08-24  
> **Phạm vi:** Toàn bộ `packages/chat_core` — 84 file `.dart`, ~6.029 LOC  
> **Tiêu chuẩn review:** Senior Flutter Architect / SDK Engineer & Code Reviewer  
> **Prompt tham chiếu:** `review/prompt.md`

---

## 1. Tổng Quan Kiến Trúc

```
chat_core/
├── chat_core.dart              ← Barrel export (93 dòng, export toàn bộ)
├── core/
│   ├── config/                 ← ChatModuleConfig
│   ├── constants/              ← ChatApiEndpoints
│   ├── data/models/            ← ChatUserModel, ChatMemberModel
│   ├── domain/entities/        ← ChatUser, ChatMember
│   ├── error/                  ← ChatException hierarchy
│   ├── network/                ← JsonApiClient
│   └── utils/                  ← Logger, MIME, UserUtils
├── features/
│   ├── auth_token/             ← ACS token provider + repository
│   ├── contact/                ← Search contacts
│   ├── conversation_list/      ← CRUD room, members, upload
│   └── thread/                 ← Messages, realtime WS, polling, cache
```

### Điểm mạnh kiến trúc hiện tại

- ✅ Tách rõ Domain / Data / DataSource theo feature-based structure
- ✅ Dependency direction đúng: Domain không import Data
- ✅ Repository pattern nhất quán, dễ mock cho test
- ✅ Use case classes mỏng, chỉ delegate — phù hợp với scope library
- ✅ `web_socket_channel` thuần Dart, không phụ thuộc Flutter widget
- ✅ Config tập trung qua `ChatModuleConfig` với backward-compatible defaults

### Điểm yếu kiến trúc

| Vấn đề | Mức độ | Ghi chú |
|---|:---:|---|
| Barrel export toàn bộ implementation detail | **P1** | Consumer phụ thuộc trực tiếp vào datasource/repository impl |
| `WebSocketRealtimeDataSourceImpl` god class | **P1** | 840 dòng, ~10 responsibilities trong 1 class |
| `MessageRemoteDataSourceImpl` tự quản HTTP riêng | P2 | Không dùng chung `JsonApiClient` → duplicate header/error logic |
| `SystemMessageTextBuilder` static mutable resolver | P2 | Global state khó test, race khi multi-isolate |

---

## 1.5 Trạng Thái Fix Từ P4 (`b19db92` → `1b83532`)

Commit hiện tại (`1b83532` — "review before public production") thay đổi 15 file trong `chat_core`: +1060/-911 dòng.

| Issue từ P4 | Mức độ | Trạng thái tại `1b83532` | Đánh giá fix |
|---|:---:|:---:|---|
| **N-C4-1: `ChatDataException` extends `ChatApiException`, synthetic `statusCode=422`** | P3 | ✅ **ĐÃ FIX ĐẦY ĐỦ** | Tạo `ChatException` base abstract class; `ChatDataException` giờ extends `ChatException` trực tiếp với `statusCode` nullable + `isHttpError=false`. Thiết kế đúng chuẩn. |
| **N-C4-2: Thiếu test exception contract** | P2 | ⚠️ **FIX MỘT PHẦN** | Thêm test cho exception hierarchy nhưng test chỉ verify constructor properties, KHÔNG test actual throw từ datasource methods. |
| **N1: `updateType.contains('name')` false positive** | TB/P2 | ✅ **ĐÃ FIX** | Split bằng comma thành tokens rồi exact match. Xử lý đúng `'name,avatar'` và tránh false-positive `'username'`. |
| **N-C3-3: Naming native/websocket bất đối xứng** | P3 | ✅ **ĐÃ FIX** | File + class + interface đổi tên đồng bộ sang `WebSocket*`. Old file giữ re-export stub cho backward compat. |
| **Barrel layer leak** | P2 | ❌ **TỆ HƠN** | Thêm 2 exports mới (`websocket_realtime_datasource.dart` + `_impl.dart`). Implementation leak tiếp tục mở rộng. |
| **Hardcoded Vietnamese text (i18n)** | P1 chấp nhận | ⚠️ Vẫn mở | `SystemMessageTextBuilder` vẫn hardcode tiếng Việt. CustomResolver là escape hatch nhưng static mutable. |
| **N4: `customResolver` static mutable** | P2 | ⚠️ Vẫn mở | Không đổi. |
| **N5: `parseEventDate` giả định UTC** | Thấp | ⚠️ Vẫn mở | Không đổi. |

**Nhận xét:** Commit này xử lý tốt 3/8 carryover issues (trong đó 1 issue chính P3). Tuy nhiên barrel export đi ngược hướng — thay vì thu hẹp, lại thêm implementation exports.

### Chi tiết fix đáng chú ý

#### `ChatException` hierarchy mới ✅

```dart
// TRƯỚC (P4):
class ChatApiException implements Exception { ... }
class ChatDataException extends ChatApiException {
  // Kế thừa statusCode=422 không hợp lý
}

// SAU (P5):
abstract class ChatException implements Exception {
  String get code;
  String get message;
  bool get isHttpError;
}
class ChatApiException extends ChatException { ... }  // isHttpError=true
class ChatDataException extends ChatException { ... } // isHttpError=false, statusCode nullable
```

Đây là improvement quan trọng vì consumer có thể catch riêng lỗi dữ liệu vs lỗi HTTP mà không nhầm lẫn status code.

#### `updateType` token-based matching ✅

```dart
// TRƯỚC: updateType.contains('name') → 'username' cũng match (false positive)
// SAU:
final tokens = updateType.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
if (tokens.contains('all') || updateType == 'all') { ... }
else if (tokens.contains('name') || updateType == 'name') { ... }
```

Xử lý đúng format comma-separated values từ BE.

#### Barrel export mới ⚠️

```dart
+export 'features/thread/data/datasources/websocket_realtime_datasource.dart';
+export 'features/thread/data/datasources/websocket_realtime_datasource_impl.dart';
```

Consumer giờ có thể import trực tiếp `WebSocketRealtimeDataSourceImpl` (840 dòng god class). Khi refactor class này theo khuyến nghị P5, sẽ breaking change.

---

## 2. Phát Hiện Chi Tiết Theo Category

### 2.1 Architecture & Separation of Concerns

#### A-P5-1 [P0]: `WebSocketRealtimeDataSourceImpl` — God class, quá nhiều responsibility

**File:** `lib/features/thread/data/datasources/websocket_realtime_datasource_impl.dart` (840 dòng)

Class này đồng thời đảm nhận:

1. Quản lý kết nối WebSocket (`_ensureConnected`)
2. Reconnect logic với exponential backoff + jitter
3. Heartbeat timer và idle timeout detection
4. Parse + route ~15 loại event type (`NewMessage`, `MessageDeleted`, `MessagePinned`, `RoomCreated`, `RoomUpdated`, `RoomDisbanded`, `MemberJoined/Left/Removed`, ...)
5. Build system message text (duplicate một phần logic của `SystemMessageTextBuilder`)
6. Read receipt tracking (`_lastVisibleMessageId`)
7. Room enter/leave state management
8. Session expiry detection + callback
9. Broadcast stream management cho thread-level và list-level

**Tại sao nguy hiểm:**
- Bất kỳ thay đổi nào ở event parsing đều có nguy cơ break connection logic
- Không thể unit test từng responsibility độc lập
- Khi debug realtime bug, developer phải đọc qua 840 dòng để tìm đúng section
- Thêm event type mới làm class tiếp tục phình to

**Khuyến nghị:**
```
WebSocketConnectionManager     ← connect, heartbeat, reconnect, dispose
WebSocketEventParser           ← parse raw JSON → typed event objects
WebSocketEventDispatcher       ← route events → thread/list controllers
ReadReceiptManager             ← track lastVisibleMessageId, send/clear
```

#### A-P5-2 [P2]: `MessageRemoteDataSourceImpl` không dùng `JsonApiClient`

**File:** `lib/features/thread/data/datasources/message_remote_datasource_impl.dart`

Trong khi `ConversationRemoteDataSourceImpl` và `ContactRemoteDataSourceImpl` dùng chung `JsonApiClient`, file này tự tạo `http.Client` riêng và duplicate:
- Header construction (`Authorization`, `X-API-KEY`, `Content-Type`)
- Error parsing (`statusCode != 200/201` → throw `ChatApiException`)
- Response decoding (`jsonDecode(response.body)`)

**Impact:** Khi cần thêm header mới (ví dụ trace-id), phải sửa ở 3 nơi thay vì 1. Risk của drift giữa các datasource rất cao.

#### A-P5-3 [P2]: `SystemMessageTextBuilder.customResolver` static mutable global

**File:** `lib/features/thread/domain/services/system_message_text.dart:26`

```dart
static SystemMessageCustomResolver? customResolver;
```

Global mutable state gây khó test (test A set resolver, test B bị ảnh hưởng). Nếu library chạy trong isolate khác, resolver sẽ không propagate.

---

### 2.2 API Efficiency & Network

#### N-P5-1 [P1]: Pagination `hasMore = items.isNotEmpty` gây request dư thừa

**File:** `conversation_remote_datasource_impl.dart:69`

```dart
final hasMore = items.isNotEmpty;
```

Nếu BE trả đúng `limit=20` items ở page cuối cùng, `hasMore=true` nhưng trang kế tiếp sẽ trả rỗng. UI sẽ trigger thêm 1 request không cần thiết.

**Khuyến nghị:** So sánh `items.length < limit` để xác định `hasMore=false`.

#### N-P5-2 [P2]: `getRoomReactions` và `getMessageReactions` hardcoded `pageSize: '50'`

Không có tham số phân trang từ caller. Nếu room có >50 reactions, dữ liệu sẽ bị cắt im lặng.

#### N-P5-3 [P2]: `listMessages` hardcoded `'pageSize': '50'`

Caller (`MessageRepository`) không có cách kiểm soát số tin mỗi lần load. Với thread dài, load history đầu tiên luôn fetch 50 tin dù UI chỉ hiển thị 20.

#### N-P5-4 [P3]: ACS endpoint `acsThreadMessages` định nghĩa nhưng không sử dụng

Dead code. Có thể gây nhầm lẫn rằng thư viện gọi trực tiếp ACS REST cho list messages, trong khi thực tế đang đi qua BE proxy `/api/chat/get-messages`.

---

### 2.3 Memory / Resource Issues

#### R-P5-1 [P1]: `stopWatchingList()` đóng controller nhưng KHÔNG ngắt kết nối WebSocket

**File:** `websocket_realtime_datasource_impl.dart:810-813`

```dart
Future<void> stopWatchingList() async {
    final controller = _listController;
    _listController = null;
    await controller?.close();
}
```

Sau khi gọi `stopWatchingList()`:
- Controller đã đóng → không nhận data nữa
- Nhưng `_channel` vẫn mở, heartbeat timer vẫn chạy
- Nếu không còn thread watcher nào, kết nối WebSocket được giữ vô nghĩa

**Khuyến nghị:** Sau khi close controller, nếu `_threadControllers.isEmpty && _threadIdsByRoom.isEmpty && _watchedRoomIds.isEmpty` thì gọi `_closeSocket()`.

#### R-P5-2 [P2]: `leaveActiveRoom()` clear `_activeRoomIds` nhưng giữ nguyên `_watchedRoomIds`

**File:** `websocket_realtime_datasource_impl.dart:665-684`

```dart
void leaveActiveRoom() {
    ...
    _lastVisibleMessageId = null;
    _activeRoomIds.clear();
    // _watchedRoomIds KHÔNG được clear
    // _threadIdsByRoom KHÔNG được clear
}
```

State inconsistency: sau khi background → foreground, nếu user quay lại cùng room, `watchNewMessages()` sẽ add lại vào `_activeRoomIds`. Nhưng nếu user chuyển sang room khác mà không gọi `watchNewMessages()` cho room cũ, `_watchedRoomIds` vẫn chứa room cũ → server sẽ re-enter room cũ khi reconnect.

#### R-P5-3 [P2]: `PollingEngine._controller` không có `onCancel` listener cleanup

Broadcast stream controller không tự động stop polling khi tất cả listeners cancel. Chỉ `dispose()` mới dừng timer. Nếu caller quên gọi `stopWatching()`, timer sẽ chạy vô hạn.

---

### 2.4 Crash / Reliability Issues

#### C-P5-1 [P0]: Race condition trong `AuthTokenRepositoryImpl.refresh()`

**File:** `auth_token_repository_impl.dart:38-42`

```dart
Future<void> refresh(String roomId) async {
    _cached.remove(roomId);
    await getAccessToken(roomId);
}
```

Scenario lỗi:
1. Thread A gọi `getAccessToken(roomId)` → bắt đầu fetch, tạo `_inFlight[roomId]`
2. Token trả về hết hạn ngay → Thread B gọi `refresh(roomId)`
3. `refresh()` xóa `_cached[roomId]`
4. `refresh()` gọi `getAccessToken(roomId)` → thấy `_inFlight[roomId]` vẫn tồn tại → trả về FUTURE CŨ (token đã expired)
5. Token expired vẫn được dùng → API call tiếp theo fail 401

**Fix:** Trong `refresh()`, xóa cả `_inFlight[roomId]` trước khi gọi `getAccessToken()`:
```dart
Future<void> refresh(String roomId) async {
    _cached.remove(roomId);
    _inFlight.remove(roomId); // ← THÊM DÒNG NÀY
    await getAccessToken(roomId);
}
```

#### C-P5-2 [P1]: WebSocket `_ensureConnected` — race giữa connect timeout và dispose

**File:** `websocket_realtime_datasource_impl.dart:78-120`

```dart
await channel.ready.timeout(const Duration(seconds: 15));
if (_disposed) { ... }
```

Nếu `dispose()` được gọi TRONG khi đang chờ `channel.ready.timeout(15s)`:
1. `dispose()` set `_disposed = true`, gọi `_closeSocket()` 
2. `_closeSocket()` tìm `_channel` → null (chưa assign) → không close gì
3. Sau 15s, `channel.ready` resolve hoặc timeout
4. Code check `if (_disposed)` → đóng channel này ✅
5. NHƯNG nếu timeout xảy ra trước → catch block gọi `_scheduleReconnect()` → check `_disposed` → return ✅

Trường hợp edge: nếu `channel.ready` resolve NGAY SAU khi check `_disposed == false` nhưng trước khi gán `_channel = channel` — khả năng rất thấp nhưng tồn tại trong async context.

**Đánh giá thực tế:** Risk thấp vì Dart single-threaded event loop. Không phải blocker nhưng nên thêm guard.

#### C-P5-3 [P1]: Event ID collision bằng timestamp milliseconds

**File:** `websocket_realtime_datasource_impl.dart` (nhiều vị trí)

```dart
id: 'room_created_${DateTime.now().millisecondsSinceEpoch}',
id: 'member_joined_${DateTime.now().millisecondsSinceEpoch}',
...
```

Hai event cùng loại đến trong cùng 1 millisecond sẽ có ID giống nhau → consumer dedup bằng ID sẽ drop event thứ hai.

**Khuyến nghị:** Dùng UUID hoặc ít nhất tăng thêm counter.

#### C-P5-4 [P2]: `PollingEngine` swallow mọi exception không log

**File:** `polling_engine.dart:63-66`

```dart
} catch (e) {
    _consecutiveErrors++;
    // Không log gì cả
}
```

Khi polling fail liên tục (ví dụ token hết hạn → 401), developer không có cách nào biết tại sao. Chỉ thấy "không nhận được tin mới".

**Khuyến nghị:** Ít nhất log `ChatLogger.warn('Polling failed', error: e)`.

#### C-P5-5 [P2]: `_extractUrls` heuristic fragile cho upload response

**File:** `conversation_remote_datasource_impl.dart:497-535`

Recursive search toàn bộ JSON tree để tìm URL. Nếu BE thêm field metadata chứa URL không liên quan (ví dụ `callbackUrl`), function sẽ trả sai URL.

---

### 2.5 Realtime / ACS Integration

#### RT-P5-1 [P1]: Không có deduplication cho incoming realtime messages

`WebSocketRealtimeDataSourceImpl._handleSocketData` emit mọi message nhận được vào stream. Nếu server gửi duplicate event (do reconnect re-enter room), consumer sẽ nhận trùng.

**Khuyến nghị:** Maintain `Set<String>` recent message IDs (LRU cache ~100 entries).

#### RT-P5-2 [P1]: Reconnect không re-fetch missed messages

Khi WebSocket disconnect rồi reconnect:
1. Server gửi event `connected`
2. Client re-enter rooms
3. Tin nhắn gửi trong thời gian offline bị mất

Consumer phải tự phát hiện gap (qua timestamp) và gọi REST `listMessages` để fill. Nhưng `chat_core` không expose signal nào (như `onReconnected` callback) để UI biết cần refetch.

#### RT-P5-3 [P2]: Heartbeat interval lấy từ server nhưng không validate upper bound

```dart
final interval = _intValue(event['heartbeatIntervalSeconds']) ?? 30;
_startHeartbeat(Duration(seconds: max(5, interval)));
```

Nếu server gửi `heartbeatIntervalSeconds: 3600`, client sẽ đợi 1 giờ trước khi heartbeat. Nên cap tối đa (ví dụ 120s).

---

### 2.6 Public API Design

#### API-P5-1 [P1]: Barrel file export toàn bộ implementation

**File:** `lib/chat_core.dart:68-90`

```dart
export 'features/auth_token/data/datasources/auth_token_remote_datasource_impl.dart';
export 'features/conversation_list/data/datasources/conversation_remote_datasource_impl.dart';
export 'features/thread/data/datasources/websocket_realtime_datasource_impl.dart';
export 'features/thread/data/repositories/message_repository_impl.dart';
...
```

Consumer có thể import và phụ thuộc trực tiếp vào implementation class. Khi refactor internals, sẽ breaking change cho consumer.

**Khuyến nghị:** Chỉ export:
- Domain entities
- Repository interfaces
- Use cases
- Config + Logger + Exception
- Factory/builder function để khởi tạo SDK

Implementation details nên nằm trong `src/` hoặc không export.

#### API-P5-2 [P2]: Không có factory/entry point để khởi tạo SDK

Consumer phải tự tạo từng component (`JsonApiClient`, `AuthTokenRepositoryImpl`, `ConversationRepositoryImpl`, ...) rồi wire chúng lại. Không có `ChatSdk.create(config)` hay tương tự.

**Risk:** Consumer wire sai dependency (dùng 2 instance `http.Client` riêng biệt), hoặc quên gọi `dispose()`.

#### API-P5-3 [P2]: `Conversation.copyWith()` không cho phép set `null` cho optional fields

```dart
Conversation copyWith({
    String? avatarUrl,  // không thể set avatarUrl = null
})
```

Khi muốn xóa avatar, không thể truyền `null`. Cần sentinel value hoặc parameter `clearAvatar = true`.

---

### 2.7 Performance

| Scenario | Đánh giá | Ghi chú |
|---|:---:|---|
| Small chat (<100 tin) | ✅ Tốt | Polling/WS đủ nhanh, cache giúp load tức thì |
| Medium chat (100–1000 tin) | ⚠️ Chấp nhận được | `_saveToCache` load toàn bộ cache rồi merge — O(n) mỗi lần |
| Large chat (>1000 tin) | ❌ Nguy hiểm | Cache merge O(n) mỗi lần, không có index hay limit |
| Group >20 người | ⚠️ | `pollingIntervalLargeGroup` config sẵn nhưng chưa dùng |

#### Perf-P5-1 [P2]: Cache merge O(n) mỗi lần listMessages

Mỗi lần load thêm 1 trang tin nhắn, `_saveToCache` gọi:
1. `local.getCachedMessages(threadId)` — load TOÀN BỘ cache
2. Merge bằng Map
3. `local.saveMessages(threadId, merged)` — ghi lại TOÀN BỘ

Với 1000 tin × 20 lần scroll = 20.000 operations. Nên dùng batch insert hoặc delta update.

---

### 2.8 Testability & Coverage

#### Test files hiện có (8 files, 806 dòng):

| File | Coverage |
|---|---|
| `auth_token_repository_test.dart` | ✅ Token caching, retry |
| `chat_api_exception_test.dart` | ✅ Exception parsing |
| `chat_user_utils_test.dart` | ✅ User ID normalization |
| `conversation_remote_datasource_test.dart` | ⚠️ Chỉ 15 dòng (stub?) |
| `system_message_text_test.dart` | ⚠️ 35 dòng (chưa cover hết event types) |
| `group_conversation_test.dart` | ⚠️ Basic |
| `message_repository_cache_test.dart` | ✅ Cache merge logic |
| `message_test.dart` | ✅ Model parsing |

#### Test còn thiếu hoàn toàn:

| Area | Impact |
|---|---|
| WebSocket connect/disconnect/reconnect lifecycle | **Critical** |
| WebSocket event parsing (15+ event types) | High |
| PollingEngine backoff + recovery | High |
| Upload file via SAS (3-step flow) | Medium |
| Conversation pagination | Medium |
| Contact search pagination | Low |
| Integration REST + realtime conflict | Critical |
| Token refresh race condition | Critical |
| Read receipt send/clear lifecycle | Medium |

---

## 3. Flow Xuyên Suốt: Send Message → Realtime → UI

```
UI gọi SendMessageUseCase
    ↓
MessageRepositoryImpl.sendMessage()
    ↓
MessageRemoteDataSourceImpl.sendMessage()
    ├── getAppToken()           ← app JWT
    ├── getAccessToken(roomId)  ← ACS token (có cache + retry)
    └── POST /api/chat/send-message  (raw http.Client, KHÔNG JsonApiClient)
    ↓
_appendToCache(threadId, message)
    └── Lưu local cache (newest-first)
    ↓
Return Message entity cho UI

--- Song song ---

WebSocket nhận event NewMessage
    ↓
_handleSocketData → _handleRoomEvent
    ↓
MessageModel.fromWebSocketJson(rawMessage, threadId)
    ↓
_emit(message) → broadcast stream
    ↓
MessageRepositoryImpl.watchNewMessages().map((msg) {
    unawaited(_appendToCache(...));  // fire-and-forget cache save
    return msg;
})
    ↓
UI subscription nhận Message
```

**Vấn đề trong flow:**
1. Optimistic message (từ sendMessage) và realtime message (từ WS) có thể trùng ID → UI hiển thị 2 bubble nếu không dedup
2. Cache append là fire-and-forget (`unawaited`) — nếu cache save fail, tin sẽ biến mất khi mở lại thread
3. `sendMessage` tạo message với `senderDisplayName: ''` — UI phải tự lookup tên người gửi

---

## 4. Bảng Tổng Hợp Priority

| Priority | Issue | File | Impact | Effort | Recommendation |
|:---:|---|---|:---:|:---:|---|
| **P0** | Token refresh race với in-flight future | `auth_token_repository_impl.dart:38` | Critical | Low | Clear `_inFlight` trong `refresh()` |
| **P0** | God class WebSocket (840 dòng) | `websocket_realtime_datasource_impl.dart` | High | High | Tách thành Connection Manager + Event Parser + Dispatcher |
| **P1** | Barrel export implementation detail | `chat_core.dart:68-90` | High | Medium | Giảm export xuống domain + usecase + factory |
| **P1** | `stopWatchingList()` không disconnect socket | `websocket_realtime_datasource_impl.dart:810` | Medium | Low | Check empty watchers → close socket |
| **P1** | Không dedup realtime messages | `websocket_realtime_datasource_impl.dart` | Medium | Medium | LRU Set message IDs |
| **P1** | Pagination `hasMore = items.isNotEmpty` | `conversation_remote_datasource_impl.dart:69` | Medium | Low | Compare `items.length < limit` |
| **P1** | Event ID collision (timestamp ms) | `websocket_realtime_datasource_impl.dart` nhiều chỗ | Medium | Low | UUID hoặc atomic counter |
| **P1** | Reconnect không signal missed messages | `websocket_realtime_datasource_impl.dart` | High | Medium | Callback/stream `onReconnected` |
| **P2** | `MessageRemoteDataSource` không dùng JsonApiClient | `message_remote_datasource_impl.dart` | Maintainability | Medium | Refactor dùng chung client |
| **P2** | Polling engine silent failure | `polling_engine.dart:63` | Debugging | Low | Add warn log |
| **P2** | `leaveActiveRoom` state inconsistency | `websocket_realtime_datasource_impl.dart:665` | State bug | Low | Clear cả watched + threadIdsByRoom |
| **P2** | Cache merge O(n) mỗi lần | `message_repository_impl.dart:130-150` | Performance | Medium | Batch/delta update |
| **P2** | Static customResolver | `system_message_text.dart:26` | Testability | Low | Instance injection |
| **P2** | Thiếu SDK entry point/factory | Toàn bộ package | DX | Medium | Thêm `ChatSdk.create(config)` |
| **P2** | Hardcoded pageSize 50 | `message_remote_datasource_impl.dart` | Flexibility | Low | Expose config param |
| **P2** | Heartbeat interval không cap upper bound | `websocket_realtime_datasource_impl.dart:600` | Reliability | Low | Cap max 120s |
| **P3** | Dead code `acsThreadMessages` | `chat_api_endpoints.dart:53` | Readability | Trivial | Remove |
| **P3** | `_extractUrls` fragile heuristic | `conversation_remote_datasource_impl.dart:497` | Correctness | Low | Require explicit field contract |
| **P3** | `copyWith` không clear nullable fields | `conversation.dart:80-105` | API design | Low | Sentinel hoặc bool flag |
| **P3** | Vietnamese hardcoded (i18n) | Nhiều file | Extensibility | Medium | Localization support |

---

## 5. Recommended Target Architecture

```
Current:
┌──────────────────────────────────────────────┐
│ chat_core.dart (barrel export everything)    │
├──────────────────────────────────────────────┤
│ features/                                    │
│   ├── auth_token/  (domain + data)           │
│   ├── conversation_list/  (domain + data)    │
│   ├── thread/                                │
│   │     ├── domain/                          │
│   │     └── data/                            │
│   │         ├── datasources/                 │
│   │         │   ├── websocket_realtime...    │ ← 840-line god class
│   │         │   ├── message_remote...        │ ← duplicates HTTP logic
│   │         │   └── polling_engine.dart       │
│   │         ├── models/                      │
│   │         └── repositories/                │
│   └── contact/                               │
└──────────────────────────────────────────────┘

Target:
┌──────────────────────────────────────────────┐
│ chat_core.dart                               │
│   exports: entities, repos, usecases,        │
│            config, exceptions,               │
│            ChatSdkFactory                    │
├──────────────────────────────────────────────┤
│ src/                                         │
│   ├── core/                                  │
│   │     ├── network/json_api_client.dart     │ ← SINGLE HTTP client
│   │     ├── websocket/                       │
│   │     │   ├── connection_manager.dart      │ ← connect/reconnect/heartbeat
│   │     │   ├── event_parser.dart            │ ← JSON → typed events
│   │     │   ├── event_dispatcher.dart        │ ← route → streams
│   │     │   └── read_receipt_manager.dart    │ ← lastVisible tracking
│   │     └── error/                           │
│   ├── features/                              │
│   │     ├── auth/                            │
│   │     ├── conversations/                   │
│   │     ├── messaging/                       │
│   │     └── contacts/                        │
│   └── chat_sdk_factory.dart                  │ ← Wire dependencies
└──────────────────────────────────────────────┘
```

---

## 6. Migration Plan

### Phase 1 — Critical Fixes (1–2 ngày)
1. Fix `AuthTokenRepositoryImpl.refresh()` race condition (1 dòng)
2. Fix pagination `hasMore` logic (1 dòng)
3. Add `stopWatchingList()` socket cleanup
4. Add event deduplication (LRU set)
5. Add `ChatLogger.warn` trong PollingEngine catch block

### Phase 2 — Architecture Refactor (3–5 ngày)
1. Extract `WebSocketEventParser` từ god class
2. Extract `WebSocketConnectionManager`
3. Refactor `MessageRemoteDataSourceImpl` dùng `JsonApiClient`
4. Thêm `onReconnected` stream/callback
5. Replace timestamp IDs với UUID/counter

### Phase 3 — Public API Cleanup (2–3 ngày)
1. Restructure barrel export (breaking change — version bump)
2. Thêm `ChatSdkFactory.create(config)` entry point
3. Remove dead code (`acsThreadMessages`)
4. Fix `copyWith` nullable field semantics

### Phase 4 — Testing (3–5 ngày)
1. Unit test WebSocket connection lifecycle (mock web_socket_channel)
2. Unit test từng event type parsing
3. Unit test PollingEngine backoff/recovery
4. Integration test: REST send → WS receive → cache write
5. Race condition test: concurrent token refresh

### Phase 5 — Polish (1–2 ngày)
1. i18n support cho system messages
2. Configurable page sizes
3. Heartbeat upper bound validation
4. Documentation cho public API

---

## 7. Scorecard

| Tiêu chí | Điểm (thang 10) | Ghi chú |
|---|:---:|---|
| Architecture | 6.5 | Clean layers tốt nhưng god class + barrel leak kéo điểm xuống |
| Maintainability | 6.0 | 840-line class khó maintain; duplicate HTTP logic |
| Readability | 6.5 | Comment tiếng Việt tốt, naming rõ; nhưng code dài |
| Performance | 7.0 | OK cho small chat; O(n) cache merge cho large chat |
| API Efficiency | 7.0 | Pagination hasMore sai; hardcoded limits; unused ACS endpoint |
| Memory Safety | 6.5 | Socket leak sau stopWatchingList; polling không auto-stop |
| Crash Safety | 7.5 | Exception hierarchy cải thiện (+0.5); token race vẫn P0; event ID collision |
| Testability | 5.5 | Static resolver; god class; thiếu coverage quan trọng |
| Extensibility | 6.0 | Thêm event type mới phải sửa god class |
| Public API Design | 5.0 | Export everything + thêm mới (−0.5); không entry point; copyWith limitation |
| **Production Readiness** | **6.5** | Cải thiện từ P4 (7.5→6.5 so sánh relative); internal MVP OK; chưa đủ public SDK |

---

## 8. Production Readiness Verdict

```text
⚠️ READY WITH MAJOR FIXES
```

So với P4, commit `1b83532` đã xử lý đúng 3 carryover issues (exception hierarchy, updateType parsing, native→websocket naming) — đây là tiến bộ tích cực. Tuy nhiên barrel export đi ngược hướng khi thêm implementation exports mới, và các critical issues về WebSocket lifecycle, token race condition vẫn chưa được address.

Sẵn sàng cho **internal MVP** với scope giới hạn (small team, small chat volume, single platform). Chưa đủ điều kiện **publish public SDK** do:

### Must Fix Before Release (public):
1. **Token refresh race condition** — có thể gây cascading 401 errors trong production khi token gần hết hạn
2. **WebSocket resource leak** — `stopWatchingList()` giữ socket mở → battery drain, server connection pool exhaustion
3. **Barrel export implementation** — bất kỳ refactor nào sẽ breaking change cho consumer

### Should Fix:
1. God class WebSocket — tách trách nhiệm trước khi thêm feature mới
2. Pagination `hasMore` — gây request waste trên production
3. Realtime deduplication — tránh double-render tin nhắn
4. Reconnect gap detection — tin nhắn mất trong lúc offline
5. Test coverage cho WebSocket lifecycle

### Nice to Have:
1. i18n cho system messages
2. Configurable page size / polling interval runtime
3. `ChatSdkFactory` entry point
4. Structured error codes cho upload flow
5. Delta cache update thay vì full rewrite

---

*Review bởi Codex Agent — Part 5, dựa trên prompt.md yêu cầu senior architect perspective.*

---

## Kiểm Tra Đã Thực Hiện

- ⚠️ **Không chạy được `dart pub get`, `dart analyze`, `dart test`** — Flutter SDK cache ngoài sandbox (giới hạn tương tự P4).
- ✅ Đọc toàn bộ 84 file `.dart` trong `packages/chat_core/lib/` (~6.029 LOC).
- ✅ Đọc toàn bộ 8 test files (806 LOC).
- ✅ Phân tích git diff `b19db92..1b83532` cho 15 file thay đổi (+1060/-911).
- ✅ Trace flow xuyên suốt: UI → UseCase → Repository → DataSource → REST/WebSocket → Cache.
- ✅ Verify carryover issues từ P4 review.
- ✅ Xác nhận `ChatDataException` không còn extends `ChatApiException`.
- ✅ Xác nhận barrel export đã thêm implementation exports mới.
