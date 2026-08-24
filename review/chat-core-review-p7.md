# Code Review: `chat_core` Package (Phase 7)

> **Scope**: Toàn bộ package `chat_core` — domain + data layer cho module chat (ACS + BE nội bộ). Dart thuần, không phụ thuộc widget UI.
>
> **Files reviewed**: 85 source files, 10 test files, ~3,500 LOC (source) + ~1,000 LOC (tests)
>
> **Reviewer perspective**: Senior Flutter/Library Architect

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Review](#2-architecture-review)
3. [Folder / Module Structure](#3-folder--module-structure)
4. [Issue Details](#4-issue-details)
5. [Memory / Resource Issues](#5-memory--resource-issues)
6. [Crash / Reliability Issues](#6-crash--reliability-issues)
7. [Realtime / WebSocket Issues](#7-realtime--websocket-issues)
8. [UI Architecture](#8-ui-architecture)
9. [Public API Review](#9-public-api-review)
10. [Performance Review](#10-performance-review)
11. [Testability](#11-testability)
12. [Refactoring Priority](#12-refactoring-priority)
13. [Target Architecture](#13-target-architecture)
14. [Migration Plan](#14-migration-plan)
15. [Production Readiness Verdict](#15-production-readiness-verdict)

---

## 1. Executive Summary

**Điểm mạnh chính:**

- Clean Architecture layers rõ ràng (domain → data → datasource), dễ hiểu và dễ tìm code.
- WebSocket implementation chất lượng cao: heartbeat, exponential backoff reconnect, jitter, dedup, session expired handling.
- Cache-first strategy hợp lý cho conversation list và message history.
- Public API barrel files (`chat_core.dart` / `chat_core_impl.dart`) tách riêng public interface và internal implementation.
- Error handling nhất quán qua `ChatApiException` / `ChatDataException`.
- Model parsing resilient — fallback nhiều field names, parse date an toàn, không crash khi thiếu data.

**Vấn đề chính:**

- `sendMessage` gọi ACS token API dư thừa mỗi lần gửi tin (~100-300ms latency thêm).
- `listMessages` bỏ qua tham số `startTime`, pagination không hiệu quả.
- `unreadCount` chỉ binary 0/1 thay vì count thực.
- Entity `ChatAccessToken` chứa logic thời gian (`isExpired`, `needsRefresh`) — impure entity.
- Code chết: polling engine trong `MessageRemoteDataSourceImpl` không được sử dụng.
- Token ACS lưu trong `Conversation` entity — rủi ro bảo mật nếu entity bị serialize/log.
- Duplicate MIME type resolution logic.
- `leaveActiveRoom` không dọn dẹp room tracking maps.

---

## 2. Architecture Review

### 2.1 Separation of Concerns

```
chat_core.dart          ← Public API barrel (interfaces + entities + use cases)
chat_core_impl.dart     ← Internal barrel (models + implementations)

core/
├── config/             ← ChatModuleConfig (DI config)
├── constants/          ← ChatApiEndpoints (centralized API paths)
├── data/models/        ← Shared DTOs (ChatUserModel, ChatMemberModel)
├── domain/entities/    ← Shared entities (ChatUser, ChatMember)
├── error/              ← ChatApiException, ChatDataException
├── network/            ← JsonApiClient (HTTP + envelope decoding)
└── utils/              ← ChatLogger, ChatMimeUtils, ChatUserUtils

features/
├── auth_token/         ← ACS token fetch + cache + retry
├── conversation_list/  ← Conversation CRUD, pagination, group mgmt
├── contact/            ← Contact search
└── thread/             ← Message CRUD, realtime (WebSocket + polling), reactions, pins
```

**Đánh giá:**

- ✅ Separation tốt: UI logic hoàn toàn nằm ngoài scope.
- ✅ Repository pattern rõ ràng: abstract interface → impl with remote + local datasources.
- ✅ Use cases clean — mỗi use case 1 responsibility.
- ⚠️ `ConversationRepository` quá lớn (295 LOC, 17 methods) — đang gánh CRUD + group management + member management + file upload. Nên tách member management và file upload thành feature riêng.
- ⚠️ `MessageRemoteDataSourceImpl` (727 LOC) — quá lớn, chứa CRUD + reactions + pinned messages + readers + resources + polling. Nên tách thành focused datasources.

### 2.2 Data Flow

```
UI → UseCase → Repository → RemoteDataSource → JsonApiClient → HTTP
                                        ↕
                                  LocalDataSource → Cache
                                        ↕
                         WebSocketRealtimeDataSource → WebSocketEventDispatcher → Stream<Message>
```

**Đánh giá:**
- ✅ Flow rõ ràng, không có circular dependency.
- ✅ Realtime (WebSocket) được tách riêng khỏi REST.
- ⚠️ `watchNewMessages` trong repository ưu tiên WebSocket, nhưng `MessageRemoteDataSource` vẫn giữ `_activePolling` map — code chết.

### 2.3 Dependency Direction

- ✅ Domain không phụ thuộc Data.
- ✅ Core không phụ thuộc Features.
- ⚠️ `system_message_text.dart` nằm trong `thread/domain/services/` nhưng import `ConversationType` từ `conversation_list/domain/entities/` — cross-feature dependency. Acceptable cho shared logic nhưng cần đánh dấu.

---

## 3. Folder / Module Structure

### Câu trả lời cho các câu hỏi đánh giá:

1. **Dễ tìm code?** ✅ Rất dễ. Feature-based structure, mỗi feature có data/domain separation rõ.
2. **Developer mới hiểu architecture nhanh?** ✅ Barrel files giúp import dễ. Clean architecture layers rõ ràng.
3. **Khi bug xảy ra, biết tìm ở đâu?** ✅ Tên file mô tả rõ responsibility. API calls → datasources, state → repository, parsing → models.
4. **Feature mới thêm không ảnh hưởng feature cũ?** ✅ Feature boundaries tốt, dependency direction đúng.
5. **Module quá lớn?** ⚠️ `MessageRemoteDataSourceImpl` (727 LOC) và `ConversationRemoteDataSourceImpl` (555 LOC).
6. **Module chứa nhiều responsibility?** ⚠️ `ConversationRepository` chứa conversation CRUD + member management + file upload.

### proposed structure (target)

```
lib/
├── chat_core.dart
├── chat_core_impl.dart
├── core/
│   ├── config/
│   ├── constants/
│   ├── data/models/
│   ├── domain/entities/
│   ├── error/
│   ├── network/
│   └── utils/
├── features/
│   ├── auth_token/          (giữ nguyên)
│   ├── conversation_list/   (tách member mgmt ra)
│   ├── contact/             (giữ nguyên)
│   ├── thread/              (tách reactions, pinned messages ra)
│   └── file_upload/         (mới — SAS upload logic)
└── ...
```

---

## 4. Issue Details

### 4.1 Performance / Unnecessary API Calls

#### ISSUE-001: `sendMessage` gọi ACS token API dư thừa [P1]

**File**: `message_remote_datasource_impl.dart:68-70`

```dart
final appToken = await _appTokenProvider.getAppToken();
final token = await _authTokenRepository.getAccessToken(roomId);  // ← DỰ THỪA
```

**Vấn đề**: Mỗi lần gửi tin nhắn, code gọi `getAccessToken(roomId)` chỉ để lấy `token.acsUserId` gán vào field `senderId` của message trả về. Nhưng message BE trả về đã có `data` (messageId), và `senderId` trên message object này chỉ dùng để tạo MessageModel trả về — UI hoàn toàn có thể lấy senderId từ context (current user).

**Impact**: Mỗi send message mất thêm 100-300ms do gọi API join-room (kể cả khi token đã cache, vẫn phải await). Trong group chat, mỗi tin gửi đều chịu latency này.

**Fix**: Bỏ `_authTokenRepository.getAccessToken(roomId)` trong `sendMessage`. Dùng `senderId` từ config hoặc truyền vào từ bên ngoài.

---

#### ISSUE-002: `listMessages` bỏ qua tham số `startTime` [P1]

**File**: `message_remote_datasource_impl.dart:94-118`

```dart
Future<PaginatedResult<MessageModel>> listMessages({
  required String roomId,
  required String threadId,
  String? startTime,        // ← Nhận tham số
  String? cursor,
}) async {
  final uri = Uri.parse(...).replace(queryParameters: {
    'roomId': roomId,
    'pageSize': '50',
    // ← startTime KHÔNG được đưa vào query params!
    if (cursor != null && cursor.isNotEmpty) 'continuationToken': cursor,
  });
```

**Vấn đề**: `startTime` được truyền từ repository nhưng không bao giờ được đưa vào HTTP request. Mỗi lần load history đều fetch 50 messages mới nhất thay vì chỉ fetch messages từ thời điểm mới.

**Impact**: Network waste, especially on slow connections. PollingEngine cũng gọi `listMessages(startTime: ...)` nhưng startTime không có effect.

**Fix**: Thêm `if (startTime != null && startTime.isNotEmpty) 'startTime': startTime` vào query params.

---

#### ISSUE-003: `listConversations` infers `hasMore` không chính xác [P2]

**File**: `conversation_remote_datasource_impl.dart:69`

```dart
final hasMore = items.length >= limit;
```

**Vấn đề**: Server trả đúng `limit` items khi còn data nhưng cũng trả đúng `limit` items ở page cuối nếu data chia hết. Code suy luận `hasMore` thay vì server trả field `hasMore`.

**Impact**: UI có thể hiển thị "Load more" khi thực tế không còn data, gây 1 request lỗi vô ích.

**Fix**: Mong server trả `hasMore` field. Nếu không, dùng convention `items.length > limit` (server trả `limit + 1`).

---

### 4.2 Data Correctness

#### ISSUE-004: `unreadCount` chỉ binary 0/1 [P1]

**File**: `conversation_model.dart:93`

```dart
unreadCount: (json['isRead'] as bool? ?? true) ? 0 : 1,
```

**Vấn đề**: `unreadCount` chỉ có 0 hoặc 1 dựa trên boolean `isRead`. Trong chat, unread count phải là số lượng tin nhắn thực (3 tin chưa đọc, 15 tin chưa đọc...).

**Impact**: UI không thể hiển thị badge số tin chưa đọc chính xác. Zalo/Messenger hiển thị "5" thay vì "●".

**Fix**: Server cần trả `unreadCount` integer thay vì boolean `isRead`. Entity `Conversation` đã có field `unreadCount` int, chỉ cần parse đúng.

---

#### ISSUE-005: Token ACS lưu trong Conversation entity [P2]

**File**: `conversation.dart:62-65`

```dart
final String? token;
final DateTime? tokenUtcExp;
final String? cui;
```

**Vấn đề**: `Conversation` entity chứa ACS access token (`token`), expiration (`tokenUtcExp`), và ACS user ID (`cui`). Đây là sensitive data không nên nằm trong domain entity — entity có thể bị serialize, log, hoặc leak qua debugging tools.

**Impact**: Bảo mật — token ACS có thể bị expose nếu entity được log hoặc serialize.

**Fix**: Di chuyển `token`/`tokenUtcExp`/`cui` ra khỏi `Conversation` entity. Dùng `AuthTokenRepository` để manage token riêng. Conversation chỉ chứa `roomId` và `threadId`.

---

#### ISSUE-006: `ChatAccessToken.isExpired` / `needsRefresh` dùng `DateTime.now()` trong entity [P2]

**File**: `chat_access_token.dart:22-28`

```dart
bool get isExpired => DateTime.now().isAfter(expiresOn);
bool get needsRefresh =>
    DateTime.now().isAfter(expiresOn.subtract(const Duration(minutes: 2)));
```

**Vấn đề**: Entity chứa logic thời gian với side effect (`DateTime.now()`). Entity nên là pure value object. Điều này làm:
- Không thể test time-dependent behavior.
- Entity không tái sử dụng được trong context có clock khác.

**Fix**: Di chuyển logic expiry check ra `AuthTokenRepositoryImpl`. Entity chỉ giữ data.

---

### 4.3 Code Hygiene / Dead Code

#### ISSUE-007: Polling engine trong `MessageRemoteDataSourceImpl` là code chết [P2]

**File**: `message_remote_datasource_impl.dart:29-30, 524-540`

```dart
final Map<String, PollingEngine<MessageModel>> _activePolling = {};
// ...
@override
Stream<Message> watchNewMessages(String roomId, String threadId) {
  final existing = _activePolling[threadId];
  if (existing != null) return existing.stream;
  final engine = PollingEngine<MessageModel>(...);
  _activePolling[threadId] = engine;
  engine.start();
  return engine.stream;
}
```

**Vấn đề**: `MessageRepositoryImpl.watchNewMessages` luôn dùng `_realtime` (WebSocket), không bao giờ gọi `_remote.watchNewMessages()` (polling). Code polling trong remote datasource hoàn toàn dead.

**Impact**: Codebase phức tạp hơn cần thiết. Developer mới confusion giữa WebSocket vs Polling paths.

**Fix**: Xóa `watchNewMessages`, `_activePolling` khỏi `MessageRemoteDataSourceImpl` và interface `MessageRemoteDataSource`. Giữ `PollingEngine` trong codebase nhưng chỉ dùng khi cần fallback.

---

#### ISSUE-008: Duplicate MIME type resolution [P3]

**Files**: `chat_core/lib/core/utils/mime_utils.dart` vs `conversation_remote_datasource_impl.dart:398-423`

**Vấn đề**: Hai nơi resolve MIME type với bảng khác nhau:
- `ChatMimeUtils`: 14 types (thiếu gif, webp)
- `ConversationRemoteDataSourceImpl._lookupMimeType`: 8 types (có gif, webp, thiếu heic/heif/doc/xls/ppt)

**Fix**: Dùng `ChatMimeUtils` ở mọi nơi, bỏ `_lookupMimeType` private.

---

#### ISSUE-009: `_eventIdCounter` là static mutable state toàn cục [P3]

**File**: `websocket_event_parser.dart:8-9`

```dart
static int _eventIdCounter = 0;
```

**Vấn đề**: Counter toàn cục, không reset, không thread-safe (trong Isolate context). Trong dài hạn, giá trị có thể overflow. Tuy nhiên trong practice, giá trị kết hợp với timestamp và random hex nên collision cực thấp.

**Fix**: Dùng UUID hoặc chỉ dùng `{timestamp}_{randomHex}` bỏ counter.

---

#### ISSUE-010: `MessageModel.fromAcsJson` deprecated nhưng vẫn được dùng [P3]

**File**: `message_model.dart:161-163` vs `message_remote_datasource_impl.dart:210`

```dart
@Deprecated('Dùng MessageModel.fromServerJson thay thế.')
factory MessageModel.fromAcsJson(...) => MessageModel.fromServerJson(...);

// Trong datasource — vẫn gọi deprecated:
final rawMessages = rawItems
    .map((e) => MessageModel.fromAcsJson(e, threadId: threadId))
    .toList();
```

**Fix**: Đổi sang `fromServerJson`, xóa `@Deprecated`.

---

#### ISSUE-011: `chat_user_utils.dart` export chính nó [P3]

**File**: `core/utils/chat_user_utils.dart:1`

```dart
export 'chat_user_utils.dart';  // Self-referential, vô nghĩa
```

**Fix**: Xóa dòng này.

---

### 4.4 Concurrency / Cache Issues

#### ISSUE-012: Cache write race condition [P2]

**Files**: `conversation_repository_impl.dart`, `message_repository_impl.dart`

```dart
// Pattern lặp lại ở nhiều nơi:
final cached = await local.getCachedConversations();
// ← await ở đây cho phép async operation khác chen vào
final merged = /* modify cached */;
await local.saveConversations(merged);
```

**Vấn đề**: Trong Flutter single isolate, true race condition hiếm xảy ra. Nhưng nếu hai async operations call cùng lúc (ví dụ: `listConversations` đang save + `getOrCreateDirectConversation` cũng save), operation thứ hai có thể đọc stale cache của operation thứ nhất.

**Impact**: Thấp trong Flutter (single isolate), nhưng cần lưu ý khi migrate isolates.

**Fix**: Cho MVP accept. Phase sau: thêm simple mutex/queue cho cache writes.

---

#### ISSUE-013: `leaveActiveRoom` không dọn room tracking maps [P2]

**File**: `websocket_realtime_datasource_impl.dart:327-345`

```dart
void leaveActiveRoom() {
  _isAppPaused = true;
  final roomsToLeave = {
    ..._activeRoomIds,
    ..._watchedRoomIds,
    ..._threadIdsByRoom.keys
  };
  // sends leave_room events...
  _lastVisibleMessageId = null;
  _activeRoomIds.clear();
  // ← _watchedRoomIds KHÔNG được clear
  // ← _threadIdsByRoom KHÔNG được clear
}
```

**Vấn đề**: `_activeRoomIds` được clear nhưng `_watchedRoomIds` và `_threadIdsByRoom` thì không. Khi user quay lại room và `watchNewMessages` được gọi lại, `_threadIdsByRoom` vẫn chứa mapping cũ + thêm mới, `_watchedRoomIds` cũng grow.

**Impact**: Memory leak nhẹ, và `_threadIdsByRoom` có thể chứa stale mapping room→thread.

**Fix**: Clear cả `_watchedRoomIds` và `_threadIdsByRoom` trong `leaveActiveRoom()`.

---

#### ISSUE-014: `_saveToCache` merge overwrite local state [P3]

**File**: `conversation_repository_impl.dart:76-85`

```dart
final byId = <String, Conversation>{
  for (final c in cached) c.id: c,
  for (final c in conversations) c.id: c,  // ← Overwrites cached version
};
```

**Vấn đề**: Server data luôn ghi đè cached data. Nếu user vừa ghim conversation (local cache update) nhưng chưa sync server, và `listConversations` chạy, server data sẽ overwrite pin state.

**Impact**: Thấp — vì `pinConversation` đã update cache + server cùng lúc, nhưng trong edge case (mạng chậm) có thể lose local state.

**Fix**: Merge thông minh hơn — giữ local fields (pin, isMuted, unreadCount) nếu server không trả giá trị mới.

---

## 5. Memory / Resource Issues

### Memory Leak Audit

| Component | Resource | Properly Disposed? | Risk |
|-----------|----------|-------------------|------|
| `WebSocketRealtimeDataSourceImpl` | `_channel` | ✅ `_closeSocket()` | None |
| `WebSocketRealtimeDataSourceImpl` | `_socketSubscription` | ✅ `_closeSocket()` | None |
| `WebSocketRealtimeDataSourceImpl` | `_heartbeatTimer` | ✅ `_closeSocket()` | None |
| `WebSocketRealtimeDataSourceImpl` | `_reconnectTimer` | ✅ `_closeSocket()` | None |
| `WebSocketEventDispatcher` | `_threadControllers` | ✅ `dispose()` | None |
| `WebSocketEventDispatcher` | `_listController` | ✅ `dispose()` | None |
| `MessageRemoteDataSourceImpl` | `_http` | ✅ `dispose()` | None |
| `MessageRemoteDataSourceImpl` | `_activePolling` | ✅ `dispose()` (but dead code) | None |
| `JsonApiClient` (in datasource constructors) | `_http` | ⚠️ Only if `dispose()` called | Low |
| `ConversationRepositoryImpl` | — | ⚠️ No `dispose()` method | None (no held resources) |

**Kết luận**: Không có memory leak nghiêm trọng. WebSocket lifecycle management tốt.

### Subscription Leak Audit

| Stream | Listener | Unsubscribed? |
|--------|----------|--------------|
| `channel.stream` | `_socketSubscription` | ✅ Cancel on close |
| `watchNewMessages` | Broadcast `StreamController` | ✅ Closed on `stopWatching` |
| `watchListMessages` | Broadcast `StreamController` | ✅ Closed on `stopWatchingList` |

---

## 6. Crash / Reliability Issues

### Potential Crashes

1. **`ChatAccessTokenModel.fromJson` — `json['token'] as String`** (line 13): Nếu server trả `token: null`, sẽ throw `TypeError`. Fix: `(json['token'] as String?) ?? ''`.

2. **`ConversationModel.fromRoomJson` — `json['roomId'] as String`** (line 111): Tương tự, không null-safe. Server trả `null` roomId sẽ crash.

3. **`ConversationModel.fromRoomJson` — `json['threadId'] as String`** (line 112): Same issue.

4. **`PinnedMessageModel._parseDate`**: Safely handled với fallback `DateTime.now()`. ✅

5. **`JsonApiClient._decodeOrThrow`**: Safely catches JSON decode errors. ✅

6. **`WebSocketEventParser.parseRoomEvent`**: Null-safe throughout. ✅

7. **`_mergeById` in `MessageRepositoryImpl._saveToCache`**: Using `Map` keyed by ID guarantees uniqueness. ✅

### Error Handling Assessment

- ✅ `JsonApiClient` maps HTTP errors → `ChatApiException` consistently.
- ✅ `AuthTokenRepositoryImpl._refresh` retries 3 times with 3s delay, skips retry for 401/403/404.
- ✅ `ConversationRepositoryImpl` and `MessageRepositoryImpl` fall back to cache on network errors.
- ⚠️ Cache errors silently swallowed (`catch (_) {}`) — acceptable for MVP but should add logging.

---

## 7. Realtime / WebSocket Issues

### WebSocket Implementation Quality: ⭐⭐⭐⭐ (4/5)

**Strengths:**
- ✅ Exponential backoff with jitter cho reconnect.
- ✅ Heartbeat monitoring — detect idle connection và reconnect.
- ✅ Auth error detection (close codes 1008, 4003, 4401, 4403 + string matching).
- ✅ `onSessionExpired` callback để host app xử lý.
- ✅ Message deduplication qua `WebSocketEventDispatcher`.
- ✅ Room enter/leave protocol đúng.
- ✅ Idle socket close khi không có active rooms.
- ✅ `_isAppPaused` flag prevents read sends in background.

**Issues:**

1. **`_startHeartbeat` gửi `lastVisibleMessageId` trong heartbeat message** (line ~175): Heartbeat nên chỉ có `{'type': 'heartbeat'}`. Nếu server không kỳ vọng `lastVisibleMessageId` trong heartbeat, nó có thể bị ignore hoặc gây lỗi.

2. **`watchNewMessages` reset `_lastVisibleMessageId = null` mỗi lần enter room** (line ~350): Mỗi lần user navigate vào thread, read state bị reset → gửi read message lại ngay cả khi đã đọc trước đó.

3. **`_handleSocketData` chỉ xử lý `type == 'room_event'`** — bỏ qua mọi event type khác (ví dụ: `message_updated`, `typing`). Nếu server gửi các event type mới, chúng bị silent drop.

---

## 8. UI Architecture

N/A — `chat_core` là domain + data layer, không chứa UI code.

**Đánh giá cho UI layer (chat_ui) dựa trên public API:**

- ✅ Entities (`Message`, `Conversation`, `ChatUser`) clean, dễ bind vào UI.
- ✅ Stream-based realtime (`watchNewMessages`, `watchListMessages`) phù hợp với Flutter's reactive model.
- ✅ `PaginatedResult<T>` generic hỗ trợ pagination UI.
- ⚠️ `MessageType` là string-based class (không phải enum) — UI cần switch trên `message.type.value` hoặc dùng `is` check, hơi verbose.

---

## 9. Public API Review

### Barrel Files

```dart
// chat_core.dart — PUBLIC (host app import)
// Entities, interfaces, use cases, config, error, utils

// chat_core_impl.dart — INTERNAL (Wiring/DI only)
// Models, datasource impls, repository impls
```

**Đánh giá:**

- ✅ Tách public/internal rõ ràng.
- ✅ Host app chỉ cần import `chat_core.dart` cho most use cases.
- ✅ Config class nullable/fallback-friendly — thêm option sau không breaking.

### Issues:

1. **`ChatModuleConfig` không có `copyWith`** — Host app muốn thay đổi 1 field phải tạo lại toàn bộ config. Thêm `copyWith` sẽ tiện hơn.

2. **`ChatAuthTokenProvider` interface quá đơn giản** — chỉ có `getAppToken()`. Host app không thể report token refresh failure, không thể inject refresh strategy.

3. **`MessageRepository.watchNewMessages` signature** — `Stream<Message> watchNewMessages(String roomId, String threadId)`. Host app phải truyền cả `roomId` AND `threadId` — redundant vì repository có thể lookup threadId từ roomId.

4. **Use cases là thin pass-throughs** — Mỗi use case chỉ gọi `_repository.method()` với params y hệt. Giá trị layering thấp cho simple CRUD. Acceptable cho library API consistency.

---

## 10. Performance Review

### Small Chat (1-1, <50 messages)
- ✅ Excellent. Cache-first load, WebSocket realtime, minimal API calls.
- ⚠️ `sendMessage` fetch ACS token mỗi lần → +100-300ms latency.

### Medium Chat (Group, 10-20 members, <500 messages)
- ✅ Good. WebSocket handles realtime well.
- ⚠️ `listMessages` không dùng `startTime` → fetch full 50 messages mỗi polling cycle.
- ⚠️ `unreadCount` binary → không progress bar loading.

### Large Chat (Group, 50+ members, 5000+ messages)
- ⚠️ `listMessages` page size cố định 50 → cần scroll nhiều.
- ⚠️ `ChatEventParser.parseRoomEvent` generates synthetic IDs với timestamp + counter + random → memory grow nếu conversation dài.
- ⚠️ `_recentMessageIdQueue` trong `WebSocketEventDispatcher` giới hạn 100 entries → nếu >100 messages arrive trong session, old IDs bị evict và duplicate có thể lọt qua.

---

## 11. Testability

### Current Test Coverage

| Area | Tests | Coverage |
|------|-------|----------|
| AuthTokenRepository | `auth_token_repository_test.dart` (66 LOC) | ✅ Cache, dedup, error |
| Conversation (Group) | `group_conversation_test.dart` (303 LOC) | ✅ CRUD, members, roles |
| Message Repository Cache | `message_repository_cache_test.dart` (293 LOC) | ✅ Cache-first, offline fallback |
| Message Entity | `message_test.dart` (54 LOC) | ✅ copyWith, equality |
| ChatUserUtils | `chat_user_utils_test.dart` (23 LOC) | ✅ normalize |
| ChatApiException | `chat_api_exception_test.dart` (29 LOC) | ✅ Parsing |
| WebSocket Dispatcher | `websocket_event_dispatcher_test.dart` (105 LOC) | ✅ Dedup, emit |
| WebSocket Parser | `websocket_event_parser_test.dart` (92 LOC) | ✅ Event types |
| SystemMessageText | `system_message_text_test.dart` (35 LOC) | ✅ Text generation |
| Conversation Remote DS | `conversation_remote_datasource_test.dart` (15 LOC) | ⚠️ Minimal |

### Missing Tests

| Priority | Test Case | Reason |
|----------|-----------|--------|
| P1 | `WebSocketRealtimeDataSourceImpl` lifecycle | Heartbeat, reconnect, session expired, idle close |
| P1 | `JsonApiClient` HTTP methods + error mapping | Core networking |
| P1 | `ConversationRemoteDataSourceImpl` SAS upload flow | Complex multi-step upload |
| P2 | `MessageRemoteDataSourceImpl.listMessages` pagination | RoomUpdated enrichment logic |
| P2 | `MessageRemoteDataSourceImpl.sendMessage` (no ACS token call) | After ISSUE-001 fix |
| P2 | `PollingEngine` backoff + interval | Exponential backoff correctness |
| P2 | `ConversationRepositoryImpl` cache merge | Race condition, merge logic |
| P3 | `MessageType.fromString` edge cases | Unknown types, backward compat |
| P3 | `ChatMimeUtils.lookupMimeType` | All 14 types |

### Testability Assessment

- ✅ All datasources depend on abstractions (interfaces), easy to mock.
- ✅ `JsonApiClient` accepts `http.Client?` — injectable for testing.
- ✅ Repository constructors accept optional local datasources — easy to test without cache.
- ⚠️ `ChatAccessToken.isExpired` uses `DateTime.now()` — can't test time-dependent behavior.
- ⚠️ `WebSocketRealtimeDataSourceImpl` depends on `WebSocketChannel` — needs mock/fake for unit test.

---

## 12. Refactoring Priority

| Priority | Issue | File | Impact | Effort | Recommendation |
|----------|-------|------|--------|--------|----------------|
| P1 | `sendMessage` fetches ACS token unnecessarily | `message_remote_datasource_impl.dart` | Perf (+100-300ms per send) | Low | Remove `_authTokenRepository.getAccessToken()` call |
| P1 | `listMessages` ignores `startTime` param | `message_remote_datasource_impl.dart` | Network waste | Low | Add `startTime` to query params |
| P1 | `unreadCount` is binary 0/1 | `conversation_model.dart` | Data incorrectness | Medium | Server must return `unreadCount` int |
| P2 | Dead polling code | `message_remote_datasource_impl.dart` | Code complexity | Low | Remove `_activePolling` and polling methods |
| P2 | Token stored in Conversation entity | `conversation.dart` | Security | Medium | Move token to AuthTokenRepository scope |
| P2 | `isExpired`/`needsRefresh` in entity | `chat_access_token.dart` | Testability | Low | Move to repository |
| P2 | `leaveActiveRoom` doesn't clear room maps | `websocket_realtime_datasource_impl.dart` | Memory + stale state | Low | Clear `_watchedRoomIds` and `_threadIdsByRoom` |
| P2 | Duplicate MIME type resolution | `mime_utils.dart` + `conversation_remote_datasource_impl.dart` | Consistency | Low | Use `ChatMimeUtils` everywhere |
| P2 | `listConversations` infers hasMore | `conversation_remote_datasource_impl.dart` | Pagination accuracy | Medium | Server should return explicit hasMore |
| P2 | Cache merge race condition | `conversation_repository_impl.dart` | Theoretical data loss | Medium | Add simple mutex (Phase 2+) |
| P3 | `fromAcsJson` deprecated but used | `message_model.dart` | Code hygiene | Low | Migrate to `fromServerJson` |
| P3 | Self-referential export | `chat_user_utils.dart` | Noise | Trivial | Delete |
| P3 | `_eventIdCounter` global mutable | `websocket_event_parser.dart` | Overflow risk | Low | Use UUID or drop counter |

---

## 13. Target Architecture

```
Current Architecture                    Target Architecture
─────────────────                       ──────────────────

MessageRemoteDataSourceImpl (727 LOC)   MessageCRUDDataSource (200 LOC)
  ├── sendMessage                         ├── sendMessage
  ├── listMessages                        ├── listMessages
  ├── updateMessage                       ├── updateMessage
  ├── deleteMessage                       ├── deleteMessage
  ├── pinMessage                          └── pinMessage
  ├── getPinnedMessages
  ├── getMessageReaders                  PinnedMessageDataSource (100 LOC)
  ├── getMessageResources                  ├── getPinnedMessages
  ├── getReactionConfigs                   └── ...
  ├── getMessageReactions
  ├── getRoomReactions                    ReactionDataSource (120 LOC)
  ├── reactMessage                         ├── getReactionConfigs
  ├── watchNewMessages (DEAD)             ├── getMessageReactions
  └── stopWatching (DEAD)                 ├── getRoomReactions
                                           └── reactMessage

ConversationRepositoryImpl (295 LOC)    ConversationRepositoryImpl (150 LOC)
  ├── conversation CRUD                    ├── conversation CRUD
  ├── member management                    └── pin
  ├── room info management
  ├── role management                     MemberManagementRepository (100 LOC)
  ├── ownership transfer                   ├── add/remove participants
  ├── file upload                          ├── setRoleAdmin
  └── pin                                  └── transferOwnership

                                        FileUploadService (80 LOC)
                                          ├── uploadRoomAvatar
                                          └── uploadFileViaSas

ConversationEntity                      ConversationEntity
  ├── id, threadId, ...                    ├── id, threadId, ...
  ├── token, tokenUtcExp, cui (REMOVE)     └── (no token fields)

ChatAccessTokenEntity                   ChatAccessTokenEntity
  ├── isExpired, needsRefresh (REMOVE)     └── pure data only
```

### Key Changes

1. **Tách `MessageRemoteDataSource` thành 3 datasources** focused hơn.
2. **Tách member management** ra khỏi `ConversationRepository`.
3. **Tách file upload** thành service riêng.
4. **Remove token fields** từ Conversation entity.
5. **Move time logic** ra khỏi `ChatAccessToken` entity.
6. **Remove dead polling code** từ message datasource.

---

## 14. Migration Plan

### Phase 1 – Critical Fixes (1-2 ngày)

1. **ISSUE-001**: Xóa `_authTokenRepository.getAccessToken()` trong `sendMessage`.
2. **ISSUE-002**: Thêm `startTime` vào query params trong `listMessages`.
3. **ISSUE-013**: Clear `_watchedRoomIds` + `_threadIdsByRoom` trong `leaveActiveRoom`.
4. **ISSUE-004**: Server-side fix: trả `unreadCount` int thay vì `isRead` boolean.
5. **ISSUE-010**: Đổi `fromAcsJson` → `fromServerJson` trong datasource.

### Phase 2 – Architecture Cleanup (3-5 ngày)

1. **ISSUE-007**: Xóa dead polling code (`_activePolling`, `watchNewMessages`, `stopWatching` trên remote datasource).
2. **ISSUE-005**: Di chuyển `token`/`tokenUtcExp`/`cui` ra khỏi `Conversation` entity.
3. **ISSUE-006**: Di chuyển `isExpired`/`needsRefresh` ra khỏi entity.
4. **ISSUE-008**: Merge duplicate MIME tables → dùng `ChatMimeUtils` mọi nơi.
5. **Tách `ConversationRepository`**: Member management → `MemberRepository`, file upload → `FileUploadService`.

### Phase 3 – Testing (2-3 ngày)

1. Viết tests cho `WebSocketRealtimeDataSourceImpl` lifecycle.
2. Viết tests cho `JsonApiClient` HTTP error mapping.
3. Viết tests cho SAS upload flow.
4. Viết tests cho `PollingEngine` backoff behavior.
5. Bổ sung test cho pagination logic.

### Phase 4 – API Stabilization (1-2 ngày)

1. Review tất cả public interfaces trong `chat_core.dart`.
2. Đánh dấu deprecated APIs.
3. Thêm `@immutable` annotations cho entities.
4. Review error types và ensure consistency.
5. Document `ChatModuleConfig` options.

---

## 15. Production Readiness Verdict

### 🟡 READY WITH MINOR FIXES

**Must Fix Before Release:**
1. **ISSUE-001**: Remove unnecessary ACS token fetch in `sendMessage` — mỗi message gửi đều bị +100-300ms latency không cần thiết.
2. **ISSUE-002**: Implement `startTime` in `listMessages` query params — pagination hiện tại fetch toàn bộ 50 messages mỗi lần.
3. **ISSUE-004**: Server cần trả `unreadCount` integer — UI không thể hiển thị badge số tin chưa đọc.
4. **ISSUE-013**: Fix `leaveActiveRoom` không clear room maps — room tracking grow vô hạn.

**Should Fix:**
1. **ISSUE-005**: Di chuyển tokenACS ra khỏi Conversation entity (security).
2. **ISSUE-006**: Di chuyển time logic ra khỏi ChatAccessToken entity (testability).
3. **ISSUE-007**: Xóa dead polling code (code hygiene).
4. **ISSUE-008**: Unify MIME type resolution (consistency).
5. Viết tests cho WebSocket lifecycle và JsonApiClient.

**Nice to Have:**
1. Tách ConversationRepository thành smaller focused repositories.
2. Thêm `copyWith` cho ChatModuleConfig.
3. Tách MessageRemoteDataSource thành focused datasources.
4. Viết tests cho SAS upload flow.
5. Loại bỏ deprecated `fromAcsJson`.
6. Fix `_eventIdCounter` global mutable state.

---

*Review completed: 2026-08-24*
*Package: `chat_core` v0.1.0*
*Total source files: 85 | Total test files: 10 | LOC (source): ~3,500 | LOC (tests): ~1,000*
