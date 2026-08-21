# Chat Library Code Review — Overview (ACS-Chat-Flutter)

> Ngày review: 2026-08-21
> Phạm vi: **review tổng quan cấp project/architecture** toàn bộ `chat-module-mvp/`
> (chat_core ~6.200 LOC, chat_ui ~14.600 LOC, chat_native_platform_interface ~270 LOC native,
> tổng ~20.900 dòng Dart).
> Tiêu chí: `review/prompt.md` (Senior Flutter Architect / SDK Engineer).
> Review chi tiết từng package: `review/chat-core-review.md`, `review/chat-ui-review.md`,
> `review/chat-native-review.md`.
> Ghi chú: `flutter analyze`/`flutter test` không chạy được trong môi trường review này
> (sandbox hạn chế ghi vào Flutter cache) — kết luận dựa trên đọc source trực tiếp.

## 3. Critical Issues (P0/P1)

> Format theo prompt §29. Các issue P2/P3 đầy đủ hơn nằm trong `issue.md` và review từng package.

### P0-1 — Realtime "chết" sau background → foreground (Scenario 3 của prompt)

```text
Issue: Mất realtime cho thread đang mở sau khi app background rồi foreground
File: packages/chat_ui/lib/features/thread/presentation/screens/thread_screen.dart (didChangeAppLifecycleState :493)
      + packages/chat_core/lib/features/thread/data/datasources/native_realtime_datasource_impl.dart (leaveActiveRoom, watchNewMessages)
Class/Method: _ThreadScreenContentState.didChangeAppLifecycleState / NativeRealtimeDataSourceImpl.leaveActiveRoom
Severity: P0  Category: Lifecycle/Realtime

Current behavior:
 - paused/inactive/detached → screen gọi repo.leaveActiveRoom() → datasource gửi leave_room
   và XÓA SẠCH _activeRoomIds + reset _lastVisibleMessageId.
 - resumed → chỉ gọi sendReadMessageIfNeeded(); KHÔNG gọi lại watchNewMessages/enter_room.

Problem:
 Nếu socket bị OS ngắt khi background (rất phổ biến trên iOS), lúc foreground:
 _handleDisconnected → _scheduleReconnect → reconnect thành công → vòng lặp
 "for (final roomId in _activeRoomIds) enter_room" chạy trên tập RỖNG
 (đã bị clear lúc pause) → không enter_room nào được gửi → thread đang mở
 không còn nhận event cho tới khi user back ra và mở lại room.

Why dangerous: Lỗi im lặng (không crash), user đang chat thì realtime ngừng hoạt động.
Reproduction: Mở room → khóa màn hình 30–60s (đủ để OS giết socket) → mở lại → nhờ người khác gửi tin → tin không hiện realtime.
Recommended solution:
 - leaveActiveRoom chỉ gửi leave_room + giữ nguyên _activeRoomIds (hoặc lưu riêng _enteredRoomIds);
 - on resumed: nếu socket còn sống thì re-enter, nếu không reconnect sẽ tự re-enter từ _activeRoomIds;
 - Thêm test lifecycle (pause/resume) cho datasource.
```

### P0-2 — Conversation list: reaction event realtime làm sai unread count + hỏng preview

```text
Issue: _onNewMessage không lọc MessageType.reactionUpdate trước khi cập nhật lastMessage/unreadCount
File: packages/chat_ui/lib/features/conversation_list/presentation/notifiers/conversation_list_notifier.dart (:51 trở đi)
Severity: P1  Category: Realtime/State inconsistency

Current behavior: Thread notifier lọc reactionUpdate ngay đầu listener, nhưng LIST notifier thì không.
 Signal reaction (content = reactionCode, vd "like") đi tới nhánh idx != -1 →
 copyWith(lastMessage: 'NgườiA : like', unreadCount + 1).
Problem: Người khác thả cảm xúc → phòng bị tính là có tin mới chưa đọc + preview tin cuối bị ghi đè bằng mã reaction.
Why dangerous: Unread badge sai là lỗi UX nhìn thấy ngay, làm giảm tin cậy của cả module.
Recommended solution: Thêm early-return `if (message.type == MessageType.reactionUpdate) return;`
 (và cân nhắc cả MessageDeleted signal — không nên +unread cho tin bị xoá).
```

### P0-3 — README/Quick-start sai hoàn toàn so với API thật

```text
Issue: Tài liệu tích hợp mô tả API không tồn tại
File: README.md (mục "Khởi tạo & Sử dụng nhanh")
Severity: P1 (P0 nếu publish SDK)  Category: Public API/Docs

Current behavior: README yêu cầu `await ChatCore.initialize();`, dùng `ChatListPage(...)`,
 và nhét `backendBaseUrl/apiKey` vào `ChatUiConfig`.
Problem: Trong code KHÔNG có `ChatCore.initialize`, KHÔNG có `ChatListPage`
 (thực tế là `ConversationList` + callback `onTapConversation`), `ChatUiConfig` chỉ chứa màu.
 Tích hợp thật phải override 3 provider (chatModuleConfigProvider, chatAuthTokenProviderProvider,
 chatUiConfigProvider) trong ProviderScope — không được dokumented.
Reproduction: Copy paste quick-start README → compile error ngay.
Recommended solution: Viết lại README theo API thật + thêm `example/` app chạy được
 (melos.yaml khai báo `example` nhưng thư mục không tồn tại).
```

### P1-4 — Không có retry cho tin nhắn gửi thất bại

```text
Issue: Optimistic send đánh dấu failed khi lỗi, nhưng không có API/UI để gửi lại
File: thread_messages_notifier.dart sendMessage (:1116) — catch(_) chỉ set status failed
Severity: P1  Category: Reliability/UX
Problem: Network yếu/mất → tin "failed" nằm vĩnh viễn trong lịch sử, user phải gõ lại.
 Prompt §27 Scenario 7 (send → slow network → retry) không được đáp ứng.
Recommended solution: Thêm `resendMessage(failedId)` trong notifier + action "Gửi lại/Xoá"
 trên bubble failed (đồng thời thêm logging cho catch — hiện error bị nuốt hoàn toàn).
```

### P1-5 — `refreshReactions` gọi API theo từng reaction event (thiếu debounce/dedup)

```text
Issue: Mỗi reaction realtime event → 1 GET get-room-reactions
File: thread_messages_notifier.dart (listener :199 → refreshReactions :115)
Severity: P1  Category: API efficiency
Problem: Burst 20 reaction trong 2s → 20 request trùng mục đích; không có in-flight dedup/debounce.
Recommended solution: Debounce ~300–500ms + reuse request đang pending (single-flight như token repo).
```

### P1-6 — Thread mở: 4–5 API call mỗi lần vào room, thiếu cache không cần thiết

```text
Issue: Mỗi lần mở thread kích hoạt join-room (nếu token hết cache) + get-messages + get-pinned-messages + get-room-reactions + get-members
File: thread_messages_notifier.dart build() (:152) + _loadHistory (:851)
Severity: P1  Category: API efficiency
Problem: getReactionConfigs là cấu hình toàn cục nhưng notifier (autoDispose) cache trong field `_reactionConfigs`
 → mở room nào cũng fetch lại; pinned/reactions fetch song song không dedup với realtime signal cùng nội dung.
Recommended solution: keepAlive cache cho reaction configs; cân nhắc gộp pinned+reactions vào response get-messages (nếu BE hỗ trợ) hoặc guard "chỉ fetch khi screen visible".
```

---

## 4. API Efficiency Issues

| #   | Vấn đề                                                                                                                                                                                                                                                                      | Mức |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --- |
| 1   | Reaction event → API không debounce (P1-5)                                                                                                                                                                                                                                  | P1  |
| 2   | 4–5 call mỗi lần mở thread; reaction configs không cache global (P1-6)                                                                                                                                                                                                      | P1  |
| 3   | `refresh()` của conversation list không có mutex — pull-to-refresh + `_initFromCache` + `_scheduleRefreshForNewRoom` (delay 600ms) có thể chạy chồng lấn; `_mergeConversations` chạy 2 lần song song tuy không crash nhưng tốn request                                      | P2  |
| 4   | `listMessages` trong `MessageRemoteDataSourceImpl` tự giữ `http.Client` + header riêng thay vì tái dùng `JsonApiClient` (duplication nhỏ, không dup request)                                                                                                                | P3  |
| 5   | Không có **catch-up sau reconnect**: socket nối lại chỉ re-enter rooms; tin gửi trong lúc offline/không socket không được kéo bù bằng REST → có thể mất tin hiển thị cho tới lần mở room kế tiếp (phụ thuộc server replay qua `lastVisibleMessageId` — cần xác nhận với BE) | P1  |
| 6   | `LinkPreviewFetcher` fetch inline trong `sendMessage` (timeout 4s) — gửi tin chứa link luôn trễ tối đa 4s kể cả khi preview fail; nên gửi ngay rồi enrich sau                                                                                                               | P2  |

---

## 5. Memory / Resource Issues

| #   | Vấn đề                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Mức  |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| 1   | **Policy keepAlive/autoDispose không nhất quán (Riverpod 3 mặc định auto-dispose)**: `authTokenRepositoryProvider` keepAlive có chủ đích, nhưng `messageRepositoryProvider`/`conversationRepositoryProvider` thì không → rời khỏi mọi màn chat là repo dispose → **WebSocket đóng + controllers đóng**. Điều này mâu thuẫn trực tiếp comment trong `stopWatchingList()` ("socket thuộc session app, chỉ đóng khi logout/app teardown"). Cần quyết định rõ: nếu socket thuộc app-session thì keepAlive repo; nếu thuộc chat-section thì sửa comment/docs | P1   |
| 2   | `NativeRealtimeDataSourceImpl` dispose đúng (close socket, cancel timer/subscription, close controllers) ✅ — nhưng chỉ được gọi qua Riverpod `onDispose` của repo (xem #1); không có cách nào dispose tường minh khi logout ngoài `clearChatModuleUserData` (chỉ xoá cache, không đóng socket)                                                                                                                                                                                                                                                         | P1   |
| 3   | Hive `saveMessages` **rewrite toàn bộ JSON list của thread cho mỗi tin mới** (`_appendToCache` → `saveMessages`) — O(n) encode + disk write trên mỗi event realtime; thread 5.000–10.000 tin sẽ tốn đáng kể CPU/IO                                                                                                                                                                                                                                                                                                                                      | P2   |
| 4   | `MediaUploadProgressNotifier` (không autoDispose) giữ map theo roomId mãi — cần ensure `setRoomProgress(roomId, null)` được gọi khi upload xong                                                                                                                                                                                                                                                                                                                                                                                                         | P3   |
| 5   | `prettyJson` encode **mọi WebSocket event vô điều kiện** trước khi `ChatLogger.log` check `enabled` (`native_realtime_datasource_impl.dart:147`) — tốn CPU cả khi logging tắt                                                                                                                                                                                                                                                                                                                                                                           | P2   |
| 6   | Timer/subscription trong ThreadScreen (`_searchDebounce`, `_highlightTimer`, listeners) dispose đầy đủ ✅                                                                                                                                                                                                                                                                                                                                                                                                                                               | KEEP |

---

## 6. Crash / Reliability Issues

| #   | Vấn đề                                                                                                                                                                                                                | Mức  |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| 1   | `UnimplementedError` providers — host quên override = crash runtime không báo trước (xem §2.3-E)                                                                                                                      | P1   |
| 2   | **57 `catch (_)`**; đa số ở đường cache có comment (chấp nhận được), nhưng `sendMessage` catch lỗi send không log, `_getSenderAvatar`, `refreshReactions`... nuốt lỗi im lặng → debug production rất khó (prompt §12) | P2   |
| 3   | ID signal realtime tự sinh bằng `DateTime.now().millisecondsSinceEpoch` (`'room_updated_...'`) — 2 event cùng millisecond → **trùng ID**, list keyed-by-id có thể rụng 1 signal; nên dùng uuid hoặc sequence          | P2   |
| 4   | Signal `MessageDeleted` có `type = MessageType.text` + content tiếng Việt — đi vào list notifier như tin thường (+unread). Type nên là tín hiệu delete, không phải text                                               | P2   |
| 5   | Không thấy pattern nguy hiểm `!`/`.first`/`.single`/cast thô ở các file trọng yếu — code phòng thủ tốt (`firstOrNull`, tryParse) ✅                                                                                   | KEEP |
| 6   | `leaveActiveRoom` trong `dispose()` của ThreadScreen bọc try/catch — đúng, nhưng kết hợp P0-1 tạo bug hành vi chứ không crash                                                                                         | —    |

---

## 7. Realtime / ACS Issues

**Đánh giá riêng (prompt §4, §7):**

1. **Không còn ACS realtime** — toàn bộ realtime là WebSocket BE (xem §2.3-A). Câu hỏi của prompt "ACS listener có bị register nhiều lần không?" → hiện không tồn tại ACS listener nào bên Flutter; risk tương đương là `enter_room` bị gửi nhiều lần nếu `watchNewMessages` cùng room được gọi lại nhiều lần trước khi socket connected (mỗi lần gọi add vào `_activeRoomIds` — Set nên không dup, nhưng `enter_room` frame có thể gửi trùng khi `_serverConnected` true; server cần idempotent).
2. **Điểm tốt (KEEP)**: backoff `[1,2,4,8,15,30]s + jitter`, idle detection `interval*2`, auth close codes `{1008,4003,4401,4403}` + `_looksLikeAuthError`, `onSessionExpired` callback cho host, `resetSession()` để host tái kết nối sau login lại, `cancelOnError: true`.
3. **Bug hành vi**: P0-1 (background/foreground), P0-2 (reaction leak ở list), thiếu catch-up (API #5), clear `_lastVisibleMessageId` mỗi lần `watchNewMessages` → read-receipt của room trước bị reset khi switch room.
4. **API surface gây hiểu nhầm**: `watchListMessages(String roomId)` nhận param không dùng (đã ghi nhận từ review trước, chưa sửa); constructor param `platform`/`authTokenRepository` chết.
5. **Thiếu observability**: không có state "connected/reconnecting/disconnected" expose ra UI (chỉ có online/offline của device qua `connectivity_plus`) — user không biết realtime đang chết.
6. **Native plugin** (`ChatNativePlugin.kt/sw`): code ACS SDK hoàn chỉnh (ChatClient, CommunicationTokenCredential, Trouter events) nhưng **không có đường gọi từ Flutter** → nên deprecate/remove để tránh host app bundle Azure SDK vô ích (chi tiết trong `review/chat-native-review.md`).

---

## 8. UI Architecture

- **Tích cực (KEEP)**: `scrollable_positioned_list` cho inverted list + load-older khi gần đỉnh (guard `isLoadingOlder` tốt); skeleton loading; offline banner; RouteAware + WidgetsBindingObserver đầy đủ; permission ảnh đã chuyển sang lazy (mở gallery mới xin) ✅.
- **Vấn đề**:
    - `thread_screen.dart` 2.263 dòng vẫn chứa search UI, pin flow (`_togglePin`/`_setMessagePin` tại :1198, :2026), scroll logic, upload banner, toast — 17+ `setState`. (review trước đề xuất tách ~7 widget; đã tách được một phần sang `widgets/` nhưng Screen vẫn giữ orchestration).
    - `visibleMessages = messages.where(...)` tính trong `build()` (:1359) — O(n) mỗi rebuild; nên là derived state trong notifier (prompt §19).
    - `state = [...state]` hack rebuild còn 5 chỗ — triệu chứng của state shape nghèo (`Notifier<List<Message>>` + field ngoài state `_pinned`, `_reactionConfigs`, `myAcsUserId`, `_historyLoaded`). Khuyến nghị `ThreadState` immutable (đã đề xuất từ review trước, chưa làm).
    - **Pin flow viết trong Screen ở 3 nơi** (`thread_screen`, `conversation_list_screen`, `room_settings_screen`) — optimistic update + rollback + quy tắc "tối đa 3 pin, phải chọn tin thay thế" là business logic, phải nằm trong notifier/use-case.
    - Nhận diện media-only vẫn so chuỗi placeholder (`'[Hình ảnh]'`, `'[Video]'`...) — nên dựa vào metadata/resource types.

---

## 9. Public API Review (prompt §16–18)

**Đánh giá theo 3 level custom UI:**

| Level                    | Hỗ trợ hiện tại                                                                                                                                                                                                                                                                                                                              | Đánh giá               |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| A – Dùng UI mặc định     | Có (`ConversationList`, `ThreadScreen`, `RoomSettingsScreen`) nhưng **không có navigator/router thống nhất** — host tự push route, tự nối `onTapConversation`                                                                                                                                                                                | ⚠️ hoạt động nhưng thô |
| B – Customize một phần   | `ChatUiConfig` ~25 color token; **không có slot/builder API** (`messageBuilder`, `inputBuilder`, `appBarBuilder` đều không tồn tại); 320 chỗ hardcode màu trong chat_ui khiến config phủ không hết                                                                                                                                           | ❌ thiếu               |
| C – Tự xây UI (headless) | Về lý thuyết: host dùng use-case + repo từ chat_core (có export). Thực tế: API chưa thiết kế cho consumption (repo impl expose kèm, thiếu facade `ChatController`, thiếu docs, thiếu error type công khai, `watchNewMessages` trả `Message` nhưng signal realtime trộn lẫn message thật — consumer phải tự phân loại `MessageType`/metadata) | ❌ thiếu               |

**Các vấn đề public API chính:**

1. README quick-start sai hoàn toàn (P0-3).
2. Barrel `chat_core.dart` export cả data models + impl → consumer phụ thuộc implementation detail, khó giữ backward compatibility.
3. `ChatModuleConfig.acsEndpoint` required nhưng vô dụng; `ChatUiConfig` trong README bị mô tả sai field.
4. Naming leak ACS (`acsUserId`, `8:acs:` prefix xuất hiện trong logic UI) — nếu sau này BE đổi identity scheme, public model sẽ bị ảnh hưởng.
5. Không có error taxonomy công khai: chỉ `ChatApiException` (statusCode/code/message); consumer không phân biệt được network vs auth vs ACS/BE vs cancelled.
6. Không versioning strategy: install qua git ref `development`; pubspec `0.1.0` + `publish_to: none` — cần quy ước tag/CHANGELOG trước khi nhân bản sang app thứ hai.
7. Không có example app → integrator tự mò (melos workspace khai báo `example` nhưng thư mục trống).

---

## 10. Performance Review

| Quy mô                   | Đánh giá                                                                                                                                                     |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Small (<500 tin)         | Mượt — cache-first paint nhanh, identity restore từ Hive trước khi chờ join-room                                                                             |
| Medium (1.000–5.000 tin) | Bắt đầu tốn: `visibleMessages` filter O(n) mỗi rebuild + Hive rewrite toàn list mỗi tin mới; vẫn chấp nhận được trên máy tầm trung                           |
| Large (5.000–10.000 tin) | Rủi ro: Hive JSON encode/decode nguyên thread (vài MB) trên mỗi append; `_chronological` sort + clone list mỗi merge; nên benchmark trước khi cam kết hỗ trợ |

Điểm tốt: `ListView` qua `scrollable_positioned_list` (lazy build), debounce search 350ms, avatar cache trong notifier, upload qua SAS không chiếm băng thông BE.

---

## 11. Testability

- **Có thể test tốt (về thiết kế)**: repo/use-case inject interface; notifier dùng Riverpod overrides; Hive datasource nhận `Box` qua constructor; realtime datasource tách interface.
- **Thực tế**: ~1.028 dòng test / ~20.900 LOC (~5%). chat_core: 4 file (auth token, message, repo cache, group conversation). chat_ui: 3 file tiện ích nhỏ — **0 test cho ThreadMessagesNotifier, ConversationListNotifier, mọi screen/widget chính**.
- **Test cases còn thiếu (theo rủi ro, prompt §23/§27)**:
    1. Realtime datasource: pause/resume + reconnect re-enter rooms (P0-1); duplicate `watchNewMessages`; auth close codes.
    2. ConversationListNotifier: `_onNewMessage` mọi nhánh (reaction phải bị lọc — P0-2; disband/kick/pin/update; đẩy phòng lên đầu).
    3. ThreadMessagesNotifier: merge cache/remote, isMe identification, optimistic send + echo dedup + rollback, pin toggle/rollback, `loadUntilMessage` cận trên.
    4. Pagination: load-older + realtime xen ngang không dup tin.
    5. Token repo: single-flight khi N caller song song; retry không lặp khi auth fail.
- **Đề xuất CI**: melos analyze/test/format bắt buộc + custom lint cấm `package:flutter` trong chat_core, cấm UI import data model.

---

## 12. API Call & Resource Matrix (prompt §25)

| Operation         | Current API Call                          | Trigger                                                 | Dư thừa?                       | Cache?                         | Deduplicate?               | Risk                                                              |
| ----------------- | ----------------------------------------- | ------------------------------------------------------- | ------------------------------ | ------------------------------ | -------------------------- | ----------------------------------------------------------------- |
| Mở danh sách room | GET `/api/chat/get-room-chats`            | list open, pull-refresh, debounce 600ms khi có room mới | Có thể chồng lấn (không mutex) | Hive cache-first ✅            | ❌                         | Request trùng khi refresh chồng                                   |
| Mở thread         | GET `/api/chat/join-room/{id}`            | mỗi lần mở room                                         | ❌ cần (lấy identity)          | Token RAM cache + keepAlive ✅ | Single-flight ✅           | None đáng kể                                                      |
| Lịch sử tin       | GET `/api/chat/get-messages`              | mở thread + load-older                                  | Không                          | Hive cache-first ✅            | ❌                         | Race realtime-vs-REST khi load page đầu (đã xử lý dedup by-id ✅) |
| Tin ghim          | GET `/api/chat/get-pinned-messages/{id}`  | mỗi lần mở thread (sau load history)                    | Có thể gộp                     | ❌                             | ❌                         | Nhẹ                                                               |
| Reactions room    | GET `/api/chat/get-room-reactions/{id}`   | mở thread + **mỗi reaction event realtime**             | **Có (burst)**                 | ❌                             | ❌                         | P1-5                                                              |
| Reaction configs  | GET `/api/chatadmin/get-reaction-configs` | mỗi lần mở thread                                       | **Có** — config global         | Chỉ trong notifier autoDispose | ❌                         | Nên keepAlive cache                                               |
| Gửi tin           | POST `/api/chat/send-message`             | user send                                               | Không                          | —                              | ❌ (không có retry/resend) | Fail không gửi lại được (P1-4)                                    |
| Realtime          | WebSocket `/ws/chat/view` + heartbeat     | watch thread/list                                       | Không                          | —                              | enter_room có thể trùng    | P0-1, thiếu catch-up                                              |
| Read receipt      | heartbeat `lastVisibleMessageId`          | tin mới visible                                         | Không                          | dedup same-id ✅               | ✅                         | `_lastVisibleMessageId` reset khi switch room                     |

---

## 13. Lifecycle Matrix (prompt §26)

| Lifecycle           | Expected                                       | Current                                                                        | Risk                                          |
| ------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------ | --------------------------------------------- |
| Initialize          | Host override config+token provider, Hive init | `throw UnimplementedError` nếu quên; không có `ChatCore.initialize` như README | Crash runtime, docs sai                       |
| Open conversation   | Cache → identity → remote → realtime           | Đúng trình tự, guard `ref.mounted` tốt ✅                                      | 4–5 API call (P1-6)                           |
| Switch conversation | Leave room cũ, enter room mới                  | stopWatching + enter_room ✅; `_lastVisibleMessageId` reset                    | Read receipt room cũ có thể mất               |
| Background          | Giữ trạng thái, giảm resource                  | `leaveActiveRoom()` xóa `_activeRoomIds`                                       | —                                             |
| Foreground          | **Re-enter rooms, khôi phục realtime**         | Chỉ `sendReadMessageIfNeeded`; reconnect re-enter từ tập rỗng                  | **P0-1**                                      |
| Logout              | Đóng socket, xoá cache, reset token            | `clearChatModuleUserData` xoá Hive; socket/token repo không dispose tường minh | Zombie socket/token tới khi repo auto-dispose |
| Login again         | Reset session, reconnect                       | `resetSession()` có sẵn, host phải tự gọi                                      | Phụ thuộc host                                |
| Dispose             | Cancel subs, close controllers                 | Riverpod `onDispose` đúng ✅                                                   | Phụ thuộc autoDispose policy (Mục 5-#1)       |
| Reconnect           | Backoff, re-enter, catch-up                    | Backoff+re-enter ✅, catch-up ❌                                               | Mất tin trong lúc down                        |

---

## 14. Refactoring Priority (prompt §31)

| Priority | Issue                                                                             | File                                                                                                | Impact                     | Effort         | Recommendation                                                                |
| -------- | --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | -------------------------- | -------------- | ----------------------------------------------------------------------------- |
| P0       | Realtime chết sau background/foreground                                           | `thread_screen.dart:493`, `native_realtime_datasource_impl.dart` (leaveActiveRoom)                  | Critical UX                | Low            | Giữ `_activeRoomIds` khi leave; re-enter on resume                            |
| P0       | README/quick-start sai API thật + thiếu example                                   | `README.md`, `example/`                                                                             | Blocking cho tích hợp      | Low–Medium     | Viết lại docs, tạo example app tối thiểu                                      |
| P1       | Reaction event → unread/preview sai ở list                                        | `conversation_list_notifier.dart:51`                                                                | State sai visible          | Low            | Early-return reactionUpdate (+MessageDeleted)                                 |
| P1       | Thiếu catch-up sau reconnect                                                      | `native_realtime_datasource_impl.dart`                                                              | Mất tin                    | Medium         | REST catch-up (listMessages delta) khi reconnect, hoặc xác nhận server replay |
| P1       | Reaction API burst, thiếu debounce                                                | `thread_messages_notifier.dart:115,199`                                                             | API dư thừa                | Low            | Debounce 300–500ms + single-flight                                            |
| P1       | Không retry tin fail                                                              | `thread_messages_notifier.dart:1116`                                                                | UX + reliability           | Medium         | `resendMessage` + UI action                                                   |
| P1       | keepAlive policy repo/realtime không nhất quán                                    | `shared_providers.dart`                                                                             | Resource + reconnect churn | Low            | Quyết định app-session vs section-session, keepAlive tương ứng                |
| P1       | ACS legacy: `acsEndpoint` required vô dụng, native plugin dead, naming misleading | `chat_module_config.dart`, `chat_native_platform_interface`, README                                 | Kiến trúc + size app       | Medium         | Quyết định strip-ACS (khuyến nghị) — xem §16                                  |
| P1       | Pin flow trong 3 Screen                                                           | `thread_screen.dart:1198,2026`, `conversation_list_screen.dart:98`, `room_settings_screen.dart:288` | Maintainability + test     | Medium         | Gom về notifier/use-case                                                      |
| P2       | Text tiếng Việt trong data layer                                                  | `native_realtime_datasource_impl.dart` (`_handleRoomEvent`), `message_model.dart`                   | i18n + consistency         | Medium         | Event mapper chỉ sinh metadata; text builder ở UI                             |
| P2       | Barrel export data models/impl                                                    | `chat_core.dart`                                                                                    | Breaking-change risk       | Low            | Chỉ export domain + interfaces (kèm migration note)                           |
| P2       | O(n) filter trong build + `state=[...state]` hack                                 | `thread_screen.dart:1359`, `thread_messages_notifier.dart`                                          | Perf + clarity             | Medium         | `ThreadState` immutable + derived state trong notifier                        |
| P2       | Hive rewrite toàn list mỗi tin                                                    | `hive_message_local_datasource.dart`                                                                | Perf large thread          | Medium         | Lưu theo chunk/page hoặc append-only                                          |
| P2       | prettyJson mọi event                                                              | `native_realtime_datasource_impl.dart:147`                                                          | CPU                        | Low            | Lazy encode nếu `ChatLogger.enabled`                                          |
| P2       | 320 màu hardcode                                                                  | chat_ui widgets                                                                                     | Theming                    | Medium         | Mở rộng `ChatUiConfig` token phủ đủ                                           |
| P3       | 57 `catch (_)` thiếu log                                                          | rải rác                                                                                             | Debuggability              | Low            | Log mức debug trước khi nuốt                                                  |
| P3       | UnimplementedError DI                                                             | `shared_providers.dart`, `thread_providers.dart`                                                    | DX                         | Medium         | `.family`/ChatScope widget                                                    |
| P3       | Test ~5%                                                                          | toàn bộ                                                                                             | Reliability                | High (dần dần) | Ưu tiên notifier + realtime (mục 11)                                          |

---

## 15. Recommended Target Architecture (prompt §32)

```text
Current Architecture
 - BE REST + BE WebSocket, ACS chỉ còn là di sản (identity)
 - 3 package, barrel leak, text UI trong data layer, coupling chéo feature
        ↓
Problems (§2.3, §3)
 - Identity ACS misleading + dead native plugin
 - Public API drift (README), thiếu Option B/C cho custom UI
 - Realtime lifecycle bug, thiếu catch-up, reaction burst
 - God-file, pin flow sai tầng, Hive rewrite O(n)
        ↓
Target Architecture
 chat_core (pure Dart)
   ├─ domain/            entity + error taxonomy công khai (ChatError: network|auth|server|cancelled)
   ├─ data/              repo impl + mappers (KHÔNG export qua barrel)
   ├─ realtime/          RealtimeEngine (WebSocket) + RoomEventMapper (chỉ metadata, không text)
   │                     + ConnectionState stream (public cho UI vẽ trạng thái)
   ├─ identity/          bỏ semantics "acs" khỏi tên public (internal mapping giữ nếu BE cần)
   └─ chat_controller.dart  ← facade headless cho Option C:
         messages stream, sendMessage/resend, loadMore, markAsRead, pin, react...
 chat_ui
   ├─ screens/ (mỏng)    chỉ compose + gọi controller/notifier
   ├─ widgets/ (1 file = 1 class) + theming token phủ đủ
   ├─ features/shared/   realtime + identity providers (cắt import chéo)
   └─ text/              system message builder (1 nguồn, i18n-ready)
 example/                app mẫu chạy được = living documentation
        ↓
Migration Steps → §16
```

Ưu tiên target: dễ debug (state một nguồn + connection state visible), không API dư thừa (debounce/single-flight/catch-up), không leak implementation (barrel hẹp + controller facade), dễ custom UI (3 level A/B/C rõ ràng).

---

## 16. Migration Plan (prompt §33)

### Phase 1 — Critical Fixes (0.5–1.5 ngày)

1. Fix P0-1: `leaveActiveRoom` không xóa `_activeRoomIds`; resume re-enter rooms (kèm test).
2. Fix P0-2: lọc reaction/deleted signal trong `_onNewMessage`.
3. Viết lại README quick-start theo API thật; tạo `example/lib/main.dart` tối thiểu.
4. Debounce `refreshReactions`; early-return message type không liên quan ở list.

### Phase 2 — Architecture (3–5 ngày)

1. **Strip ACS legacy** (quyết định trong phase này): bỏ `acsEndpoint` khỏi config (hoặc để optional no-op + doc), deprecate/remove `chat_native_platform_interface`, rename `NativeRealtimeDataSource*` → `WebSocketRealtimeDataSource*` (alias giữ tương thích), cập nhật README đúng thực tế BE+WebSocket.
2. Thống nhất keepAlive policy: realtime + repo thuộc app-session (keepAlive) hoặc section-session (docs rõ); thêm `dispose()` tường minh cho logout.
3. Catch-up sau reconnect: REST delta khi socket hồi phục (phối hợp BE xác nhận replay).
4. Tách `RoomEventMapper` khỏi datasource; chuyển text tiếng Việt sang UI builder.
5. Hẹp barrel `chat_core.dart` (ngừng export data models/impl).

### Phase 3 — UI (3–4 ngày)

1. Gom pin flow về notifier/use-case (3 screen đang giữ logic).
2. Tách phần còn lại của `thread_screen.dart` (search view, scroll logic) — target < 500 dòng.
3. `ThreadState` immutable thay `List<Message>` + field rời; derived `visibleMessages` trong notifier.
4. Mở rộng `ChatUiConfig` phủ 320 chỗ hardcode màu; thêm builder API cho Option B (messageBuilder/inputBuilder/appBarBuilder).

### Phase 4 — Public API (2–3 ngày)

1. `ChatController` facade headless cho Option C + error taxonomy `ChatError`.
2. Connection state stream public; resend API; versioning strategy (tag + CHANGELOG + ref ổn định).
3. `UnimplementedError` providers → `.family`/`ChatScope`.

### Phase 5 — Testing (liên tục)

Theo mục 11; mỗi phase kết thúc bằng `melos run analyze && format && test` + 4 luồng thủ công (mở room, gửi/nhận, ghim, background/foreground).

---

## Production Readiness Verdict

```text
⚠️ READY WITH MAJOR FIXES
```

Đang dùng nội bộ cho NPP-Mobile: chấp nhận được nếu fix Phase 1 ngay.
**Chưa đủ điều kiện publish cho nhiều app** cho tới khi hoàn thành Phase 1–2 và phần lớn Phase 4.

**Must Fix Before Release:**

1. P0-1 — Realtime không phục hồi sau background/foreground (re-enter rooms).
2. P0-3 — README/quick-start sai API + thiếu example app (integrator không thể tự tích hợp).
3. P0-2 — Reaction event làm sai unread count/preview ở danh sách phòng.
4. Strip hoặc tái kích hoạt có chủ đích phần ACS legacy (`acsEndpoint`, native plugin) — tránh bundle SDK chết và config vô nghĩa.
5. Retry/resend cho tin nhắn gửi thất bại.

**Should Fix:**

1. Catch-up tin nhắn sau reconnect (hoặc xác nhận server replay qua `lastVisibleMessageId`).
2. Debounce/single-flight cho reaction API; cache global cho reaction configs.
3. KeepAlive policy nhất quán cho repository/realtime + dispose tường minh khi logout.
4. Gom pin flow về notifier; tách `thread_screen.dart`/`thread_messages_notifier.dart`.
5. Hẹp barrel chat_core; chuyển text sự kiện khỏi data layer (chuẩn bị i18n).

**Nice to Have:**

1. `ChatController` headless + builder API (Option B/C) để consumer tự xây UI.
2. Phủ theming đầy đủ (320 màu hardcode → token).
3. CI architecture lint + nâng coverage test lên toàn bộ notifier.
4. Hive incremental cache cho thread lớn; benchmark 5.000–10.000 tin.
