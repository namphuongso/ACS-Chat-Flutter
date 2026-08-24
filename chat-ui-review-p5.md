# Chat UI Code Review – P5

## 1. Executive Summary

| Tiêu chí | Điểm | Nhận xét |
|---|---|---|
| Architecture | 6/10 | Feature-first tốt, nhưng Notifier quá lớn, trộn nhiều concern |
| Maintainability | 4/10 | ThreadScreen 2284 dòng, Notifier 1302 dòng — rất khó maintain |
| Readability | 5/10 | Code Dart sạch, comment tiếng Việt rõ, nhưng file dài gây khó đọc |
| Performance | 6/10 | ListView.builder + ScrollablePositionedList tốt; rebuild chưa tối ưu |
| API Efficiency | 5/10 | Thiếu dedup cho getMembers, refreshHistory; link preview fetch mỗi lần gửi |
| Memory Safety | 6/10 | Subscription cancel đúng; avatar cache không clear; static cache không TTL |
| Crash Safety | 6/10 | Null safety tốt; catch (_) {} 44+ chỗ làm lỗi bị nuốt |
| Testability | 3/10 | Chỉ 5 test files đơn giản; không test realtime/pagination/lifecycle |
| Extensibility | 7/10 | ChatUiConfig linh hoạt; MessageBubble/Input có callback tùy biến |
| UI Customizability | 6/10 | Màu sắc custom được; builder-level customization chưa có |
| Public API Design | 6/10 | Expose quá nhiều internal providers; thiếu abstraction layer |
| Production Readiness | 5/10 | MVP dùng được nội bộ nhưng chưa đủ publish public |

## 2. Architecture Assessment

### Điểm mạnh (KEEP)

- **Feature-first structure** (`features/thread`, `features/conversation_list`, `features/contact`, `features/shared`) giúp định vị code nhanh.
- **Riverpod provider tree** phân tầng rõ: config → datasource → repository → usecase → notifier → screen.
- **`ProviderScope` per-screen** với override `roomIdProvider` / `threadIdProvider` đảm bảo scope đúng từng room.
- **Hive local caching** cho messages/conversations hỗ trợ offline và hiển thị tức thì.
- **ChatCore abstraction**: `chat_ui` chỉ phụ thuộc interfaces từ `chat_core`, không phụ thuộc trực tiếp ACS SDK — đúng hướng.
- **Optimistic send** với rollback khi fail.
- **`ChatUiConfig`** cho phép host app override toàn bộ màu sắc mà không phải sửa source.

### Điểm yếu

#### A. God Class — `ThreadMessagesNotifier` (1302 dòng)

Class này đang làm quá nhiều việc:

- Load history + pagination
- Realtime message handling
- System message building/formatting (duplicate logic giữa `_handleMemberEventSignal` và `_enrichSystemMessageContent`)
- Reaction management
- Pin/unpin management
- Media upload orchestration
- Identity resolution (myAcsUserId)
- Avatar cache management
- Link preview fetching
- Read receipt sending

Đây là architectural smell rõ ràng nhất của package.

#### B. God Widget — `ThreadScreen` (2284 dòng)

Một StatefulWidget duy nhất chứa:
- AppBar với search bar inline
- Pinned message banner
- Message list rendering
- Search logic (debounce, deep pagination scan)
- Message action dialogs (reaction picker, edit, delete, pin, readers)
- Lifecycle handling (WidgetsBindingObserver + RouteAware)
- Navigation (room settings, member screens)

Cần tách thành ít nhất 5-6 widget/controller nhỏ hơn.

#### C. Duplicate system-message formatting logic

`_handleMemberEventSignal()` (~250 dòng) và `_enrichSystemMessageContent()` (~150 dòng) đều parse metadata → build content qua `SystemMessageTextBuilder.build()`. Hai method này xử lý cùng eventType nhưng với fallback chain khác nhau → dễ lệch logic khi sửa một nơi.

---

## 3. Critical Issues

### Issue 1: Errors bị nuốt im lặng — `catch (_) {}`

```
Issue:     Exception không được log, không propagate lên caller
File:      Nhiều file (thread_messages_notifier.dart, conversation_list_notifier.dart, v.v.)
Severity:  P0 – Critical
Category:  Error handling / Observability
```

**Current behavior:** Có ít nhất **44 chỗ** dùng `catch (_) {}` hoặc `catch (e) {}` không log trong `lib/`.

**Problem:** Khi production có lỗi (network timeout, token expired, parse error), developer hoàn toàn không biết lỗi xảy ra ở đâu. Không có cách nào debug.

**Why dangerous:** Trong chat SDK production, silent failure dẫn tới:
- Tin nhắn "biến mất" không ai biết tại sao
- Reaction không cập nhật mà không có error
- Pagination dừng đột ngột không rõ nguyên nhân
- Token refresh fail mà app vẫn nghĩ là đã login

**Reproduction:** Mở thread khi backend trả 500 → `_fetchMembersIfNeeded()` catch (_) → members trống, không có error nào hiển thị hay log.

**Recommended solution:** Thay tất cả `catch (_)` bằng:
```dart
} catch (e, st) {
  ChatLogger.error('context-description', error: e, stackTrace: st);
  // Optionally rethrow or set error state
}
```

---

### Issue 2: Race condition trong `_loadHistory()`

```
Issue:     Multiple async operations có thể interleave khi refreshHistory() được gọi đồng thời
File:      lib/features/thread/presentation/notifiers/thread_messages_notifier.dart
Class:     ThreadMessagesNotifier
Method:    _loadHistory()
Severity:  P0 – Critical
Category:  Race condition / State inconsistency
```

**Current behavior:** `_loadHistory()` gồm các bước tuần tự:
1. `getMyAcsUserId()` (async, Hive disk read)
2. `getAccessToken(roomId)` (async, network call join-room)
3. `_listMessagesUseCase()` (async, network call ACS REST)

Không có guard chống gọi đồng thời. Khi connectivity thay đổi (offline → online), `refreshHistory()` được gọi. Nếu user cũng vừa mở thread, hai instance `_loadHistory()` chạy song song → state.messages bị ghi đè lẫn nhau.

**Scenario:**
```
T=0ms   User mở room → _loadHistory() #1 bắt đầu
T=100ms Network recovery event → refreshHistory() → _loadHistory() #2 bắt đầu
T=500ms #1 xong getAccessToken, set myAcsUserId
T=600ms #2 xong getAccessToken, set myAcsUserId (duplicate)
T=800ms #1 xong listMessages, state = messages_1
T=900ms #2 xong listMessages, state = messages_2 ← GHI ĐÈ kết quả #1
```

**Impact:** Cursor có thể bị sai, tin nhắn bị duplicate hoặc missing.

**Fix:**
```dart
Future<void> _loadHistory() async {
  if (_isLoadingHistory) return;
  _isLoadingHistory = true;
  try { ... } finally { _isLoadingHistory = false; }
}
```

---

### Issue 3: `sendMessage()` optimistic dedup theo content — match sai

```
Issue:     Optimistic message matching theo content có thể match nhầm
File:      lib/features/thread/presentation/notifiers/thread_messages_notifier.dart
Method:    sendMessage(), realtime listener trong build()
Severity:  P1 – High
Category:  Data consistency
```

**Current behavior:** Khi nhận echo realtime từ chính tin mình gửi, code tìm pending message bằng:
```dart
final pending = _messages.where((m) =>
    m.status == MessageDeliveryStatus.sending &&
    m.content == message.content).firstOrNull;
```

Nếu user copy-paste cùng 1 nội dung 5 lần nhanh chóng, 5 optimistic messages có cùng content. Echo có thể về theo thứ tự khác với thứ tự gửi → mapping sai id → UI hiện tin nhắn lặp hoặc mất.

**Recommended solution:** Thêm unique client-generated ID vào metadata của optimistic message để match echo chính xác:
```dart
final clientId = 'local-${uuid.v4()}';
// metadata: {'clientMsgId': clientId}
// Match echo bằng metadata['clientMsgId']
```

---

### Issue 4: Không có request deduplication cho `getMembers`

```
Issue:     getMembers() được gọi mỗi lần mở thread, không có cache/dedup
File:      lib/features/thread/presentation/notifiers/thread_messages_notifier.dart
Method:    _fetchMembersIfNeeded()
Severity:  P1 – High
Category:  API efficiency
```

**Current behavior:** Mỗi lần build() → Future.microtask → `_fetchMembersIfNeeded()` → HTTP GET `/rooms/{roomId}/members`. Nếu user back ra rồi vào lại room, API được gọi lại dù participants chưa đổi.

**Impact:** Với 20 rooms, user switch nhanh → 20 API calls trong 30 giây cho data gần như không đổi.

**Recommended solution:** Cache members trong `ConversationListNotifier.state[roomId].participants`. Chỉ fetch lại khi nhận `MemberJoined/Left/Removed` realtime event.

---

## 4. API Efficiency Issues

| Operation | Current Call | Trigger | Dư thừa? | Cache? | Dedup? | Risk |
|---|---|---|---|---|---|---|
| Load conversations | GET /conversations | Screen init + didPopNext | Yes khi pop next nếu realtime đã cập nhật | Hive local | No | Medium |
| Load messages page 1 | ACS listMessages | Thread open | No | Hive local (read-only) | No guard | Low |
| Join-room/token | POST /join-room | Thread open | Yes nếu identity đã cached | RAM (AuthTokenRepository) | Single-flight trong repo | Low |
| GetMembers | GET /rooms/{id}/members | Thread open | **Yes** — mỗi lần mở room | ConversationListNotifier | **No** | High |
| Send text message | POST /send-message | User tap send | No | N/A | N/A | Low |
| Link preview | HTTP GET external URL | Mỗi lần sendMessage chứa URL | **Yes** nếu URL đã preview trước đó | Static Map (max 100) | Per-URL | Low |
| Reactions summary | GET /reactions?roomId | Thread open + mỗi react | Yes nếu reactions không đổi | ThreadReactionsService._configs (chỉ configs) | No | Medium |
| Pinned messages | GET /pinned?roomId | Sau load history + sau delete | Acceptable | State.pinnedMessages | No | Low |
| Read receipt | WebSocket read | Mỗi tin mới hiển thị | **Yes** — fire cho mọi tin, không throttle | N/A | No | Medium |

---

## 5. Memory / Resource Issues

### 5.1 `_userAvatarCache` không clear khi dispose

```
File:   thread_messages_notifier.dart
Field:  final Map<String, String> _userAvatarCache = {};
Risk:   P2 – Medium
```

Cache này sống cùng Notifier. Riverpod auto-dispose Notifier khi rời màn hình → GC sẽ collect. Tuy nhiên nếu `keepAlive` được bật (hoặc notifier giữ lâu), cache tích lũy vô hạn avatar URL string (nhẹ, không crash nhưng leak memory).

**Recommendation:** Clear trong `ref.onDispose()`.

### 5.2 `LinkPreviewFetcher._cache` static, FIFO eviction

```
File:   core/utils/link_preview_fetcher.dart
Field:  static final _cache = <String, LinkPreviewData>{};
Risk:   P2 – Medium
```

Static cache sống suốt app lifecycle. Max 100 entries, evict FIFO. Không có TTL → stale previews có thể hiển thị mãi.

**Recommendation:** Dùng LRU cache hoặc thêm TTL (vd 24h).

### 5.3 `_realtimeSub` cancel đúng nhưng `stopWatchingUseCase` fire-and-forget

```dart
ref.onDispose(() {
  unawaited(_realtimeSub?.cancel());
  unawaited(stopWatchingUseCase(threadId));
});
```

Nếu `stopWatchingUseCase` throw, exception bị swallow bởi `unawaited`. Nên thêm `.catchError(...)`.

---

## 6. Crash / Reliability Issues

### 6.1 `_chronological()` sort theo `DateTime` — timestamp trùng nhau

```
File:      thread_messages_notifier.dart
Method:    _chronological()
Severity:  P2 – Medium
```

Nếu 2 tin nhắn có cùng `createdAt` (millisecond precision), sort không ổn định (Dart's `sort` is not stable). Kết quả: thứ tự tin nhắn có thể đảo ngược giữa các lần render.

**Recommendation:** Thêm secondary sort key (id hoặc sequence number).

### 6.2 `loadUntilMessage` polling loop có thể spin vô hạn

```dart
while (attempts < maxAttempts && DateTime.now().isBefore(timeout)) {
  if (state.isLoadingOlder) {
    await Future.delayed(300ms);
    if (_messages.any(...)) return true;
    continue; // attempts không tăng → loop tiếp tục
  }
  ...
}
```

Nếu `isLoadingOlder` luôn true (do scroll listener liên tục trigger), loop này có thể chờ 10 giây mà không tăng attempts → vẫn thoát do timeout, nhưng waste CPU.

---

## 7. Realtime / ACS Issues

### 7.1 REST response ghi đè realtime messages

```
File:      thread_messages_notifier.dart
Method:    _loadHistory()
Severity:  P1 – High
```

Flow: realtime nhận message X → append vào state. Sau đó `_loadHistory()` hoàn tất → `state = state.copyWith(messages: mergedItems)` trong đó `mergedItems` chỉ gồm remoteItems từ REST + localExtras. Nếu X chưa có trong REST response (race), X bị **mất khỏi state**.

Code có check `localExtras` nhưng chỉ giữ lại messages không có trong `remoteIds`. Message X (realtime-only) sẽ nằm trong `localExtras` → được giữ. Tuy nhiên nếu X là system message có content khớp với 1 system message trong remote → bị loại do dedup logic.

**Recommendation:** Merge theo ID thay vì replace toàn bộ list.

### 7.2 Realtime subscription không re-subscribe khi roomId đổi

`ThreadMessagesNotifier.build()` watch `roomIdProvider`. Nếu roomId đổi (switch room), Notifier rebuild → subscription cũ cancel, subscription mới tạo. Điều này hoạt động NHƯNG `stopWatchingUseCase(threadId)` được gọi async — có thể race với việc tạo subscription mới cho room khác nếu cả hai dùng chung WebSocket connection ở repo layer.

---

## 8. UI Architecture

### Điểm mạnh
- `ScrollablePositionedList` cho jump-to-index (search result, pinned message).
- Skeleton loading states.
- Offline banner.
- Empty state.
- Pull-to-refresh trên danh sách.

### Điểm yếu

#### ThreadScreen quá lớn

2284 dòng trong 1 file. Cần tách:

```
thread_screen.dart (~200 dòng)
├── thread_app_bar.dart (~200 dòng) — title, search toggle
├── thread_search_bar.dart (~150 dòng) — search input + navigation
├── pinned_message_banner.dart (~80 dòng)
├── thread_message_list.dart (~300 dòng) — list rendering + scroll
├── thread_message_actions.dart (~400 dòng) — reaction/edit/delete dialogs
└── thread_lifecycle_handler.dart (~100 dòng) — RouteAware + AppLifecycle
```

#### Hardcoded Vietnamese strings

Tất cả UI strings ("Chưa có tin nhắn", "Phòng chat đã bị giải tán", v.v.) hardcode tiếng Việt. SDK public cần i18n/l10n support.

#### Không có builder callbacks

Consumer muốn customize message bubble, input bar, appBar... phải copy toàn bộ ThreadScreen. Thiếu:

```dart
ChatView(
  messageIdBuilder: (context, message, child) => ...,
  inputBarBuilder: (context, controller) => ...,
  appBarBuilder: (context, room) => ...,
)
```

Hiện tại chỉ customize được màu sắc qua `ChatUiConfig`.

---

## 9. Public API Review

### Exported surface (`chat_ui.dart`)

Export quá rộng:
- Tất cả screens (ThreadScreen, RoomSettingsScreen, RoomMembersScreen, ContactListScreen...)
- Tất cả notifiers/providers (threadMessagesProvider, conversationListProvider, authTokenRepositoryProvider...)
- Widgets nội bộ (MessageBubble, MessageInput...)

**Vấn đề:** Consumer có thể import `authTokenRepositoryProvider` và gọi trực tiếp repository → bypass use case layer → coupling cao, khó breaking change sau này.

**Recommendation:** Chỉ export những gì consumer thực sự cần:
```dart
// Public API
export 'core/chat_navigator.dart';
export 'core/chat_ui_config.dart';
export 'features/conversation_list/presentation/screens/conversation_list_screen.dart';
export 'features/thread/presentation/screens/thread_screen.dart';

// Internal (không export)
// - Providers chi tiết
// - Repository implementations
// - Local data sources
```

### ACS Implementation Leak

✅ **KEEP:** Package không expose bất kỳ class ACS trực tiếp. Models (`Message`, `Conversation`, `ChatUser`) đều là domain models từ `chat_core`. Consumer không cần biết underlying là ACS.

⚠️ **Lưu ý:** `myAcsUserId` field trong `ThreadState` leak concept "ACS user ID" ra public state. Consumer chỉ cần biết "senderId của tôi". Nên rename thành `mySenderId` hoặc encapsulate.

---

## 10. Performance Review

### Small chat (< 50 messages)
✅ OK — không vấn đề đáng kể.

### Medium chat (100–1000 messages)
- `visibleMessages` computed trong `build()` mỗi lần rebuild → filter toàn bộ list. Với 1000 messages, filter 8 loại MessageType + empty check mỗi frame → O(n) mỗi build.
- **Recommendation:** Memoize `visibleMessages` bằng `select()` hoặc compute riêng trong Notifier.

### Large chat (> 1000 messages)
- `ScrollablePositionedList.builder` tốt cho lazy loading.
- `_isCurrentUserCurrentlyRemoved()` iterate `messages.reversed` mỗi lần state change → O(n) mỗi update.
- Search deep scan gọi `loadOlder()` tối đa 4 pages × 50 items/page = 200 messages → OK nhưng block UI thread khi filter.

---

## 11. Testability

### Hiện trạng

| File | Lines | Tests |
|---|---|---|
| thread_messages_notifier.dart | 1302 | **0 tests** |
| thread_screen.dart | 2284 | **0 tests** |
| conversation_list_notifier.dart | 336 | **0 tests** |
| message_bubble.dart | 377 | 0 tests |
| message_input.dart | 880 | 0 tests |
| ChatDeepLinkData | ~70 | 5 tests ✅ |
| LastMessagePreview | ~60 | 4 tests ✅ |
| ImageDimensionUtils | ~80 | 2 tests ✅ |
| RichMessageText | ~100 | 1 test ✅ |
| ThreadState | ~60 | 2 tests ✅ |

**Coverage ước tính: < 5%** đối với business logic.

### Test cases còn thiếu (ưu tiên cao)

1. **Pagination**: Load page 1 → loadOlder → verify ordering + no duplicates + cursor update.
2. **Realtime + pagination conflict**: Receive new msg via realtime → loadOlder → verify new msg không bị mất.
3. **Send message success/fail**: Optimistic appear → success (replace with real) / fail (mark failed).
4. **Lifecycle**: Open thread → dispose → verify subscriptions cancelled + stopWatching called.
5. **Token expired**: getAccessToken throws → verify fallback to cache + historyLoaded set.
6. **System message dedup**: Same system message via realtime + REST → only 1 in state.
7. **Read receipt throttling**: Multiple new messages → sendReadMessage called once for last.

---

# 31. Refactoring Priority

| Priority | Issue | File | Impact | Effort | Recommendation |
|---|---|---|---|---|---|
| P0 | Silent error swallowing (44+) | Multiple files | Critical | Low | Replace all `catch(_)` with logged catch |
| P0 | Race condition `_loadHistory` | thread_messages_notifier.dart | Critical | Low | Add `_isLoadingHistory` guard |
| P1 | God class ThreadMessagesNotifier | thread_messages_notifier.dart | High | Medium | Split into MessageLoader + RealtimeHandler + SystemMessageFormatter |
| P1 | God widget ThreadScreen | thread_screen.dart | High | Medium | Split into 5-6 sub-widgets |
| P1 | getMembers no dedup/cache | thread_messages_notifier.dart | High | Low | Cache in ConversationListNotifier |
| P1 | Optimistic dedup by content | thread_messages_notifier.dart | High | Low | Use client-generated unique ID |
| P2 | visibleMessages O(n) per build | thread_screen.dart | Medium | Low | Compute in notifier or memoize |
| P2 | No UI builder callbacks | chat_ui.dart | Medium | Medium | Add builder params to ThreadScreen |
| P2 | Hardcoded Vietnamese strings | All widgets | Medium | Low | Add localization support |
| P2 | Static LinkPreview cache no TTL | link_preview_fetcher.dart | Medium | Low | Add TTL or use LRU |

---

# 32. Recommended Target Architecture

```
Current                          Target
─────────                        ──────
ThreadScreen (2284 lines)        ThreadScreen (~200)
                                 ├── ThreadAppBar
                                 ├── ThreadSearchBar
                                 ├── PinnedBanner
                                 ├── MessageListWidget
                                 └── ThreadActionHandler

ThreadMessagesNotifier (1302)    ThreadMessagesNotifier (~300, state only)
                                 ├── ThreadHistoryService (load, paginate, cache)
                                 ├── ThreadRealtimeService (subscription, dispatch)
                                 ├── SystemMessageFormatter (pure function)
                                 └── ThreadIdentityService (acsUserId resolution)

Direct export all                Public facade + internal barrel
```

---

# 33. Migration Plan

### Phase 1 – Critical Fixes (1–2 days)
1. Replace all `catch (_)` with logged catches.
2. Add `_isLoadingHistory` guard to `_loadHistory()`.
3. Add client-generated unique ID for optimistic message matching.

### Phase 2 – Architecture (3–5 days)
4. Extract `SystemMessageFormatter` as pure utility.
5. Split `ThreadMessagesNotifier`: move history/pagination logic into service.
6. Add members cache to `ConversationListNotifier`.
7. Restrict public exports in `chat_ui.dart`.

### Phase 3 – UI (3–5 days)
8. Split `ThreadScreen` into sub-widgets.
9. Add builder customization parameters.
10. Extract hardcoded strings to constants/localization.

### Phase 4 – Testing (ongoing)
11. Unit tests for pagination + realtime merge logic.
12. Widget tests for message bubble rendering variants.
13. Integration test for open→close→reopen lifecycle.

---

# Production Readiness Verdict

**⚠️ READY WITH MAJOR FIXES**

Package chạy được cho MVP nội bộ nhưng chưa đủ an toàn để publish cho nhiều app bên ngoài.

**Must Fix Before Release:**
1. Replace 44+ silent `catch (_) {}` với logged error handling.
2. Fix race condition trong `_loadHistory()` (add mutex/guard).
3. Fix optimistic message dedup (dùng unique client ID thay vì content match).

**Should Fix:**
1. Split `ThreadMessagesNotifier` (1302 dòng) và `ThreadScreen` (2284 dòng).
2. Thêm cache/dedup cho `getMembers()`.
3. Giới hạn public exports — chỉ export những gì consumer cần.
4. Thêm unit tests cho pagination, realtime merge, và lifecycle.

**Nice to Have:**
1. Builder callbacks cho UI customization.
2. Localization support thay vì hardcoded Vietnamese.
3. LRU/TTL cache cho link previews.
4. Rename `myAcsUserId` → `mySenderId` trong public state.
