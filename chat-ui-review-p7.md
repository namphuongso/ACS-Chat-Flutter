# Code Review `chat_ui` – P7

Phạm vi review: `chat-module-mvp/packages/chat_ui` theo tiêu chí trong `review/prompt.md`.

> Lưu ý: đã thử chạy `flutter analyze` trong package `chat_ui`, nhưng Flutter SDK muốn ghi cache ngoài workspace và sandbox chặn quyền ghi. Yêu cầu chạy escalated cũng không được auto-review chấp nhận, nên phần dưới dựa trên review thủ công source code.

## Tóm tắt nhanh

`chat_ui` đã có nền tảng khá tốt: dùng Riverpod, có use case/repository từ `chat_core`, có cache Hive, có dispose một số subscription/controller, có optimistic message và một số test cho utility/widget nhỏ. Tuy nhiên package hiện chưa thật sự “production-ready SDK UI” vì còn các vấn đề chính:

- UI package đang tự dựng data source/repository concrete từ `chat_core_impl`, làm public UI bị coupling trực tiếp với backend/ACS/WebSocket implementation.
- `ThreadMessagesNotifier` và các screen lớn đang chứa quá nhiều responsibility: identity, token/join-room, cache, realtime, pagination, pin, reaction, media, system event enrichment, read receipt.
- Một số API public được khai báo nhưng không được sử dụng (`messageBubbleBuilder`, `inputBuilder`), khiến khả năng custom UI không đúng cam kết.
- Có race condition thực tế trong contact search có thể kẹt loading vĩnh viễn.
- Có nhiều hidden network calls, duplicate calls, swallowed errors và async UI paths thiếu mounted guard.
- Test coverage hiện rất mỏng so với phần rủi ro nhất: realtime, pagination, lifecycle, upload, contact search, config customization.

## Đánh giá kiến trúc

### Separation of Concerns

Hiện tại boundary giữa UI/state/domain/data chưa rõ:

- `shared_providers.dart` import cả `chat_core.dart` và `chat_core_impl.dart`, sau đó tự tạo `AuthTokenRemoteDataSourceImpl`, `ConversationRemoteDataSourceImpl`, `MessageRemoteDataSourceImpl`, `WebSocketRealtimeDataSourceImpl` và repository impl.
- `ThreadMessagesNotifier` không chỉ quản lý state mà còn điều phối join-room/token, cache disk, realtime stream, enrich system message, pin/reaction, read receipt, link preview, upload delegation.
- `RoomSettingsScreen`, `RoomMembersScreen` gọi use case trực tiếp từ widget và tự quản lý dialog/loading/error.
- `MessageInput` vừa là input UI vừa xử lý permission, file picker, temp file, HEIC conversion, gallery state.

Hệ quả: khó mock, khó test lifecycle, khó thay backend/ACS implementation, và bug realtime/cache thường phải debug xuyên nhiều layer.

### Folder/module structure

Package có chia theo `features/*/presentation`, nhưng thiếu layer application/controller rõ ràng và phần data composition nằm trong UI providers. Một cấu trúc ổn hơn cho library SDK:

```text
lib/
├── chat_ui.dart                  # public API ổn định, chỉ export facade/widgets/config
└── src/
    ├── core/                     # config/theme/navigation/common widgets
    ├── application/              # controllers/notifiers/use-case orchestration
    ├── domain/                   # UI-facing abstractions/interfaces nếu cần
    ├── presentation/             # screens/widgets only
    └── infrastructure/           # optional default bindings/cache adapters, internal
```

Với hướng SDK, nên có `ChatUiScope`/`ChatDependencies` để host inject repository/usecase hoặc default implementation; UI package không nên export/khóa chặt provider implementation nội bộ.

## Findings ưu tiên

### P0/P1 – Cần xử lý trước khi production

#### 1. Contact search có race condition làm kẹt loading

- Evidence: `contact_list_notifier.dart:57` bắt đầu `loadContacts`, lưu `requested = state.keyword`, set `isLoading = true`; nếu user gọi `search()` ở `contact_list_notifier.dart:123` trong lúc request cũ đang chạy, `loadContacts()` mới return sớm vì `state.isLoading`; request cũ về thấy keyword đã đổi và return tại `contact_list_notifier.dart:73` mà không reset `isLoading`.
- Impact: danh bạ có thể kẹt skeleton/loading, search mới không chạy, UX bị dead-end.
- Recommendation: dùng request sequence/cancel token; trong `finally` luôn reset loading nếu request còn active; cho phép search mới supersede request cũ thay vì return khi `isLoading`.

#### 2. Public customization API bị khai báo nhưng không wired

- Evidence: `ChatUiConfig` khai báo `messageBubbleBuilder` và `inputBuilder` tại `chat_ui_config.dart:168` và `chat_ui_config.dart:172`.
- Evidence: trong `thread_screen.dart:1351` luôn dựng `MessageBubble` trực tiếp; `thread_screen.dart:1479` luôn dựng `MessageInput` trực tiếp. `rg` chỉ thấy hai builder xuất hiện trong config, không có nơi sử dụng.
- Impact: host app tin rằng có thể custom bubble/input nhưng runtime không có tác dụng; đây là breaking API/SDK trust issue.
- Recommendation: tạo `defaultBubble`/`defaultInput` rồi gọi builder nếu khác null; bổ sung widget tests xác nhận builder được gọi.

#### 3. UI package coupling trực tiếp với backend/ACS implementation

- Evidence: `shared_providers.dart:2` import `package:chat_core/chat_core_impl.dart`; `shared_providers.dart:29`, `shared_providers.dart:42`, `shared_providers.dart:57`, `shared_providers.dart:62`, `shared_providers.dart:66` tự dựng remote data source, realtime data source và repository impl.
- Evidence: `contact_providers.dart:2` import `chat_core_impl.dart`; `contact_providers.dart:10` tự dựng `ContactRemoteDataSourceImpl`.
- Impact: `chat_ui` không còn là presentation library độc lập; host app khó thay transport, mock repository, thay cache policy, hoặc test UI mà không kéo backend/WebSocket concrete.
- Recommendation: export API injection chính thức (`ChatUiDependencies`, provider overrides documented); default implementation đặt sau facade/internal module, không để screen/notifier phụ thuộc impl.

#### 4. `ThreadMessagesNotifier` là god object và có side-effect trong `build()`

- Evidence: file dài 1,240 dòng; `build()` tại `thread_messages_notifier.dart:101` watch nhiều dependency, resolve identity, mở realtime subscription tại `thread_messages_notifier.dart:155`, đăng ký dispose tại `thread_messages_notifier.dart:262`, rồi fire `_loadHistory`, `_loadPinnedMessages`, `refreshReactions`, `_fetchMembersIfNeeded` qua microtask tại `thread_messages_notifier.dart:267`.
- Impact: khó reasoning lifecycle; khi dependency/provider rebuild có nguy cơ đăng ký subscription hoặc microtask nhiều lần; logic khó unit test; state transition dễ race giữa cache/remote/realtime/pin/reaction.
- Recommendation: tách thành `ThreadController` nhỏ + services: `IdentitySession`, `MessageHistoryController`, `RealtimeThreadController`, `ReadReceiptController`, `PinnedMessageController`, `ReactionController`.

#### 5. Read receipt có thể bị gọi dư và không có de-dupe/error handling

- Evidence: `sendReadMessageIfNeeded()` chọn last non-system message rồi gọi `_messageRepository.sendReadMessage` tại `thread_messages_notifier.dart:602`-`thread_messages_notifier.dart:612`.
- Evidence: được gọi sau realtime insert (`thread_messages_notifier.dart:250`), sau load remote (`thread_messages_notifier.dart:821`) và sau cache load (`thread_messages_notifier.dart:856`).
- Impact: mở room, nhận realtime hoặc load cache/remote có thể spam read receipt cùng một message; không await/catch nên lỗi bị mất hoặc báo vào zone không mong muốn tùy implementation.
- Recommendation: lưu `lastReadMessageIdSent`, throttle/debounce theo room, chỉ gửi khi message cuối không phải của mình và thread đang active/visible; await hoặc log lỗi có kiểm soát.

#### 6. Async UI path ở pinned message thiếu mounted guard sau `await`

- Evidence: trong `thread_screen.dart:1095` lấy `ScaffoldMessenger.of(context)`, sau đó `await notifier.loadUntilMessage(messageId: id)` ở `thread_screen.dart:1103`; sau await tiếp tục `ref.read`, `_scrollToMessage`, `messenger.showSnackBar`, và `setState` tại `thread_screen.dart:1123` mà không kiểm tra `mounted`/`context.mounted`.
- Impact: user rời màn hình trong lúc load history có thể gặp setState/use context sau dispose.
- Recommendation: sau mọi await trong handler UI phải `if (!mounted) return;`; không giữ `BuildContext`/messenger quá lâu nếu route có thể bị pop.

### P2 – Rủi ro cao, nên xử lý trong refactor gần

#### 7. Hidden API call để enrich metadata cho media realtime

- Evidence: khi realtime message là media placeholder và thiếu metadata, code gọi `_enrichMessageMetadata` tại `thread_messages_notifier.dart:252`-`thread_messages_notifier.dart:259`.
- Evidence: `_enrichMessageMetadata` gọi `_listMessagesUseCase(roomId, threadId)` mỗi lần tại `thread_messages_notifier.dart:295`-`thread_messages_notifier.dart:315`.
- Impact: nhiều ảnh/file gửi liên tiếp sẽ tạo nhiều request full page, có thể race và tốn quota; lỗi realtime payload bị workaround ở UI thay vì fix contract.
- Recommendation: sửa backend/WebSocket payload để có metadata; nếu chưa được, batch/debounce enrich theo room và cache in-flight request.

#### 8. Link preview nằm trong notifier và chặn luồng gửi tin

- Evidence: `sendMessage()` tự parse URL và gọi `LinkPreviewFetcher.fetch(...).timeout(1500ms)` tại `thread_messages_notifier.dart:1031`-`thread_messages_notifier.dart:1048`, lỗi bị swallow.
- Impact: gửi text có URL bị trì hoãn tối đa 1.5s; network ngoài backend bị hardcode ở UI state; host app không cấu hình được policy/privacy/cache.
- Recommendation: biến link preview thành optional service injected, chạy background sau khi gửi hoặc dùng backend enrichment; có cache và observable error/log.

#### 9. Upload service không có cancellation và có thể update provider sau dispose

- Evidence: `MessageMediaUploadService` upload tuần tự qua loop tại `message_media_upload_service.dart:55`, `message_media_upload_service.dart:158`, `message_media_upload_service.dart:248`; progress callback đọc provider trực tiếp tại `message_media_upload_service.dart:65`-`message_media_upload_service.dart:67` và finally clear progress tại `message_media_upload_service.dart:128`-`message_media_upload_service.dart:131`, `message_media_upload_service.dart:217`-`message_media_upload_service.dart:220`, `message_media_upload_service.dart:299`-`message_media_upload_service.dart:302`.
- Impact: rời room trong lúc upload có thể vẫn tiếp tục upload/gửi message hoặc throw khi `Ref` đã dispose; không có cancel/retry queue.
- Recommendation: thêm upload job controller có cancel token, kiểm tra `_ref.mounted` trong callbacks/finally, quản lý queue theo room và retry rõ ràng.

#### 10. Temp files tạo ra nhưng không được cleanup

- Evidence: `_resolvePickedFiles` ghi bytes vào `Directory.systemTemp` tại `message_input.dart:144`-`message_input.dart:148`; HEIC conversion cũng ghi temp jpg tại `message_input.dart:548`-`message_input.dart:551`.
- Impact: chọn file cloud/HEIC nhiều lần có thể phình storage tạm, nhất là app chat dùng lâu.
- Recommendation: tracking temp paths và delete sau upload success/fail/cancel; hoặc giao upload service ownership cleanup.

#### 11. Conversation realtime unread check có thể sai identity ACS

- Evidence: `_onNewMessage` trong `conversation_list_notifier.dart:101`-`conversation_list_notifier.dart:105` so sánh `message.senderId` với `currentUserId` trực tiếp.
- Impact: nếu realtime senderId là ACS user id còn currentUserId là app user id, tin do chính mình gửi từ thiết bị khác có thể bị tính unread. Thread notifier đã phải xử lý `myAcsUserId`, nhưng list notifier không có cùng logic.
- Recommendation: dùng identity resolver dùng chung app user id + ACS user id; đừng duplicate identity compare ở từng notifier.

#### 12. System message de-dupe key có thể drop nhầm event

- Evidence: `MessageStore.sortChronological` dùng key cho system message là `sys_${content}_${createdAt.minute}` tại `message_store.dart:28`-`message_store.dart:34`.
- Impact: hai system event khác nhau nhưng cùng content trong cùng phút sẽ bị merge mất một event; ngược lại event trùng cách nhau hơn 1 phút không được de-dupe.
- Recommendation: dùng stable server event id/message id/metadata id; nếu local-only thì thêm event type + actor + target + timestamp bucket nhỏ có kiểm soát.

#### 13. Import cycle/boundary ngược giữa shared và thread providers

- Evidence: `local_cache_providers.dart:7` import `thread_providers.dart` chỉ để lấy `currentUserIdProvider`; `thread_providers.dart:4` import `shared_providers.dart` và `thread_providers.dart:5` export lại shared providers; `shared_providers.dart:5` import `local_cache_providers.dart`.
- Impact: dependency direction khó hiểu, dễ phát sinh cycle khi thêm provider mới; developer mới khó biết source of truth của current user/cache.
- Recommendation: đặt `currentUserIdProvider` ở `features/shared/presentation/providers/current_user_provider.dart` hoặc core provider, rồi cả cache/thread import một chiều.

#### 14. Resource preview tạo request dư cho media

- Evidence: `roomResourcePreviewProvider` với category media gọi image page và video page tuần tự tại `thread_providers.dart:257`-`thread_providers.dart:276`.
- Impact: màn room settings/preview có thể tốn 2 request nối tiếp chỉ để lấy 3 item; latency cao hơn cần thiết.
- Recommendation: backend nên hỗ trợ query nhiều type hoặc “media”; nếu chưa, dùng `Future.wait` và cache preview theo room/category.

#### 15. Room/member management business logic nằm trong widget

- Evidence: `room_members_screen.dart` gọi trực tiếp `getMembersUseCase`, `addParticipantsUseCase`, `transferOwnershipUseCase`; `room_settings_screen.dart` gọi trực tiếp update/close/leave use cases và tự điều phối dialog/loading/error.
- Impact: khó test behavior không cần widget test; logic permission, loading, rollback, toast bị lặp và dễ không đồng nhất.
- Recommendation: tạo `RoomSettingsController`/`RoomMembersController` quản lý command state; widget chỉ render và dispatch action.

### P3 – Maintainability/API polish

#### 16. Public export đang lộ implementation detail

- Evidence: `chat_ui.dart:20`-`chat_ui.dart:27` export notifier/provider nội bộ (`ConversationListNotifier`, `conversation_providers`, `shared_providers`, `thread_providers`).
- Impact: consumer có thể phụ thuộc trực tiếp provider nội bộ, làm mọi refactor thành breaking change.
- Recommendation: chỉ export facade ổn định; nếu cần extension points, export interface/override tokens có versioning rõ.

#### 17. Error handling còn nhiều catch rỗng/swallow

- Evidence: `refreshReactions` catch rỗng tại `thread_messages_notifier.dart:93`-`thread_messages_notifier.dart:99`; `_fetchMembersIfNeeded` catch rỗng tại `thread_messages_notifier.dart:279`-`thread_messages_notifier.dart:289`; `_showCachedMessagesIfAny` catch rỗng tại `thread_messages_notifier.dart:829`-`thread_messages_notifier.dart:858`; nhiều UI actions cũng catch `_`.
- Impact: lỗi production khó trace; người dùng thấy UI không cập nhật nhưng logs/observability không đủ.
- Recommendation: chuẩn hóa `ChatErrorReporter`/`ChatLogger` với severity, room/thread context, và UI error state khi action user-facing fail.

#### 18. File/class size vượt ngưỡng maintainable

- Evidence: `thread_screen.dart` 1,680 dòng, `thread_messages_notifier.dart` 1,240 dòng, `room_settings_screen.dart` 942 dòng, `message_input.dart` 880 dòng.
- Impact: review khó, merge conflict cao, thay đổi nhỏ dễ ảnh hưởng feature khác.
- Recommendation: đặt budget file <300-500 dòng cho screen/controller; tách widget private, command controller, services; thêm lint/code owners cho feature critical.

## Đề xuất roadmap refactor

### Phase 1 – Fix correctness nhanh

1. Fix contact search race bằng request sequence/finally.
2. Wire `messageBubbleBuilder` và `inputBuilder`; thêm tests.
3. Thêm mounted guard sau await ở pinned/search/settings handlers.
4. De-dupe/throttle read receipt theo `lastReadMessageIdSent`.
5. Cleanup temp files sau upload và guard `_ref.mounted` trong upload callbacks.

### Phase 2 – Giảm coupling/lifecycle risk

1. Tách `ThreadMessagesNotifier` thành các controller/service nhỏ.
2. Tạo identity resolver dùng chung cho thread + conversation list.
3. Chuyển link preview/media metadata enrichment thành injected service có cache/batch.
4. Đưa room/member command logic ra khỏi widgets.
5. Tách provider composition default khỏi public UI API.

### Phase 3 – SDK hardening

1. Thiết kế `ChatUiScope`/`ChatDependencies` để host inject config, repos, logging, link preview, upload policy.
2. Thu hẹp exports trong `chat_ui.dart`; document stable public API.
3. Bổ sung observability: structured logs, error callbacks, analytics hooks cho network/realtime/upload.
4. Thêm integration tests/fake repositories cho realtime, pagination, offline/cache, upload cancel, room membership events.

## Test coverage nên bổ sung

- `ContactListNotifier`: search khi request cũ đang chạy không kẹt loading, stale result bị bỏ đúng.
- `ThreadMessagesNotifier`: realtime message de-dupe, `loadOlder`, `loadUntilMessage`, cache-first rồi remote merge, read receipt de-dupe.
- `ChatUiConfig`: `messageBubbleBuilder` và `inputBuilder` được gọi đúng và nhận `defaultBubble/defaultInput`.
- `MessageMediaUploadService`: partial failure, progress, cancellation/dispose, cleanup temp file.
- `ConversationListNotifier`: unread count với sender là ACS id/app id, room pin/reorder, member removed self.
- Widget tests cho pinned message tap sau dispose hoặc route pop trong lúc load history.

## Kết luận

`chat_ui` đang ở trạng thái MVP tốt để demo/internal usage, nhưng chưa nên coi là production-ready SDK cho nhiều app nếu chưa xử lý public API customization, lifecycle/realtime correctness và dependency injection boundary. Ưu tiên cao nhất là fix race/load stuck, wire API đã public, giảm coupling với `chat_core_impl`, và tách `ThreadMessagesNotifier` để kiểm soát state transition rõ ràng hơn.
