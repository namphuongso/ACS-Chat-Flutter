# Chat UI Package Code Review (`packages/chat_ui`)

> **Ngày review:** 2026-08-21  
> **Phạm vi review:** `packages/chat_ui` (~14.657 LOC, 59 files: 31 dòng barrel, 1.488 dòng core/utils/widgets, 725 dòng conversation_list, 579 dòng contact, 471 dòng shared/local cache, 10.981 dòng thread screens/notifiers/widgets, 342 dòng test).  
> **Tiêu chuẩn review:** Theo `review/prompt.md` (Senior Flutter Architect / SDK Engineer & Code Reviewer).  
> **Bản chất package:** Flutter UI & Presentation Layer package (phụ thuộc `chat_core`, `flutter_riverpod`, `hive_flutter`, `video_player`, `photo_manager`, `file_picker`, `scrollable_positioned_list`).

---

## 1. Executive Summary

| Tiêu chí | Điểm | Nhận xét chi tiết |
|---|:---:|---|
| **Architecture** | **6.0/10** | Cấu trúc phân theo feature tương đối rõ ràng; tuy nhiên xuất hiện "God Classes" nguyên khối rất lớn (`ThreadScreen` 2.264 dòng, `ThreadMessagesNotifier` 1.580 dòng, `MessageInput` 852 dòng). Class `ThreadState` định nghĩa đầy đủ nhưng bị bỏ hoang, notifier quay về dùng `Notifier<List<Message>>` kèm các biến mutable rời rạc và hack `state = [...state]`. |
| **Maintainability** | **5.5/10** | Logic xử lý tin nhắn hệ thống, phân tích cú pháp sự kiện phòng, giải quyết danh tính người dùng và định dạng văn bản bị lặp lại ở nhiều file (`ThreadMessagesNotifier`, `ThreadScreen`, `MessageBubble`), gây khó khăn lớn khi backend thay đổi schema. |
| **Readability** | **6.5/10** | Code viết sạch, comment tiếng Việt chi tiết cho các ca vá lỗi thực tế; tuy nhiên logic render lồng ghép quá nhiều điều kiện (`_isCurrentUserCurrentlyRemoved`, `getSenderKey`, `_isSameUser`) trực tiếp trong phương thức `build()`. |
| **Performance** | **5.5/10** | Render danh sách tin nhắn dùng `ScrollablePositionedList` đảo chiều tốt; nhưng bị nghẽn Main Isolate do giải mã kích thước ảnh thô (`instantiateImageCodec`), quét mảng toàn bộ tin nhắn $O(N)$ trong `build()`, và khởi tạo đồng thời hàng loạt `VideoPlayerController` để lấy thumbnail trong grid tài nguyên. |
| **API Efficiency** | **6.0/10** | Có cache local danh bạ và tin nhắn qua Hive; tuy nhiên tìm kiếm tin nhắn quét vét 8 trang liên tục không ngắt quãng, thiếu in-flight deduplication cho `getRoomReactions` và `getMembers`. |
| **Memory Safety** | **5.0/10** | **Rò rỉ bộ nhớ nghiêm trọng (P0/P1):** Bộ đệm tĩnh `_controllerCache` trong `VideoMessageContent` giữ vĩnh viễn các instance `VideoPlayerController` native mà không bao giờ dispose; `TapGestureRecognizer` tạo mới trong `RichMessageText.build()` không được giải phóng; listener của `ScrollController` bị gán lặp trong `didChangeDependencies`. |
| **Crash Safety** | **7.0/10** | Phòng thủ tốt với fallback giá trị mặc định và `mounted` check; rủi ro tiềm ẩn khi `DateTime.parse()` trên dữ liệu Hive lưu sai định dạng, `ThreadState.hashCode` vi phạm contract, và `late final _overrides` trong `_ThreadScreenState` không cập nhật khi widget rebuild. |
| **Testability** | **4.0/10** | Chỉ có 3 file test (~342 LOC, chiếm **~2.3%** codebase), chỉ test helper nhỏ (`RichMessageText`, `ChatDeepLinkData`, `LastMessagePreview`). Hoàn toàn không có Widget test, Notifier test, Media Upload test, hay Local Cache test. |
| **Extensibility** | **5.5/10** | Cung cấp `ChatUiConfig` để tùy biến màu sắc cơ bản; tuy nhiên văn bản giao diện và thông báo hệ thống bị hardcode tiếng Việt 100%, không hỗ trợ đa ngôn ngữ (i18n/l10n). |
| **UI Customizability** | **5.0/10** | Chỉ hỗ trợ tốt **Level A** (Dùng UI mặc định). Chưa hỗ trợ **Level B** (Custom từng phần qua Builder delegates như `messageBubbleBuilder`, `inputBuilder`, `appBarBuilder`). Cấu hình `onFileTap` trong `ChatUiConfig` bị bỏ quên (dead config). |
| **Public API Design** | **6.0/10** | `ChatNavigator` hỗ trợ Deep Link tiện lợi; nhưng việc quản lý `globalCurrentUserIdProvider` dùng state toàn cục dễ gây race condition khi ứng dụng chuyển đổi tài khoản hoặc mở song song nhiều thread. |
| **Production Readiness** | **5.5/10** | **⚠️ READY WITH MAJOR FIXES** (cho cả ứng dụng nội bộ lẫn xuất bản SDK). Cần xử lý dứt điểm các lỗi rò rỉ native controller và tối ưu hóa hiệu năng render. |

---

## 2. Architecture Assessment

```text
Host Application (e.g., Main App)
       │
       ▼ (Configures Theme, Tokens & Navigator)
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              packages/chat_ui                                   │
│                                                                                 │
│  [CORE & UTILS]                                                                 │
│  ├─ Config: ChatUiConfig (Colors, TextStyles, Callbacks)                        │
│  ├─ Navigation: ChatNavigator, ChatRouteObserver, ChatDeepLinkData              │
│  ├─ Shared Widgets: RichMessageText, SearchField, Skeleton, OfflineBanner      │
│  └─ Utilities: LinkPreviewFetcher, LastMessagePreview, AvatarUtils              │
│                                                                                 │
│  [SHARED INFRASTRUCTURE & LOCAL DATA]                                           │
│  ├─ Local Storage (Hive): HiveMessageLocalDataSource,                           │
│  │                        HiveConversationLocalDataSource, HiveIdentityStore    │
│  └─ Global Providers: currentUserIdProvider, connectivityProvider               │
│                                                                                 │
│  [FEATURE MODULES (Presentation / State / Widgets)]                             │
│  ├─ 📁 conversation_list: ConversationListScreen, ConversationListNotifier      │
│  ├─ 📁 contact: ContactListScreen, ContactListNotifier                          │
│  └─ 📁 thread (Chat Room Engine):                                               │
│       ├─ Screens: ThreadScreen (2.264 LOC), RoomSettingsScreen (790 LOC),       │
│       │           RoomMembersScreen, AddParticipantsScreen, RoomResourcesScreen │
│       ├─ Notifiers: ThreadMessagesNotifier (1.580 LOC)                         │
│       │             (Dead abstraction: ThreadState is unused!)                  │
│       └─ Widgets: MessageBubble, MessageInput (852 LOC), MediaContent,          │
│                   VideoMessageContent, ChatVideoPlayerDialog, GalleryPanel...   │
└─────────────────────────────────────────────────────────────────────────────────┘
       │
       ▼ (Pure Dart Domain Contract & Repositories)
packages/chat_core
```

### 2.1 Điểm mạnh kiến trúc (KEEP)

1. **Phân tách trách nhiệm tầng Presentation**: `chat_ui` tập trung vào rendering, gesture, animation, và quản lý widget lifecycle, không tự định nghĩa lại các business domain logic đã có trong `chat_core`.
2. **Offline-First UI & Cache Hydration**: Danh sách hội thoại và tin nhắn khôi phục tức thì từ Hive local box khi vừa mở màn hình (`_initFromCache`), sau đó mới fetch remote ngầm, mang lại trải nghiệm mượt mà không bị màn hình trắng/spinner chờ lâu.
3. **Optimistic UI Updates**: Các thao tác gửi tin nhắn, gửi cảm xúc (reaction), ghim tin nhắn và sửa nội dung tin đều áp dụng cập nhật lạc quan (Optimistic update) trên giao diện trước khi server phản hồi, có cơ chế rollback khi thất bại.
4. **Rich Message Rendering & Link Preview**: Hỗ trợ bóc tách cú pháp HTML đa dạng (thẻ b, i, u, s, font color, size, blockquote, danh sách ul/ol, code block) kết hợp tự động cào OpenGraph preview cho link web.
5. **Tiện ích Deep Link & Navigation đóng gói sẵn**: `ChatNavigator` và `ChatDeepLinkData` giúp host app dễ dàng trích xuất payload push notification (OneSignal/FCM) để mở thẳng phòng chat tương ứng.

---

### 2.2 Điểm yếu & Architectural Smells

#### A. Màn hình nguyên khối quá lớn (God Class Anti-Pattern)
- **Hiện trạng:**
  - `ThreadScreen.dart` dài tới **2.264 dòng code**.
  - `ThreadMessagesNotifier.dart` dài tới **1.580 dòng code**.
  - `MessageInput.dart` dài tới **852 dòng code**.
- **Vấn đề:** Trộn lẫn toàn bộ trách nhiệm: Quản lý WebSocket listener, tìm kiếm tin nhắn, quét lịch sử nền, render bottom sheet, xử lý quyền camera/gallery, giải mã kích thước ảnh, chuyển đổi HEIC, debounce typing, và hiển thị dialog.
- **Hệ quả:** Rất khó đọc, khó viết unit test/widget test độc lập, và nguy cơ gây hồi quy (regression bug) cao khi bảo trì.

#### B. Mô hình State bị phá vỡ — Class `ThreadState` bị bỏ hoang
- **Hiện trạng:** Trong `thread_state.dart`, team đã thiết kế một `ThreadState` bất biến (immutable) rất đẹp với đầy đủ `messages`, `pinnedMessages`, `reactionsMap`, `historyLoaded`, `myAcsUserId`, `hasMore`, `isLoadingOlder`, `cursor`. Tuy nhiên, `ThreadMessagesNotifier` lại kế thừa `Notifier<List<Message>>` thay vì `Notifier<ThreadState>`.
- **Hệ quả:** 
  1. Các trạng thái quan trọng (`_pinned`, `_reactionSummaries`, `myAcsUserId`, `_cursor`, `_isLoadingOlder`, `_hasMore`, `_historyLoaded`) trở thành các biến private mutable nằm rải rác bên trong Notifier.
  2. Khi danh sách reaction thay đổi (`refreshReactions`), notifier phải gọi lệnh hack `state = [...state]` chỉ để ép Riverpod phát tín hiệu rebuild cho UI!
  3. Vi phạm nguyên lý Single Source of Truth của State Management.

#### C. Trộn lẫn Logic sinh chuỗi hiển thị và Hardcoded tiếng Việt
- **Hiện trạng:** `ThreadMessagesNotifier._handleMemberEventSignal` (dòng 336–629) và `_enrichSystemMessageContent` (dòng 703–841) chứa hơn **400 dòng code** thao tác chuỗi thô để ghép các câu tiếng Việt như:
  - `'**$actorName** đã thêm **$targetNames** vào nhóm'`
  - `'**$actorName** đã chuyển quyền Trưởng phòng cho **$targetName**'`
  - `'Bạn đã bị xóa khỏi phòng'`
- **Hệ quả:**
  1. Duplicate logic với `chat_core` (`native_realtime_datasource_impl.dart` và `message_model.dart`).
  2. Hoàn toàn không thể đa ngôn ngữ hóa (i18n) khi host app cần phát hành cho thị trường quốc tế.

#### D. Tham số Cấu hình bị "Bỏ quên" (Dead Configuration)
- **Hiện trạng:** `ChatUiConfig.onFileTap` được định nghĩa công khai trong file cấu hình công cộng (`chat_ui_config.dart:157-163`) để host app tự xử lý khi người dùng chạm vào tệp đính kèm. Tuy nhiên, trong `MediaContent._handleFileAction` (`media_content.dart:114-144`), widget hoàn toàn không đọc hay kích hoạt `onFileTap`, mà luôn mở thẳng bottom sheet mặc định.

#### E. Sai sót trong việc quản lý Provider Overrides (`late final _overrides`)
- **Hiện trạng:** Trong `_ThreadScreenState` (`thread_screen.dart:52-57`):
  ```dart
  late final _overrides = [
    roomIdProvider.overrideWithValue(widget.roomId),
    threadIdProvider.overrideWithValue(widget.threadId),
    currentUserIdProvider.overrideWithValue(widget.currentUserId),
    threadMessagesProvider.overrideWith(ThreadMessagesNotifier.new),
  ];
  ```
- **Vấn đề:** Biến `_overrides` là `late final` gắn với State. Nếu widget cha rebuild và truyền vào `roomId` hoặc `threadId` mới, `_overrides` **không được cập nhật**, dẫn đến việc màn hình tiếp tục sử dụng provider của phòng chat cũ!

---

## 3. Critical Issues (P0 / P1)

### P0-1 — Rò rỉ Bộ nhớ Native & Cạn kiệt Hardware Decoder do Cache Tĩnh `VideoPlayerController`

```text
Issue: _controllerCache tĩnh trong VideoMessageContent giữ vĩnh viễn VideoPlayerController và không dispose
File: lib/features/thread/presentation/widgets/video_message_content.dart
Class: _VideoMessageContentState
Method: Toàn bộ class (thiếu dispose() và static cache vô hạn)
Severity: P0
Category: Memory Leak / Resource Leak / Native Crash

Current behavior:
Trong _VideoMessageContentState:
  static final Map<String, VideoPlayerController> _controllerCache = {};
  static final Map<String, Future<void>> _initFuturesCache = {};

Khi bong bóng video hiển thị:
1. Controller được khởi tạo qua VideoPlayerController.networkUrl(uri).
2. Khi initialize() xong, controller được lưu vào _controllerCache[cacheKey].
3. Class _VideoMessageContentState KHÔNG CÓ HÀM dispose()!
4. Listener _controller!.addListener(_onPlayerUpdate) không bao giờ được gỡ bỏ.

Problem:
Mỗi VideoPlayerController giữ một native texture buffer, hardware decoder session (MediaCodec trên Android, 
VTDecompressionSession trên iOS) và streaming socket.
Vì nằm trong static Map, các controller này sống vĩnh viễn suốt vòng đời của App ngay cả khi user đã back ra khỏi phòng chat.

Why it is dangerous:
1. Thiết bị di động chỉ hỗ trợ giới hạn từ 4 đến 8 hardware video decoder đồng thời. Khi user lướt qua 10 video trong nhóm chat, app sẽ chạm trần phần cứng -> crash đột ngột với lỗi:
   "MediaCodecVideoRenderer error" hoặc "ExoPlayerImplInternal: Playback error".
2. Chiếm dụng hàng trăm MB bộ nhớ RAM native không thể thu hồi bởi Garbage Collector.

Reproduction scenario:
1. Mở một nhóm chat có 10-15 tin nhắn video.
2. Cuộn từ dưới lên trên qua các tin nhắn video.
3. Thoát ra màn hình danh sách, mở lại nhóm chat và cuộn tiếp.
4. Kiểm tra Memory Profiler -> RAM tăng liên tục và video thứ 8 trở đi bị đen hình / ném ngoại lệ crash.

Recommended solution:
1. Xóa bỏ Map static _controllerCache vô hạn.
2. Không khởi tạo VideoPlayerController trực tiếp trong tin nhắn chat dạng danh sách! Thay vào đó chỉ hiển thị Ảnh đại diện Thumbnail (Video Thumbnail Placeholder) kèm nút Play.
3. Chỉ khi người dùng chạm vào video mới mở ChatVideoPlayerDialog toàn màn hình để khởi tạo 1 VideoPlayerController duy nhất và dispose() ngay khi đóng dialog.
```

---

### P1-1 — `TapGestureRecognizer` Tạo Mới Trong `build()` Không Được Giải Phóng Gây Rò Rỉ Gesture Arena

```text
Issue: TapGestureRecognizer được khởi tạo bên trong StatelessWidget.build() mà không được dispose()
File: lib/core/widgets/rich_message_text.dart
Class: RichMessageText
Method: _buildPlainTextWithLinks (dòng 544-551)
Severity: P1
Category: Memory Leak / Gesture Arena Leak

Current behavior:
  Widget _buildPlainTextWithLinks(String text, TextStyle baseStyle) {
    ...
    for (final match in matches) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () async { ... };
      spans.add(TextSpan(..., recognizer: recognizer));
    }
    return Text.rich(...);
  }

Problem:
Trong Flutter, GestureRecognizer (như TapGestureRecognizer) gắn vào TextSpan là đối tượng quản lý tài nguyên cấp thấp (Low-level Pointer Router). Nó KHÔNG tự động hủy khi Widget hủy. 
Mỗi lần ListView cuộn hoặc Widget rebuild (do state thay đổi, highlight, resize bàn phím), một loạt instance TapGestureRecognizer mới lại được tạo ra và đăng ký vào GestureArena mà các instance cũ không bao giờ được gọi dispose().

Why it is dangerous:
Gây rò rỉ bộ nhớ (GestureRecognizer leak) và làm nặng Event Dispatcher của Flutter Engine khi người dùng cuộn danh sách hàng ngàn tin nhắn chứa link URL.

Recommended solution:
Chuyển sang dùng StatefulWidget để quản lý vòng đời và dispose() các recognizer, hoặc sử dụng các widget chuyên dụng như SelectableText / Linkify đã được tối ưu dọn dẹp tài nguyên.
```

---

### P1-2 — Listener của `ScrollController` Bị Đăng Ký Lặp Nhiều Lần Trong `didChangeDependencies`

```text
Issue: _scrollController.addListener(_maybeLoadMore) được gọi trong didChangeDependencies thay vì initState
File: lib/features/conversation_list/presentation/screens/conversation_list_screen.dart
Class: _ConversationListState
Method: didChangeDependencies (dòng 66-73)
Severity: P1
Category: Performance / Lifecycle Bug / Duplicate Execution

Current behavior:
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      chatRouteObserver.subscribe(this, route);
    }
    _scrollController.addListener(_maybeLoadMore); // <-- Gọi mỗi khi dependencies thay đổi!
  }

Problem:
didChangeDependencies() trong Flutter có thể được gọi nhiều lần trong vòng đời của State (ví dụ: khi Theme thay đổi, Locale thay đổi, MediaQuery cập nhật do xoay màn hình/bật bàn phím, hoặc Route Observer kích hoạt).
Mỗi lần như vậy, một callback _maybeLoadMore lại được add thêm vào ScrollController. Khi dispose, lệnh _scrollController.removeListener(_maybeLoadMore) chỉ gỡ ĐÚNG 1 LẦN, để lại các listener trùng lặp trong bộ nhớ.

Why it is dangerous:
Khi người dùng cuộn danh sách, hàm `_maybeLoadMore()` và `loadMore()` bị kích hoạt đồng thời $N$ lần, dẫn đến việc bắn liên tiếp các request phân trang trùng lặp lên server.

Recommended solution:
Chuyển lệnh `_scrollController.addListener(_maybeLoadMore)` vào `initState()`.
```

---

### P1-3 — Giải mã Kích thước Ảnh Gốc Bằng `instantiateImageCodec` Gây Giật Frame Main Isolate

```text
Issue: Đọc toàn bộ byte ảnh vào RAM và gọi instantiateImageCodec trên Main Isolate khi gửi ảnh
File: lib/features/thread/presentation/notifiers/thread_messages_notifier.dart
Class: ThreadMessagesNotifier
Method: sendImages (dòng 1220-1224)
Severity: P1
Category: Performance / Main Thread Jank / High RAM

Current behavior:
  final bytes = await file.readAsBytes();
  final codec = await instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  width = frame.image.width;
  height = frame.image.height;

Problem:
1. Khi người dùng chọn gửi 5–10 ảnh chất lượng cao (mỗi ảnh 10–20MB từ camera), `file.readAsBytes()` nạp cùng lúc hàng trăm MB dữ liệu thô vào RAM.
2. `instantiateImageCodec` giải mã bitmap đầy đủ chỉ để lấy thông tin `width` và `height`.
3. Hàm này đã bị deprecate trong các phiên bản Flutter mới và chạy trực tiếp làm nghẽn Main Isolate.

Why it is dangerous:
Gây drop frame nghiêm trọng (UI bị đơ 1-2 giây ngay khi người dùng nhấn Gửi ảnh), đẩy RAM thiết bị tăng vọt và có thể bị hệ điều hành (nhất là iOS) kill app do Out Of Memory (OOM).

Recommended solution:
Sử dụng thư viện đọc metadata header nhẹ nhàng (như package `image_size_getter` chỉ đọc vài byte đầu của header EXIF/PNG/JPEG mà không giải mã toàn bộ ảnh), hoặc đưa tác vụ decode sang Background Isolate (`compute`).
```

---

### P1-4 — Gửi Tin Nhắn Bị Treo Đồng Bộ Tối Đa 4 Giây Do Cào Link Preview Trước Khi Render Optimistic

```text
Issue: LinkPreviewFetcher.fetch được await trước khi chèn tin nhắn optimistic vào state
File: lib/features/thread/presentation/notifiers/thread_messages_notifier.dart
Class: ThreadMessagesNotifier
Method: sendMessage (dòng 1120-1133)
Severity: P1
Category: UX / Latency / Performance

Current behavior:
  Future<void> sendMessage(String content, {Map<String, dynamic>? metaData}) async {
    var finalMetaData = metaData;
    if (finalMetaData == null) {
      final urlMatch = RegExp(r'(https?://[^\s<]+)').firstMatch(content);
      if (urlMatch != null) {
        final linkUrl = urlMatch.group(0)!;
        final previewData = await LinkPreviewFetcher.fetch(linkUrl); // <-- Block tối đa 4s!
        finalMetaData = previewData.toJson();
      }
    }
    final optimistic = Message(...);
    state = [...state, optimistic]; // <-- Chỉ hiện bubble sau khi đã fetch xong link!
    ...
  }

Problem:
Khi người dùng nhập một tin nhắn có chứa URL (ví dụ https://example.com) và bấm Gửi, Notifier phải chờ HTTP GET lấy HTML của trang web (với timeout lên tới 4 giây) rồi mới tạo tin nhắn `optimistic` hiển thị lên UI.

Why it is dangerous:
Phá vỡ nguyên lý phản hồi tức thì (Instant Feedback) của Optimistic UI. Người dùng bấm Gửi nhưng khung chat hoàn toàn bất động trong 2–4 giây khiến họ tưởng nút Gửi bị liệt và bấm liên tục tạo nhiều tin nhắn trùng lặp.

Recommended solution:
Chèn ngay tin nhắn `optimistic` vào `state` với nội dung text trước, sau đó fetch Link Preview bất đồng bộ ở background rồi cập nhật metadata sau.
```

---

### P1-5 — Tổng Số Lượng Tài Nguyên Phòng Chat Hiển Thị Sai Do Bị Cắt Cố Định $\le 6$

```text
Issue: roomResourcePreviewProvider tính totalCount dựa trên độ dài mảng đã bị cắt phân trang
File: lib/features/thread/presentation/providers/thread_providers.dart
Class: roomResourcePreviewProvider
Method: dòng 255-275 & room_resource_preview_section.dart dòng 123
Severity: P1
Category: Logic Bug / UI Inconsistency

Current behavior:
Trong thread_providers.dart:
  final imageResult = await useCase(..., pageSize: 3);
  final videoResult = await useCase(..., pageSize: 3);
  final total = imageResult.items.length + videoResult.items.length; // <-- Luôn <= 6!
  return RoomResourceGroupResult(items: previewItems, totalCount: total);

Trên giao diện RoomResourcePreviewSection:
  Text('Ảnh & video ($totalCount)')

Problem:
Mặc dù phòng chat có thể chứa hàng trăm ảnh và video, nhưng vì query preview truyền `pageSize: 3`, biến `totalCount` được tính bằng tổng số item của trang 1 ($3 + 3 = 6$), dẫn đến việc UI luôn hiển thị số lượng tối đa là `(6)` cho Media hoặc `(3)` cho Tệp/Link!

Recommended solution:
Sử dụng trường `totalCount` trả về từ Backend metadata của `MessageResourceList` thay vì lấy `.length` của mảng phân trang preview.
```

---

### P1-6 — `VideoResourceThumbnail` Khởi Tạo Đồng Thời Hàng Chục Native Video Controller Cho Grid Tài Nguyên

```text
Issue: Mỗi item thumbnail video trong GridView mở một VideoPlayerController độc lập
File: lib/features/thread/presentation/widgets/video_resource_thumbnail.dart
Class: _VideoResourceThumbnailState
Method: _initThumbnail (dòng 53-85)
Severity: P1
Category: Performance / Hardware Decoder Overload

Current behavior:
Khi mở màn hình xem danh mục Media ("Ảnh & Video" trong phòng), danh sách hiển thị dạng GridView.
Với mỗi video, widget `VideoResourceThumbnail` được tạo -> khởi tạo 1 `VideoPlayerController` kết nối mạng -> gọi `initialize()` -> gọi `seekTo(100ms)` để lấy khung hình đầu tiên làm ảnh đại diện.

Problem:
Khi cuộn GridView có 30 video, 30 controller video được kích hoạt mạng và mở hardware decoder cùng lúc.

Why it is dangerous:
Gây quá tải băng thông mạng, giật lag khung hình cực nặng khi cuộn và làm app bị crash do vượt quá số lượng hardware codec cho phép của hệ điều hành.

Recommended solution:
1. Backend khi upload video cần tự động trích xuất và lưu sẵn `thumbnailUrl` dạng ảnh tĩnh (JPEG/WebP) trên server.
2. Client chỉ load ảnh tĩnh bằng `Image.network()`. Tuyệt đối không dùng video player engine chỉ để render thumbnail.
```

---

### P1-7 — Vòng Lặp Polling `loadUntilMessage` Và Quét 8 Trang Nền Gây Tải Ảo Lên Backend

```text
Issue: Quét vét tự động 8 trang tin nhắn cũ (400 tin) mỗi khi tìm kiếm từ khóa
File: lib/features/thread/presentation/screens/thread_screen.dart
Class: _ThreadScreenContentState
Method: _performMessageSearch (dòng 282-308) & loadUntilMessage (dòng 1551-1578)
Severity: P1
Category: API Efficiency / Server Flooding / Network Abuse

Current behavior:
Khi người dùng tìm kiếm từ khóa trong phòng chat:
Nếu từ khóa không có trong trang tin nhắn hiện tại, code tự động chạy vòng lặp `while (pagesFetched < 8)` gọi liên tục 8 lần `loadOlder()` để kéo 400 tin nhắn cũ về nhằm tìm kiếm local trên client.

Problem:
Tìm kiếm nội dung tin nhắn là tác vụ của Backend (Search API có Indexing). Việc client tự kéo hàng loạt trang tin nhắn về máy để chạy `String.contains()` gây tốn băng thông nghiêm trọng và làm chậm thiết bị.

Recommended solution:
Tích hợp REST Search Messages API từ Backend thay vì kéo toàn bộ lịch sử thô về máy để duyệt thủ công.
```

---

## 4. API Efficiency & Network Review

### 4.1 Tổng hợp các điểm chưa tối ưu về API & Network

1. **Bộ đệm Link Preview không có giới hạn (`LinkPreviewFetcher._cache`)**:
   - `static final _cache = <String, LinkPreviewData>{};` lưu toàn bộ dữ liệu cào web trong RAM mà không có cơ chế giải phóng (LRU Cache, Max Size, hoặc TTL). Sau thời gian dài sử dụng, Map này sẽ phình to trong bộ nhớ.
2. **Gọi API lấy danh sách thành viên trùng lặp (`getMembers`)**:
   - Khi mở phòng chat, `ThreadMessagesNotifier._fetchMembersIfNeeded()` gọi `getMembers(roomId)`.
   - Ngay sau đó, nếu user bấm vào biểu tượng Info mở `RoomSettingsScreen`, hàm `_loadData()` lại gọi tiếp `getMembers(roomId)` lần thứ hai mà không tái sử dụng dữ liệu đã có từ thread.
3. **Mất Realtime sau khi Pause/Resume do gọi `leaveActiveRoom()`**:
   - Khi `ThreadScreen` vào trạng thái `paused`/`inactive`, hàm `didChangeAppLifecycleState` gọi `ref.read(messageRepositoryProvider).leaveActiveRoom()`.
   - Khi kết hợp với Bug P0-1 của `chat_core` (hàm này xóa sạch `_activeRoomIds`), khi app mở lại, kết nối WebSocket không thể tự vào lại phòng, khiến người dùng hoàn toàn không nhận được tin nhắn mới qua realtime.

---

## 5. Memory & Resource Lifecycle Issues

### 5.1 Ma trận Phân tích Vòng đời và Rò rỉ Tài nguyên (Leak Audit)

| Thành phần / Đối tượng | Nơi khởi tạo & Quản lý | Đánh giá & Rủi ro | Giải pháp khuyến nghị |
|---|---|:---:|---|
| **`VideoPlayerController` (Bong bóng chat)** | `VideoMessageContent._controllerCache` (Static Map) | ❌ **Rò rỉ nghiêm trọng (P0)**: Không bao giờ dispose, listener không được gỡ bỏ. | Xóa static cache, chuyển sang render ảnh tĩnh và chỉ mở player trong Dialog. |
| **`TapGestureRecognizer` (Link text)** | `RichMessageText._buildPlainTextWithLinks` | ❌ **Rò rỉ (P1)**: Tạo mới trong `build()` của StatelessWidget mà không dispose. | Chuyển sang StatefulWidget hoặc quản lý vòng đời recognizer. |
| **`ScrollController` Listener** | `ConversationListScreen.didChangeDependencies` | ⚠️ **Cảnh báo (P1)**: Gán lặp nhiều lần mỗi khi dependencies thay đổi. | Chuyển vào `initState()`. |
| **`LinkPreviewFetcher` Cache** | `LinkPreviewFetcher._cache` (Static Map) | ⚠️ **Cảnh báo (P2)**: Bộ đệm vô hạn không có dung lượng trần. | Thêm LRU eviction policy (giới hạn tối đa 100 URL gần nhất). |
| **`_userAvatarCache`** | `ThreadMessagesNotifier._userAvatarCache` | An toàn theo vòng đời Thread | Được tự động giải phóng khi Notifier dispose. |
| **`_itemPositionsListener`** | `ThreadScreen` | An toàn | Được `removeListener` đầy đủ trong `dispose()`. |
| **`_searchController` & `_focusNode`** | `ThreadScreen`, `SearchField` | An toàn | Được gọi `dispose()` đầy đủ. |

---

## 6. Crash & Reliability Issues

### 6.1 Bảng Kiểm tra An toàn Mã nguồn (Safety Audit)

| Vị trí / Đoạn mã | Hiện trạng | Mức độ rủi ro | Hướng xử lý |
|---|---|:---:|---|
| **`ThreadState.hashCode`** (`thread_state.dart:63-72`) | `reactionsMap` được so sánh trong `operator ==` nhưng **bị bỏ quên trong `hashCode`**. | ⚠️ Cảnh báo | Vi phạm hợp đồng đối tượng trong Dart (`a == b => a.hashCode == b.hashCode`). Bổ sung `Object.hashAll(reactionsMap.entries)`. |
| **`late final _overrides`** (`thread_screen.dart:52-57`) | Gán cố định một lần trong State. Không cập nhật khi widget cha truyền tham số mới. | ⚠️ Cảnh báo | Đưa việc cấu hình ProviderScope ra phương thức `build()` hoặc sử dụng `.family` providers. |
| **`DateTime.parse()` trong Hive Datasource** (`hive_message_local_datasource.dart:111`, `hive_conversation_local_datasource.dart:117`) | Ép kiểu `DateTime.parse(j['createdAt'] as String)`. Nếu dữ liệu lưu trong Hive bị lỗi cú pháp sẽ crash màn hình. | ⚠️ Cảnh báo | Thay thế toàn bộ bằng `DateTime.tryParse() ?? DateTime.now()`. |
| **`List.map().cast<String, dynamic>()`** (`thread_messages_notifier.dart:59`) | Giả định payload JSON từ WebSocket luôn có key String. Nếu gặp key int sẽ văng `TypeError`. | Thấp | Bọc an toàn với `Map<String, dynamic>.from(...)`. |
| **Mutate List sau gán State** (`thread_messages_notifier.dart:239-240`) | `state = [...state]; state[i] = ...;` (Gán state trước, sửa mảng sau). | Thấp | Sửa mảng trên bản copy trước: `final list = [...state]; list[i] = ...; state = list;`. |

---

## 7. UI Architecture & Customization Review

### 7.1 Đánh giá 3 Cấp độ Tùy biến UI (Customization API Levels)

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                       ĐÁNH GIÁ MỨC ĐỘ HỖ TRỢ TÙY BIẾN UI                    │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Level A] Dùng UI Mặc Định                                  ✅ ĐẠT (8.5/10)│
│  - Màn hình ThreadScreen, ConversationListScreen, RoomSettings hoàn chỉnh.  │
│  - Hỗ trợ đổi màu sắc cơ bản qua ChatUiConfig.                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Level B] Tùy Biến Từng Thành Phần (Partial Customization) ❌ CHƯA ĐẠT (3.0/10)│
│  - KHÔNG có builder delegates (messageBubbleBuilder, messageInputBuilder,    │
│    appBarBuilder, reactionPickerBuilder...).                                │
│  - Consumer bắt buộc phải dùng toàn bộ Widget mặc định hoặc viết lại từ đầu.│
├─────────────────────────────────────────────────────────────────────────────┤
│  [Level C] Tự Xây Dựng UI Hoàn Toàn (Headless UI)            🟡 KHÁ (6.5/10)│
│  - Có thể sử dụng Notifier & UseCases từ chat_core và chat_ui.              │
│  - Tuy nhiên Notifier bị phụ thuộc vào ProviderScope override cục bộ        │
│    (roomIdProvider, threadIdProvider) thay vì truyền tham số dạng .family.  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Vấn đề Hardcoded Màu Sắc & Style
- Mặc dù có `ChatUiConfig`, nhiều widget vẫn hardcode màu sắc trực tiếp trong code:
  - `Color(0xFF0787E8)` (Màu xanh dương chủ đạo mặc định).
  - `Color(0xFFF0F2F5)` (Nền avatar).
  - `Colors.orange.shade50` (Nền tin nhắn ghim).
  - `Color(0xFF1D2939)` (Nền video thumbnail).
- **Hệ quả:** Khi host app chuyển sang Dark Mode, giao diện chat bị loang lổ màu sáng/tối không đồng nhất.

---

## 8. Public API Review

### 8.1 Vấn đề Barrel File `chat_ui.dart` & State Toàn Cục

1. **Rò rỉ State nội bộ qua Barrel Export:**
   - `lib/chat_ui.dart` export trực tiếp các Notifier cụ thể (`ThreadMessagesNotifier`, `ConversationListNotifier`) và Provider cục bộ thay vì chỉ export các Widget giao diện và Interface Controller công khai.
2. **State Toàn cục `globalCurrentUserIdProvider`:**
   - File `shared_providers.dart` sử dụng một biến notifier toàn cục `globalCurrentUserIdProvider` để lưu `currentUserId`.
   - Trong `ConversationListState.initState()`, code gọi `Future.microtask(() => ref.read(globalCurrentUserIdProvider.notifier).setUserId(...))`.
   - **Rủi ro:** Khi ứng dụng chạy đa tiến trình, hỗ trợ multi-account hoặc deep link nhảy nhanh giữa 2 tài khoản, việc ghi đè vào biến toàn cục này gây race condition khiến tin nhắn của tài khoản A bị nhận diện nhầm thành tài khoản B (`isMe` bị sai).

---

## 9. Performance Review

| Kịch bản Hội thoại | Khối lượng Dữ liệu | Trải nghiệm Thực tế | Điểm nghẽn Hiệu năng Chính |
|---|---|---|---|
| **Phòng Chat Nhỏ (1-1, < 100 tin)** | Nhẹ | Rất mượt, mở tức thì từ cache | Không có. |
| **Phòng Chat Vừa (500 – 1.000 tin)** | Trung bình | Tương đối tốt khi cuộn | Quét mảng $O(N)$ trong `_getVisibleMessages` và decode ảnh thô gây giật nhẹ (drop frame) khi gửi ảnh. |
| **Phòng Chat Lớn (5.000 – 10.000 tin)** | Nặng | Bị đơ khi tìm kiếm | Quét vét 8 trang liên tục khi tìm kiếm; Memory phình to do rò rỉ controller video tĩnh và `TapGestureRecognizer`. |

---

## 10. Testability & Test Coverage

### 10.1 Hiện trạng Test trong `packages/chat_ui/test/`

Tổng số dòng code test: **342 dòng** (chiếm vỏn vẹn **~2.3%** codebase).
- `test/core/rich_message_text_test.dart` (196 dòng): Test parser HTML và style formatting.
- `test/core/utils/last_message_preview_test.dart` (97 dòng): Test cắt chuỗi preview tin cuối.
- `test/core/chat_navigator_test.dart` (49 dòng): Test parse Map deep link.

### 10.2 Các khu vực quan trọng hoàn toàn CHƯA CÓ TEST (0% Coverage):
1. ❌ `ThreadScreen` & `MessageBubble`: Chưa có Widget test cho luồng hiển thị tin nhắn, bubble bên trái/phải (`isMe`), và render tệp đính kèm.
2. ❌ `ThreadMessagesNotifier`: Chưa có test cho luồng Optimistic send, Realtime message insertion, Pinning, Edit/Delete rollback.
3. ❌ `ConversationListNotifier`: Chưa có test cho việc merge danh sách phòng từ cache + remote và phân trang (`loadMore`).
4. ❌ `HiveMessageLocalDataSource` & `HiveConversationLocalDataSource`: Chưa có test cho việc đọc/ghi dữ liệu JSON và dọn dẹp cache user (`clearAllUserData`).
5. ❌ `MessageInput` & `MediaUpload`: Chưa có test cho việc chọn file, validate định dạng hỗ trợ và tính toán thanh tiến trình upload.

---

## 11. API Call & Resource Matrix

| Nghiệp vụ UI | API / Nguồn Trigger | Tần suất Trigger | Có dư thừa? | Khả năng Cache | Deduplicate? | Rủi ro Hiệu năng / UX |
|---|---|---|:---:|:---:|:---:|---|
| **Tải Lịch sử Chat** | `listMessages` (REST) | Mở phòng chat, Scroll lên | Không | Có (Hive Local) | Không | Load 8 trang nền khi tìm kiếm từ khóa |
| **Lấy Danh tính (ACS ID)** | `join-room` (REST) | Mở phòng chat lần đầu | **Có (nếu mở lại)** | Có (RAM + Hive Store) | **Có** (Single-flight) | Timeout 20s chặn hiển thị `isMe` |
| **Cảm xúc Phòng** | `getRoomReactions` | Mở phòng chat, sau khi thả tim | Không | RAM ngắn hạn | Không | Gọi `state = [...state]` ép rebuild toàn màn hình |
| **Tin nhắn Ghim** | `getPinnedMessages` | Mở phòng chat, sau khi ghim | Không | RAM Notifier | Không | Không phân trang |
| **Thành viên Phòng** | `getMembers` | Mở thread + mở Room Settings | **Có (Gọi 2 lần)** | Không | Không | Gọi lặp lại giữa Notifier và Settings Screen |
| **Cào OpenGraph Link** | `LinkPreviewFetcher.fetch` | Nhập URL và nhấn Gửi | Không | Có (Static Map vô hạn) | Không | **Treo 4s** trước khi chèn tin nhắn vào UI |
| **Tải Lên SAS File** | `UploadFileViaSas` | Gửi ảnh, tệp, video | Không | Không | Không | Đọc toàn bộ byte ảnh vào RAM gây tốn heap |

---

## 12. Lifecycle Matrix

| Trạng thái Giao diện | Hành vi Kỳ vọng | Hành vi Thực tế trong `chat_ui` | Đánh giá & Rủi ro |
|---|---|---|---|
| **Mở Màn hình Chat** | Đọc cache Hive ngay $\to$ Kết nối WebSocket $\to$ Sync tin mới | Đọc cache, kết nối WebSocket, fetch token & history | Tốt. |
| **Chuyển App sang Background** | Tạm dừng heartbeat, giữ nguyên đăng ký phòng | Gọi `leaveActiveRoom()` | ❌ **Nguy hiểm (P0-1 core)**: Xóa sạch danh sách phòng làm hỏng realtime khi quay lại. |
| **Quay lại Foreground** | Sync lại tin nhắn mới, gửi lại `sendReadMessage` | Gửi `sendReadMessageIfNeeded()`, refresh history nếu mất mạng | Khá. |
| **Người dùng Thoát Màn hình (Pop)** | Hủy stream subscription, dọn dẹp controller video | Unsubscribe stream, đóng controller tìm kiếm; **quên dispose VideoPlayerController tĩnh** | ❌ **Rò rỉ bộ nhớ native**. |
| **Mất Mạng & Kết nối lại** | Hiện `OfflineBanner`, tự refresh khi có mạng | `ConnectivityProvider` lắng nghe và tự động gọi `refreshHistory()` | Rất tốt. |

---

## 13. Critical Scenarios Audit

### Scenario 1: Mở Chat $\to$ Gửi Tin Nhắn Chứa Link Web
- **Luồng:** Người dùng nhập `https://flutter.dev` và nhấn Gửi $\to$ `LinkPreviewFetcher` cào metadata trong 2–4s $\to$ Sau 4s tin nhắn mới xuất hiện trên UI.
- **Kết quả:** ⚠️ **FAIL về UX (Bug P1-4)**: Khung chat bị đơ 4 giây trước khi hiển thị tin nhắn.

### Scenario 2: Lướt Qua 10 Tin Nhắn Video Trong Nhóm Chat
- **Luồng:** `ListView` cuộn qua các video $\to$ `VideoMessageContent` khởi tạo và lưu controller vào `static _controllerCache` $\to$ Người dùng thoát màn hình chat.
- **Kết quả:** ❌ **FAIL (Bug P0-1)**: Toàn bộ 10 video controller native vẫn nằm trong RAM, không được giải phóng.

### Scenario 3: Mở Chat $\to$ Background App Trong 30 Giây $\to$ Foreground App
- **Luồng:** Background gọi `leaveActiveRoom()` $\to$ Socket đứt kết nối $\to$ Foreground socket mở lại nhưng không gửi `enter_room`.
- **Kết quả:** ❌ **FAIL (Bug P0-1 kết hợp Core)**: Không nhận được tin nhắn realtime mới.

### Scenario 4: Tìm Kiếm Từ Khóa Trong Phòng Chat
- **Luồng:** Người dùng gõ từ khóa không có ở trang 1 $\to$ Notifier tự động bắn 8 request kéo 400 tin nhắn cũ về máy để tìm kiếm `String.contains()`.
- **Kết quả:** ⚠️ **FAIL về API Efficiency (Bug P1-7)**: Tải ảo lên server và tốn pin thiết bị.

---

## 14. Refactoring Priority Matrix

| Mức độ | Vấn đề | File liên quan | Tác động | Độ phức tạp | Đề xuất giải pháp |
|:---:|---|---|:---:|:---:|---|
| **P0** | Rò rỉ native `VideoPlayerController` tĩnh | `video_message_content.dart` | Rất lớn (Crash OOM) | Trung bình | Xóa static cache, chỉ render ảnh thumbnail tĩnh trong bubble chat, chuyển player vào Dialog độc lập. |
| **P1** | Rò rỉ `TapGestureRecognizer` trong `RichMessageText` | `rich_message_text.dart` | Lớn (Memory Leak) | Thấp | Chuyển sang StatefulWidget có `dispose()` hoặc dùng widget linkify an toàn. |
| **P1** | Đăng ký lặp `ScrollController` listener | `conversation_list_screen.dart` | Trung bình (Duplicate API) | Rất thấp | Chuyển lệnh `addListener` vào `initState()`. |
| **P1** | Treo UI 4s khi gửi tin nhắn chứa link | `thread_messages_notifier.dart` | Lớn (UX) | Thấp | Render tin nhắn optimistic ngay lập tức, cào preview bất đồng bộ sau. |
| **P1** | Giật lag khi decode kích thước ảnh thô | `thread_messages_notifier.dart` | Trung bình (Drop Frame) | Thấp | Dùng thư viện đọc header kích thước ảnh nhẹ (image_size_getter) thay vì decode cả bitmap. |
| **P1** | Hiển thị sai tổng số tài nguyên phòng chat | `thread_providers.dart` | Trung bình (UI Bug) | Rất thấp | Lấy trường `totalCount` từ metadata response thay vì `.length` của mảng preview. |
| **P2** | Tái cấu trúc State Notifier dùng `ThreadState` | `thread_messages_notifier.dart` | Lớn (Kiến trúc) | Trung bình | Kế thừa `Notifier<ThreadState>`, loại bỏ các biến mutable rời rạc và lệnh `state = [...state]`. |
| **P2** | Chia nhỏ God Class `ThreadScreen` (2.264 dòng) | `thread_screen.dart` | Lớn (Bảo trì) | Cao | Tách thành các sub-component: `ThreadAppBar`, `ThreadSearchBar`, `ThreadMessageListView`, `ThreadActionHandlers`. |
| **P2** | Xóa bỏ Hardcoded Text tiếng Việt | `thread_messages_notifier.dart` | Lớn (i18n) | Trung bình | Đưa việc dựng câu hiển thị về Localization layer hoặc Resource Bundle. |
| **P2** | Bổ sung Widget Test và Notifier Test | Thư mục `test/` | Cao (Độ tin cậy) | Trung bình | Tăng độ phủ test từ 2.3% lên $>60\%$. |

---

## 15. Recommended Target Architecture for `chat_ui`

```text
packages/chat_ui/
├── lib/
│   ├── chat_ui.dart                          <-- PUBLIC API (Chỉ export Screens, Builders, Config, Navigator)
│   ├── src/                                  <-- INTERNAL IMPLEMENTATION
│   │   ├── core/
│   │   │   ├── config/ (ChatUiConfig, ChatThemeData)
│   │   │   ├── navigation/ (ChatNavigator, ChatDeepLinkData)
│   │   │   ├── localization/ (ChatLocalizations, En/Vi strings)
│   │   │   └── widgets/ (SearchField, SkeletonBox, OfflineBanner, SafeRichText)
│   │   ├── features/
│   │   │   ├── conversation_list/
│   │   │   │   ├── presentation/ (screens/, widgets/, notifiers/ -> StateNotifier<ConversationListState>)
│   │   │   ├── thread/
│   │   │   │   ├── presentation/
│   │   │   │   │   ├── controllers/ (ThreadNotifier -> Notifier<ThreadState>)
│   │   │   │   │   ├── screens/ (ThreadScreen decomposed: ThreadAppBar, ThreadListView...)
│   │   │   │   │   ├── widgets/ (MessageBubble, MessageInput, MediaViewer...)
│   │   │   │   │   └── builders/ (ChatBubbleBuilder, ChatInputBuilder delegates)
│   │   │   ├── contact/
│   │   │   │   ├── presentation/ (screens/, notifiers/)
│   │   │   └── shared/
│   │   │       ├── local/ (Hive Datasources with robust try-catch)
│   │   │       └── providers/ (Riverpod family providers, no global mutable state)
```

---

## 16. Actionable Migration Plan

### Giai đoạn 1: Sửa lỗi Nghiêm trọng & Rò rỉ Tài nguyên (Critical Fixes) — *Làm ngay*
1. **Fix Memory Leak Video P0-1**: Xóa bỏ `static _controllerCache` trong `VideoMessageContent`. Thay thế nội dung video trong bubble chat bằng thumbnail tĩnh + icon Play. Khi nhấn Play mới khởi tạo player trong `ChatVideoPlayerDialog` và dọn dẹp khi đóng.
2. **Fix Gesture Leak P1-1**: Chuyển `RichMessageText` sang cơ chế quản lý gesture an toàn, đảm bảo mọi `TapGestureRecognizer` đều được `dispose()`.
3. **Fix Scroll Listener P1-2**: Chuyển `_scrollController.addListener(_maybeLoadMore)` từ `didChangeDependencies()` về `initState()` trong `ConversationListScreen`.
4. **Fix Instant Send UX P1-4**: Render tin nhắn `optimistic` ngay khi bấm Gửi, không chờ `LinkPreviewFetcher` hoàn tất.

### Giai đoạn 2: Tối ưu Hóa Hiệu năng & Sửa Lỗi Logic (Performance & Logic Fixes)
1. **Fix Image Decoding Jank P1-3**: Thay thế `instantiateImageCodec` bằng phương thức đọc header file gọn nhẹ.
2. **Fix Total Count Resource P1-5**: Đọc trực tiếp `totalCount` từ metadata của Backend trong `roomResourcePreviewProvider`.
3. **Sửa Provider Overrides**: Loại bỏ `late final _overrides` trong `_ThreadScreenState`, chuyển sang sử dụng `.family` providers cho `roomId` và `threadId`.

### Giai đoạn 3: Tái cấu trúc State Management & Tách nhỏ God Class (Architecture Cleanup)
1. **Kích hoạt lại `ThreadState`**: Refactor `ThreadMessagesNotifier` thành `Notifier<ThreadState>`, đóng gói toàn bộ `messages`, `pinnedMessages`, `reactionsMap`, `loading`, `myAcsUserId` vào immutable state.
2. **Modularize `ThreadScreen`**: Chia tách file 2.264 dòng thành các component độc lập:
   - `ThreadAppBar`: Thanh tiêu đề + Search bar.
   - `ThreadMessageList`: Quản lý `ScrollablePositionedList` và scroll to bottom.
   - `ThreadActionSheets`: Quản lý dialog phản hồi cảm xúc và menu tùy chọn tin nhắn.

### Giai đoạn 4: Hỗ trợ Đa ngôn ngữ (i18n) & Customization Builders (Level B Customization)
1. Tạo `ChatLocalizations` hỗ trợ tiếng Việt và tiếng Anh, chuyển toàn bộ câu thông báo hệ thống hardcoded về localization bundle.
2. Bổ sung các builder delegates vào `ThreadScreen` và `ConversationListScreen`:
   ```dart
   ThreadScreen(
     messageBubbleBuilder: (context, message, isMe) => ...,
     inputBarBuilder: (context, onSend) => ...,
   )
   ```
3. Kết nối callback `ChatUiConfig.onFileTap` vào `MediaContent`.

### Giai đoạn 5: Tăng cường Test Coverage
1. Viết bộ Widget Test cho `MessageBubble`, `RichMessageText`, `MessageInput`.
2. Viết State Notifier Test cho `ThreadMessagesNotifier` và `ConversationListNotifier` (kiểm tra phân trang, gửi tin nhắn, nhận realtime).
3. Nâng độ phủ test tổng thể lên $>60\%$.

---

## 17. Production Readiness Verdict

```text
⚠️ READY WITH MAJOR FIXES  (Cần xử lý các lỗi rò rỉ bộ nhớ P0/P1 trước khi phát hành)
```

### Must Fix Before Release:
1. Xóa `static _controllerCache` trong `VideoMessageContent` để ngăn chặn rò rỉ native video decoders (P0-1).
2. Xử lý giải phóng `TapGestureRecognizer` trong `RichMessageText` (P1-1).
3. Sửa việc đăng ký lặp listener của `ScrollController` trong `ConversationListScreen` (P1-2).
4. Không chặn luồng gửi tin nhắn chờ cào Link Preview (P1-4).
5. Sửa lỗi `late final _overrides` trong `ThreadScreen` để tránh giữ provider cũ (Phần 2.2.E).

### Should Fix:
1. Tái cấu trúc `ThreadMessagesNotifier` sử dụng `ThreadState` bất biến, loại bỏ biến mutable và hack `state = [...state]`.
2. Chia nhỏ `ThreadScreen` (2.264 dòng) thành các widget con để dễ bảo trì và test.
3. Thay thế việc giải mã toàn bộ ảnh bằng đọc header EXIF nhẹ để tránh giật frame khi gửi ảnh.
4. Tách chuỗi tiếng Việt hardcoded sang hệ thống đa ngôn ngữ (i18n).
5. Kết nối callback `ChatUiConfig.onFileTap` đang bị bỏ hoang trong `MediaContent`.

### Nice to Have:
1. Bổ sung các builder delegates (`messageBubbleBuilder`, `inputBuilder`) hỗ trợ tùy biến UI Level B.
2. Nâng độ phủ Unit Test & Widget Test từ 2.3% lên $>60\%$.
