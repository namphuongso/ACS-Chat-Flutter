# Code Review — Chat Module (ACS-Chat-Flutter)

> Người review: Codex agent · Ngày: 2026-08-21
> Căn cứ: source `chat-module-mvp/`, `Project-guildline_and_structure_chat.md`, `CLEAN_CODE_RULES.md`.
> Danh mục lỗi chi tiết (kèm mức độ) xem trong `issue.md` — các mã issue (#1..#30) được tham chiếu bên dưới.

---

## 1. Đánh giá tổng quan

Kiến trúc tổng thể **đúng tinh thần Clean Architecture** và được giữ kỷ luật ở những chỗ khó nhất:
`chat_core` hoàn toàn không import Flutter (dependency rule sạch), domain entities không dính JSON,
use case chuẩn pattern `call()`, datasource luôn có interface + Impl, cache-first + offline fallback được
thiết kế có chủ đích với doc comment giải thích "tại sao" rất tốt (đặc biệt ở `MessageRepositoryImpl`,
`HiveIdentityStore`, `AuthTokenRepositoryImpl`).

Vấn đề tập trung ở **tầng Presentation**: các file UI phình to (4 file > 1.000 dòng), business logic rò
vào Screen, 2 feature chính import chéo nhau, và một số bug hành vi còn sót (issue #1, #2, #3). Điểm yếu
hệ thống thứ hai là **testing**: mọi luồng nghiệp vụ chính chưa có test (#27).

Xếp hạng sức khoẻ: `chat_core` 7.5/10 · `chat_ui` 5/10 · testing 3/10 · docs 6/10 (drift).

---

## 2. Điểm tốt cần giữ

- **Dependency rule được tôn trọng tuyệt đối**: không có `package:flutter` nào trong `chat_core`; không `// ignore` lint; không `print()` (dùng `developer.log`/`ChatLogger`).
- **Doc comment chất lượng cao**: nhiều chỗ giải thích bug lịch sử và quyết định thiết kế (vd comment về timeout 20s trong `_loadHistory`, comment về self-reference future trong `AuthTokenRepositoryImpl`) — rất có giá trị cho người sau.
- **Cache-first + offline degradation** nhất quán giữa conversation và message.
- **Realtime qua broadcast controller + reconnect/backoff/heartbeat/auth-expire** xử lý khá đầy đủ trong `NativeRealtimeDataSourceImpl`.
- **Pattern enum mở `MessageType`** đúng chuẩn tương thích ngược như CLEAN_CODE_RULES yêu cầu.
- `ChatUiConfig` là hướng đi đúng cho theming (chỉ chưa phủ đủ — #21).

---

## 3. Review chi tiết theo layer

### 3.1 chat_core (Domain + Data)
- **Domain:** entities immutable sạch, use case 1-trách nhiệm. Trừ một vết nhơ: text sự kiện hệ thống tiếng Việt được sinh ngay trong `MessageModel.fromAcsJson` (#13) — data model đang làm việc của presentation (render text nghiệp vụ).
- **Data:** datasource/repository phân vai rõ. `MessageRepositoryImpl` hợp lý khi đứng giữa remote + realtime + local. `NativeRealtimeDataSourceImpl` làm quá nhiều việc trong 1 class (708 dòng, ~15 nhánh event #17), và mang 2 tham số constructor chết + 1 tham số `roomId` không dùng ở `watchListMessages` (#16, #26).
- **Barrel file** export cả data models → UI dễ "đi tắt" lấy type tầng Data (#10).
- **PollingEngine** viết bài bản (jitter, backoff) nhưng không còn được dùng → dead code có điều kiện (#16).

### 3.2 chat_ui (Presentation)
- **Riverpod dùng đúng paradigma** (Notifier, override scope theo screen, autoDispose), nhưng state shape `List<Message>` + dữ liệu phái sinh ngoài state khiến notifier phải hack rebuild `state = [...state]` (#22).
- **Business logic phân tán:** flow pin (optimistic + rollback + toast) viết 2 bản trong 2 Screen thay vì trong Notifier (#9); `_togglePin` của room có thêm logic thay thế tin ghim khi đủ 3 cũng nằm trong Screen.
- **Coupling feature:** conversation_list ⇄ thread import provider lẫn nhau, thread notifier mutate state của conversation list (#8).
- **Widget tổ chức chưa đúng rule 4.3:** 18 helper `_build*` (#18), 5 widget class nhồi 1 file `message_bubble.dart` (#17), screen chứa inline sheet/dialog hàng trăm dòng (`_showMessageActionsSheet`, `_showPinnedMessagesSheet`, search UI...) (#17).
- **Bug trong build:** log payload participants mỗi rebuild (#3), lọc visibleMessages O(n) mỗi rebuild (#30).
- **Debug hack:** filter content "Thái Đăng" (#2) — cần xoá trước nhất.

### 3.3 Package khác & workspace
- `chat_native_platform_interface`: không còn được dùng sau khi realtime chuyển WebSocket (#16).
- `example/`: chỉ có thư mục `android/`, không có app Dart chạy được.
- Document drift: `read_status`, `shared/` trong guideline không tồn tại thực tế (#15).

---

## 4. Gợi ý refactor — danh sách file và nội dung

> Nguyên tắc: tách file không đổi hành vi trước; bug (#1, #2, #3) sửa độc lập, không trộn vào refactor.

### 4.1 `chat_ui/lib/features/thread/presentation/screens/thread_screen.dart` (2649 dòng → mục tiêu < 400)
**Tách thành các widget class riêng trong `widgets/`** (rule 4.3.2):
- `widgets/pinned_message_banner.dart` — banner tin ghim + indicator index.
- `widgets/pinned_messages_sheet.dart` — sheet danh sách tin ghim + `_PinnedMessageRow` (class này đã tách riêng file `pinned_message_row.dart`).
- `widgets/message_actions_sheet.dart` — sheet cảm xúc + menu thao tác tin nhắn (`_showMessageActionsSheet` ~400 dòng).
- `widgets/message_search_view.dart` — toàn bộ UI/logic search (`_isSearching`, `_searchResults`, jump-to-result).
- `widgets/scroll_to_bottom_button.dart` — nút cuộn xuống + badge unread.
- `widgets/upload_progress_banner.dart` — class `_UploadProgressBanner` hiện đã riêng class nhưng chung file.
- `widgets/upload_error_listener.dart` — tương tự.

**Chuyển logic ra khỏi Screen:**
- `_setMessagePin`/`_togglePin`/`_selectPinnedMessageToReplace` → vào `ThreadMessagesNotifier` (method `togglePin(messageId)` + `replacePin(...)`), Screen chỉ gọi notifier + nghe kết quả để toast (#9).
- `_isCurrentUserCurrentlyRemoved`, `_isSameUser`, `_normalizeAcsId`, `_getSenderAvatar` → util chung (mục 4.6).
- Lọc `visibleMessages` + tính `displayTitle/displayAvatar` → xuống notifier (derived state) để tránh O(n) mỗi rebuild (#30).
- **Xoá** block `ChatLogger.logRequest('PARTICIPANTS PAYLOAD...')` trong `build()` (#3).

### 4.2 `chat_ui/lib/features/thread/presentation/notifiers/thread_messages_notifier.dart` (1390 dòng → mục tiêu < 500)
**Tách trách nhiệm:**
- `thread_state.dart` — state class immutable `ThreadState { messages, pinned, reactions, historyLoaded, myAcsUserId, hasMore, isLoadingOlder }` thay `List<Message>` + field rời; xoá hack `state = [...state]` (#22).
- `thread_reactions_service.dart` (hoặc mixin) — `getReactionConfigs`, `refreshReactions`, `reactMessage`.
- `message_media_upload_service.dart` — `sendImages`/`sendFiles`/`sendVideos` + `_reportUploadFailures` (upload orchestration không phải việc của notifier tin nhắn).
- `system_event_presenter.dart` — gom `_appendSystemSignalMessage` + toàn bộ logic sinh câu tiếng Việt cho realtime signal; **dùng chung 1 nguồn text** với history (mục 4.5) (#13).
- Xoá filter `'Thái Đăng'` và filter chuỗi `'Bạn đã bị xóa khỏi phòng'` (thay bằng check `eventType == 'MemberRemoved' && isSelf` trong metadata) (#2).
- Thêm cận trên cho `loadUntilMessage` (vd max 20 page hoặc timeout 10s) (#5).
- Đổi `developer.log` → `ChatLogger` (12 chỗ) (#19).

### 4.3 `chat_ui/lib/features/thread/presentation/widgets/message_bubble.dart` (1350 dòng, 5 class → 1 file = 1 class)
- `message_bubble.dart` — chỉ giữ `MessageBubble`.
- `media_content.dart` — class `_MediaContent` → `MediaContent` (grid ảnh/video).
- `video_message_content.dart` — `_VideoMessageContent` (+ `_buildBody`/`_buildErrorBody` thành method nội bộ của nó hoặc tách `video_error_view.dart`).
- `link_preview_card.dart` — `_LinkPreviewCard`.
- Tách tiếp 6 helper `_build*` còn lại (`_buildFileList`, `_buildImageGrid`, `_buildSingleImage`, `_buildSystemMessageText`...) thành widget class: `file_list_section.dart`, `image_grid.dart`, `system_message_text.dart` (#18).
- Nhận diện media-only bằng metadata, bỏ so chuỗi `'[Hình ảnh]'/'[Video]'` (#7).

### 4.4 `chat_ui/lib/features/thread/presentation/widgets/message_input.dart` (1018 dòng)
- Tách `gallery_panel.dart` (`_buildGalleryPanel`), `gallery_permission_view.dart` (`_buildGalleryDeniedView`), `pick_more_tile.dart` (`_buildPickMoreTile`), giữ `attachment_panel.dart` cho khung chọn loại file.
- Chuyển permission request từ `initState` sang khi user mở gallery lần đầu (#24).
- Gom state gallery (7 biến rời) vào 1 object `GalleryState` + cân nhắc dùng_notifier nhỏ nếu logic phức tạp thêm.

### 4.5 Hệ thống text sự kiện + i18n (#13)
- Tạo `chat_ui/lib/features/shared/presentation/text/system_message_text.dart` (hoặc bước đầu `chat_strings.dart`): 1 nơi duy nhất sinh câu cho sự kiện nhóm (join/leave/remove/role/transfer/pin/room update) dùng chung cho **history** lẫn **realtime**.
- `MessageModel.fromAcsJson` (chat_core) chỉ map dữ liệu thô vào `metadata`; việc sinh câu chuyển sang builder ở 4.5 → chat_core hết string UI.
- Về dài hạn: áp `flutter_localizations`/`intl` cho toàn bộ chuỗi UI (toast, dialog, placeholder).

### 4.6 Util chung & phá coupling feature (#8, #14)
- `chat_core/lib/core/utils/acs_user_utils.dart`: `normalizeAcsId(String)`, `isSameAcsUser(String, String)` — thay 3 bản copy.
- Chuyển `watchListMessagesUseCaseProvider`/`stopWatchingListMessagesUseCaseProvider` và provider identity/shared từ `thread_providers.dart`/`conversation_providers.dart` sang `features/shared/presentation/providers/realtime_providers.dart`; cả 2 feature chỉ import `shared` → triệt tiêu import chéo.
- `updateRoomParticipants` nên là event từ shared (vd stream/participants provider) thay vì thread notifier với tay sửa state conversation list.
- Sửa import ngược: chuyển `ChatNavigator.openThread` thành constructor helper hoặc đặt trong `features/thread/` (core không import feature) (#11).

### 4.7 `chat_ui/lib/features/conversation_list/presentation/notifiers/conversation_list_notifier.dart`
- Nhánh room-tồn-tại của `_onNewMessage`: gọi lại logic sort (dùng chung với `updateLastMessage`) để đẩy phòng lên đầu (#1).
- Thay `ConversationSummaryModel` bằng `ConversationSummary` (entity) (#10); bỏ import data model khỏi UI.
- Bật realtime cả khi danh sách rỗng (bỏ guard `firstRoom == null`, hoặc chỉ guard khi `ref` chưa ready) (#6); cân nhắc bỏ tham số `roomId` khỏi `watchListMessages` ở cả 3 tầng (#26).
- Flow `_togglePin` của `conversation_list_screen.dart` chuyển vào notifier (#9).

### 4.8 `chat_ui/lib/features/thread/presentation/screens/room_settings_screen.dart` (965 dòng)
- 6 helper `_build*` → 6 widget class trong `widgets/`: `room_header.dart`, `member_row.dart`, `room_quick_actions.dart`, `group_info_rows.dart`, `direct_room_options.dart`, `danger_zone_section.dart` (#18).
- Flow đổi tên/ảnh đại diện/rời nhóm dùng use case qua 1 `RoomSettingsNotifier` riêng thay vì gọi use case trực tiếp từ screen.

### 4.9 `chat_ui/lib/features/thread/presentation/screens/room_resources_category_screen.dart` (814 dòng)
- 3 tab class `_MediaResourceTab`/`_FileResourceTab`/`_LinkResourceTab` → 3 file riêng trong `widgets/` (`media_resource_tab.dart`...), helper `_buildItemThumbnail` → `resource_item_thumbnail.dart`.

### 4.10 chat_core — dọn dẹp datasource (#16, #17, #26)
- `native_realtime_datasource_impl.dart`: bỏ tham số `platform`/`authTokenRepository` chết (breaking có kiểm soát, cập nhật MIGRATION_GUIDE_V2); tách `_handleRoomEvent` thành `room_event_mapper.dart` (map event JSON → signal `MessageModel`), class impl chỉ còn connect/reconnect/dispatch.
- Xoá hoặc deprecate package `chat_native_platform_interface`; nếu giữ phải có `@Deprecated` + doc.
- Đánh giá xoá `PollingEngine` + `MessageRemoteDataSourceImpl.watchNewMessages` nếu không còn kế hoạch dùng.
- `chat_core.dart`: ngừng export data models (chỉ export domain + use case + interfaces; data model là chuyện nội bộ của DI wiring).

### 4.11 Theming (#21)
- Mở rộng `ChatUiConfig` phủ đủ các vị trí đang fallback `Colors.*` (badge unread, divider, search result highlight, video error bg...); thay 51 chỗ `Color(0x...)` bằng token. Cân nhắc thêm `ChatSpacing`/`ChatRadius` constants.

### 4.12 Testing (#27) — ưu tiên theo rủi ro
1. `thread_messages_notifier_test.dart`: merge history/cache, isMe identification, pin toggle + rollback, delete (bỏ ghim trước khi xoá), `loadUntilMessage` cận trên.
2. `conversation_list_notifier_test.dart`: `_onNewMessage` các nhánh (tin thường, room mới, disband, kick, pin update, **đẩy lên đầu** sau khi fix #1), unread count.
3. `room_event_mapper_test.dart` (sau khi tách 4.10): mỗi loại eventType → đúng signal.
4. Widget test cho `MessageBubble` (media-only, deleted, system) và `LastMessagePreview` (đã có).
5. Mục tiêu ngắn hạn: mọi notifier chính có test; giữ CI `melos analyze/test/format` bắt buộc.

### 4.13 Docs & workspace (#15)
- Cập nhật `Project-guildline_and_structure_chat.md`: bỏ `read_status`/`shared` (hoặc tạo nếu định làm), ghi nhận pattern "local datasource interface ở chat_core, Hive impl ở chat_ui do cần Flutter binding", bổ sung cấu trúc `core/widgets`, `core/utils` của chat_ui.
- Tạo lại `example/lib/main.dart` tối thiểu để chạy melos workspace đúng nghĩa.
- (Tuỳ chọn) Thêm rule kiến trúc (enforcement): custom lint hoặc script grep trong melos cấm `package:flutter` trong chat_core và cấm import chéo feature.

---

## 5. Lộ trình đề xuất

| Đợt | Nội dung | Rủi ro | Ước lượng |
|---|---|---|---|
**Đợt 1 — Sửa bug (không refactor)** | #2 xoá filter "Thái Đăng"; #3 xoá log trong build; #1 đẩy phòng lên đầu; #7 nhận diện media bằng metadata; #5 cận trên `loadUntilMessage`; #4 gate log theo debug | Thấp | 0.5–1 ngày
**Đợt 2 — Util & phá coupling** | 4.6 (acs_user_utils, realtime về shared, sửa import core→feature), 4.7 (notifier danh sách) | Thấp–TB | 1–2 ngày
**Đợt 3 — Tách UI** | 4.1, 4.3, 4.4, 4.8, 4.9 (tách file 1-1, giữ hành vi) | TB (cần test thủ công màn chat) | 3–4 ngày
**Đợt 4 — Notifier & state** | 4.2 (ThreadState + services), 4.5 (system text + i18n bước đầu) | TB–Cao | 2–3 ngày
**Đợt 5 — Dọn chat_core + theme + test** | 4.10, 4.11, 4.12, 4.13 | Thấp | 2–3 ngày

Mỗi đợt kết thúc bằng: `melos run analyze && melos run format && melos run test` + test thủ công 4 luồng chính (mở room, gửi/nhận tin, ghim, danh sách phòng realtime).

---

## 6. Tóm tắt điều hành

- **Sửa ngay (P0):** filter "Thái Đăng" (#2), log PII trong build (#3),(room không lên đầu) (#1).
- **Refactor lớn nhất:** `thread_screen.dart` và `thread_messages_notifier.dart` — tách widget class + đưa pin/search/upload logic về đúng tầng.
- **Kiến trúc:** phá import chéo 2 feature bằng cách nâng realtime/identity lên `shared/`; ngừng export data models qua barrel.
- **Chất lượng dài hạn:** i18n tập trung, theme tokens, và test phủ toàn bộ notifier.
