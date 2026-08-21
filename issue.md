# Danh Sách Issue — ACS-Chat-Flutter (chat-module-mvp)

> Ngày review: 2026-08-21
> Phạm vi: toàn bộ source `chat-module-mvp/` (chat_core, chat_ui, chat_native_platform_interface, example) ~20.500 dòng Dart.
> Tiêu chí đánh giá: `Project-guildline_and_structure_chat.md` + `CLEAN_CODE_RULES.md`.
> Mức độ: **P0** bug hành vi · **P1** vi phạm kiến trúc · **P2** clean code/bảo trì · **P3** hiệu năng, bảo mật, testing.

---

## P0 — Bug hành vi

### 1. Tin mới realtime không đẩy phòng lên đầu danh sách (sai khác với comment)
- **Vị trí:** `packages/chat_ui/lib/features/conversation_list/presentation/notifiers/conversation_list_notifier.dart` (`_startListRealtime` :36, `_onNewMessage` :51).
- **Mô tả:** Doc comment ghi "tin mới xuất hiện (lastMessage + **đẩy lên đầu**) ngay", nhưng nhánh room-đã-tồn-tại trong `_onNewMessage` chỉ `state.map(...)` cập nhật `lastMessage`/`unreadCount` tại chỗ, không sắp xếp lại. Method có logic đẩy lên đầu (`updateLastMessage` :285) chỉ được gọi từ `ThreadMessagesNotifier` khi **tự gửi tin từ trong thread** (`thread_messages_notifier.dart:970`).
- **Ảnh hưởng:** Đang ở màn danh sách, người khác nhắn tin → phòng không nhảy lên đầu, trải nghiệm sai so với app chat chuẩn.

### 2. Lọc tin nhắn bằng username hardcode "Thái Đăng" (debug hack còn sót)
- **Vị trí:** `packages/chat_ui/lib/features/thread/presentation/notifiers/thread_messages_notifier.dart:747`
  ```dart
  if (content == 'Bạn đã bị xóa khỏi phòng') continue;
  if (m.type != MessageType.system && content == 'Thái Đăng') continue;
  ```
- **Mô tả:** Mọi tin nhắn (không phải system) có nội dung đúng bằng chuỗi "Thái Đăng" bị ẩn khỏi lịch sử. Đây là filter theo **tên một người cụ thể** — gần như chắc chắn là hack debug/test còn sót.
- **Ảnh hưởng:** Người dùng thật (hoặc bất kỳ ai gõ đúng nội dung đó) bị mất tin nhắn hiển thị. Cần xoá ngay.

### 3. Log full payload participants ngay trong `build()`
- **Vị trí:** `packages/chat_ui/lib/features/thread/presentation/screens/thread_screen.dart:1352-1366`.
- **Mô tả:** Mỗi lần `build()` chạy (mọi rebuild), màn hình gọi `ChatLogger.logRequest('PARTICIPANTS PAYLOAD...', body: <toàn bộ id, acsUserId, displayName, avatarUrl của thành viên>)`.
- **Ảnh hưởng:** (a) Side effect trong `build` — vi phạm nguyên tắc Flutter; (b) spam log cực lớn gây chậm UI; (c) đổ dữ liệu cá nhân (PII) vào log kể cả release build.

### 4. `ChatLogger` bật mặc định, log toàn thân request/response kể cả release
- **Vị trí:** `packages/chat_core/lib/core/utils/chat_logger.dart` (`enabled = true` static) + toàn bộ `JsonApiClient`, `NativeRealtimeDataSourceImpl`.
- **Mô tả:** Mọi HTTP body (nội dung tin nhắn), mọi WebSocket event được pretty-log vô điều kiện; không gắn cờ debug-only.
- **Ảnh hưởng:** Rò rỉ nội dung chat vào log thiết bị, perf tốn khi parse/encode JSON.

### 5. `loadUntilMessage` lặp vô hạn không có cận trên
- **Vị trí:** `packages/chat_ui/lib/features/thread/presentation/notifiers/thread_messages_notifier.dart:1367`.
- **Mô tả:** `while (true)` liên tục `loadOlder()` + poll 300ms nếu đang bận, chỉ dừng khi `_cursor == null`. Nếu message không tồn tại nhưng cursor vẫn còn do dữ liệu lệch, vòng lặp chạy đến khi hết toàn bộ lịch sử (rất nhiều page) mà không có max-attempt/timeout.
- **Ảnh hưởng:** Treo logic + gọi API dồn dập trong kịch bản biên (jump-to-message từ push notification).

### 6. Danh sách rỗng thì không bật realtime
- **Vị trí:** `conversation_list_notifier.dart:36-45`.
- **Mô tả:** `_startListRealtime()` return sớm nếu `state.firstOrNull == null`. Người dùng mới (chưa có phòng) sẽ không nhận được sự kiện phòng mới cho tới lần `refresh()` kế tiếp; hơn nữa `roomId` truyền vào `watchListMessages` thực tế bị datasource bỏ qua (`native_realtime_datasource_impl.dart:618` không dùng `roomId`).
- **Ảnh hưởng:** Kịch bản "được mời vào phòng đầu tiên" không hiện realtime; API surface gây hiểu nhầm (tham số không dùng).

### 7. Placeholder media nhận diện bằng chuỗi tiếng Việt hardcode
- **Vị trí:** `packages/chat_ui/lib/features/thread/presentation/widgets/message_bubble.dart` (`isMediaOnly` check: `'[Hình ảnh]'`, `'Hình ảnh'`, `'[Video]'`, `'Video'`); `thread_messages_notifier.dart` gửi tin với content `'[Video]'`.
- **Mô tả:** Việc xác định "tin chỉ chứa media" dựa vào so khớp nội dung text. Nếu BE đổi placeholder hoặc locale khác, bubble sẽ hiển thị text rác thay vì media.
- **Hướng sửa:** Nhận diện qua `metadata['type']`/`MessageType` (đã có `mediaType`), không so content.

---

## P1 — Vi phạm kiến trúc

### 8. Hai feature `conversation_list` ⇄ `thread` import provider lẫn nhau
- **Vị trí:**
  - `conversation_list_notifier.dart:5-7` import `thread/presentation/providers/thread_providers.dart` (dùng `watchListMessagesUseCaseProvider`).
  - `thread_messages_notifier.dart:10` import `conversation_list/presentation/providers/conversation_providers.dart` và gọi `conversationListProvider.notifier.updateRoomParticipants(...)`.
  - `thread_screen.dart:17` và `conversation_list_screen.dart` cùng import chéo.
- **Mô tả:** Vi phạm nguyên tắc cô lập feature (CLEAN_CODE_RULES mục 1.5, 4.3.6): feature A không được gọi/notifier-mutate state của feature B.
- **Hướng sửa:** Đưa realtime watch + participants/current-user vào `features/shared/`.

### 9. Logic nghiệp vụ "pin" nằm rải rác trong Screen, bypass Notifier, code trùng lặp
- **Vị trí:** `thread_screen.dart` (`_setMessagePin` ~:1640, `_togglePin` ~:1605 — gọi thẳng `pinMessageUseCaseProvider` từ screen) và `conversation_list_screen.dart` (`_togglePin` ~:104) — 2 bản copy của cùng 1 flow optimistic + rollback + toast.
- **Mô tả:** Screen gọi trực tiếp UseCase và tự rollback state → logic phân tán, không test được, vi phạm "Presentation gọi qua Notifier" (guideline 3.3) và rule 4.1.2/4.3.7.

### 10. Presentation dùng class của Data layer (`ConversationSummaryModel`)
- **Vị trí:** `conversation_list_notifier.dart:115` dựng `ConversationSummaryModel` (data model) thay vì `ConversationSummary` (entity). Cùng file, `updateLastMessage` lại dùng `ConversationSummary` — bất nhất.
- **Mô tả:** Barrel `chat_core.dart` export cả data models (`message_resource_model.dart`, `conversation_model.dart`...) khiến UI phụ thuộc type tầng Data — vi phạm dependency rule.

### 11. `core` phụ thuộc ngược vào `features`
- **Vị trí:** `packages/chat_ui/lib/core/chat_navigator.dart:3` import `features/thread/presentation/screens/thread_screen.dart`.
- **Mô tả:** Layer `core/` (utils/widgets dùng chung) không được import code feature; hướng phụ thuộc đúng là feature → core.

### 12. Data layer đặt trong package Presentation
- **Vị trí:** `packages/chat_ui/lib/features/shared/data/local/` (Hive local datasources + identity store).
- **Mô tả:** Guideline định nghĩa Data layer thuộc `chat_core`. Việc Hive cần Flutter binding là lý do chính đáng, nhưng đây là **deviation không được ghi nhận trong guideline** (cấu trúc doc không hề nhắc tới thư mục này). Interface nằm ở chat_core, implementation nằm chat_ui — cần document rõ pattern dependency-inversion này.

### 13. Text nghiệp vụ tiếng Việt hardcode ở 3 tầng, không i18n
- **Vị trí:**
  - Data: `chat_core/lib/features/thread/data/models/message_model.dart` (`fromAcsJson` sinh câu "đã chuyển quyền Trưởng phòng", "đã phong Admin"...).
  - Presentation: `thread_messages_notifier.dart` (`_appendSystemSignalMessage`, ~:347...) sinh câu tương tự cho realtime signal.
  - UI: hàng chục chuỗi toast/dialog hardcode trong `thread_screen.dart`, `chat_dialogs.dart`, `room_settings_screen.dart`...
- **Mô tả:** Cùng một loại sự kiện hệ thống được render text ở 2 nơi độc lập (REST history vs realtime) → dễ lệch nhau; không có cơ chế i18n; không đổi được ngôn ngữ.

### 14. Logic so khớp user ACS trùng lặp 3+ nơi
- **Vị trí:** `_isSameUser`/`_normalizeAcsId` xuất hiện trong `conversation_list_notifier.dart`, `thread_messages_notifier.dart`, `thread_screen.dart` (các bản copy gần giống nhau, bản ở thread_screen thiếu xử lý suffix `_` so với conversation notifier).
- **Hướng sửa:** Gom về 1 util trong `chat_core/core/utils/`.

### 15. Doc cấu trúc lệch thực tế (document drift)
- **Vị trí:** `Project-guildline_and_structure_chat.md`.
- **Mô tả:** Doc ghi feature `read_status` và thư mục `shared/` trong `chat_core` — thực tế **không tồn tại** (`chat_core/lib/features` chỉ có auth_token, contact, conversation_list, thread). ChatUser/ChatModuleConfig/ChatApiException trong doc ghi ở `shared/domain/entities` nhưng thực tế ở `core/domain/entities` và `core/error`. Thư mục `example/` chỉ có `android/`, không có `lib/` Dart.

### 16. Dead code: package `chat_native_platform_interface` + tham số constructor chết
- **Vị trí:** `native_realtime_datasource_impl.dart:5,23-29` — constructor nhận `platform` và `authTokenRepository` nhưng **không lưu/không dùng**; realtime đã chuyển sang WebSocket backend.
- **Mô tả:** Toàn bộ package `chat_native_platform_interface` (NativeChatMessageEvent, MethodChannel/EventChannel) không còn nơi nào sử dụng. Giữ vì "tương thích source" nhưng nên deprecated/xoá + cập nhật MIGRATION_GUIDE_V2.md. `PollingEngine` cũng chỉ được nối vào `MessageRemoteDataSourceImpl.watchNewMessages` — nhánh không còn được repository dùng.

---

## P2 — Clean code / bảo trì

### 17. God files (file quá lớn, nhiều trách nhiệm)
| File | Dòng | Vấn đề |
|---|---|---|
| `chat_ui/.../screens/thread_screen.dart` | 2649 | Screen chứa: search, pinned banner, message actions sheet, pin flow, scroll logic, upload banner, toast, lifecycle handling. 17 `setState`. |
| `chat_ui/.../notifiers/thread_messages_notifier.dart` | 1390 | 1 notifier gánh: history, realtime, identity, reactions, pin, upload ảnh/file/video, read receipt, system signal. |
| `chat_ui/.../widgets/message_bubble.dart` | 1350 | 5 widget class trong 1 file (`MessageBubble`, `_MediaContent`, `_VideoMessageContent`, `_LinkPreviewCard` + states), 6 helper `_build*`. |
| `chat_ui/.../widgets/message_input.dart` | 1018 | Gallery panel, attachment, permission, send logic trong 1 widget; 19 `setState`, 3 helper `_build*`. |
| `chat_ui/.../screens/room_settings_screen.dart` | 965 | 6 helper `Widget _build*` (vi phạm trực tiếp rule 4.3.1). |
| `chat_ui/.../screens/room_resources_category_screen.dart` | 814 | 3 tab widget lớn trong cùng 1 file. |
| `chat_core/.../native_realtime_datasource_impl.dart` | 708 | 1 class xử lý: connect, reconnect, heartbeat, auth expire, dispatch ~15 loại room_event, emit. |
| `chat_core/.../message_remote_datasource_impl.dart` | 686 | Nhiều endpoint (message + pin + reader + resource + reaction) chung 1 file. |

### 18. 18 helper `Widget _build*` — vi phạm rule tổ chức component (4.3)
- `message_bubble.dart` ×6 (`_buildBody`, `_buildImageGrid`, `_buildSingleImage`, `_buildFileList`, `_buildSystemMessageText`, `_buildErrorBody`...)
- `room_settings_screen.dart` ×6 (`_buildRoomHeader`, `_buildMemberRow`, `_buildDangerZoneSection`, `_buildGroupQuickActions`, `_buildGroupInfoRows`, `_buildDirectRoomOptions`)
- `message_input.dart` ×3 (`_buildGalleryPanel`, `_buildGalleryDeniedView`, `_buildPickMoreTile`)
- `room_resources_category_screen.dart`, `room_resource_preview_section.dart`, `rich_message_text.dart` ×1 mỗi file.

### 19. Logging không thống nhất
- Notifier/widget dùng `developer.log` trực tiếp (27 chỗ: thread_messages_notifier ×12, thread_screen ×6, message_input ×5, message_bubble ×3, message_readers_sheet ×1) thay vì `ChatLogger` của core.

### 20. 58 `catch (_)` nuốt lỗi im lặng
- Phần lớn ở đường cache (chấp nhận được, có comment) nhưng nhiều chỗ không comment/không log (vd `thread_messages_notifier.dart` `refreshReactions` catch xong bỏ qua, `_getSenderAvatar` trong thread_screen). Vi phạm rule 6.2.

### 21. 51 màu hardcode `Color(0x...)` + `Colors.*` rải rác dù đã có `ChatUiConfig`
- Nặng nhất: `thread_screen.dart` (55 chỗ), `message_bubble.dart` (45), `room_resources_category_screen.dart` (38). Config chỉ phủ 1 phần; fallback `Colors.*`vẫn rải rác khắp nơi → host app (NPP-Mobile) không thể theme đồng bộ.

### 22. State shape nghèo nàn → hack rebuild bằng `state = [...state]`
- `ThreadMessagesNotifier extends Notifier<List<Message>>`: dữ liệu phái sinh (`_pinned`, `_reactionSummaries`, `_historyLoaded`, `myAcsUserId`) nằm ngoài state, widget phải đọc qua getter + notifier tự clone list để báo rebuild. Nên dùng 1 state class immutable (vd `ThreadState`) chứa tất cả.

### 23. Provider "throw UnimplementedError" chờ override
- `thread_providers.dart:148-149`: `roomIdProvider`/`threadIdProvider` tạo kiểu `throw UnimplementedError()` rồi `overrideWithValue` trong screen. Hoạt động nhưng là anti-pattern dễ vỡ (quên override = crash runtime); `.family` rõ ràng hơn.

### 24. Xin quyền thư viện ảnh ngay khi mở màn chat
- `message_input.dart:58-64`: `PhotoManager.requestPermissionExtend()` fire-and-forget trong `initState` — permission dialog hiện ra trước khi người dùng có nhu cầu gửi ảnh.

### 25. Unused import / nghi vấn dead import
- `conversation_list_screen.dart:15` import `thread/presentation/providers/thread_providers.dart` nhưng màn hình không dùng symbol nào của thread (chỉ xuất hiện trong comment :93). Cần `flutter analyze` xác nhận toàn bộ.

### 26. `NativeRealtimeDataSourceImpl.watchListMessages` nhận `roomId` nhưng không dùng
- Interface + use case + repo đều truyền `roomId` (`watch_list_messages_usecase.dart:8`, `message_repository_impl.dart:293`) nhưng impl bỏ qua — API surface đánh lừa người đọc.

---

## P3 — Testing, hiệu năng, quy trình

### 27. Coverage test rất thấp (~5% dòng, thiếu toàn bộ nghiệp vụ chính)
- Tổng test: ~1.028 dòng. `chat_core` có 4 file test (auth token, message, repository cache, group conversation). `chat_ui` chỉ test `chat_navigator`, `last_message_preview`, `rich_message_text` — **0 test cho mọi notifier/screen/widget chính** (thread messages, conversation list, message input...). Vi phạm rule 7.1.

### 28. Không có CI check kiến trúc
- Melos có script analyze/test/format nhưng không có rule cấm import ngược tầng (vd cấm `package:flutter` trong chat_core, cấm features import chéo) — đang giữ bằng kỷ luật, không bằng tool.

### 29. `dart format` chưa chắc đồng bộ
- Chưa thể chạy `melos run format` trong môi trường review (sandbox); cần xác nhận CI xanh. Một số dòng code vượt 80 ký tự do chuỗi dài (chấp nhận được với Dart formatter).

### 30. Hiệu năng build của `thread_screen`
- `build()` lọc `visibleMessages` bằng `where` + tính title/avatar + log payload trên **mỗi rebuild** (O(n) mỗi frame rebuild khi có tin mới/typing). Nên đẩy filtering xuống notifier (derived state) hoặc memoize.

---

## Đã sửa trong đợt này (không tính vào issue tồn đọng)
- ✅ Preview tin nhắn realtime ở danh sách phòng hiển thị `SenderName : Content` khớp format API (`conversation_list_notifier.dart`, helper `_formatLastMessageContent`).

