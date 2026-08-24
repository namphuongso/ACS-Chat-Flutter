# Báo Cáo Tổng Hợp Các Vấn Đề Chưa Hoàn Thiện (Part 6 Review)

Tài liệu này tổng hợp toàn bộ các vấn đề chưa hoàn thiện, mã nguồn tàn dư và điểm cần nâng cấp được ghi nhận từ 3 báo cáo review chuyên sâu Phase 6: `chat-ui-review-p6.md`, `chat-native-review-p6.md` và `chat-core-review-p6.md` tại commit baseline `7f93fed`.

## 1. Mức Độ P1 - Ưu Tiên Cao (Critical / High Priority)

1. `chat_ui` - Thành phần mồ côi chưa được nhúng sử dụng (Orphaned Dead Code)
- File: `lib/features/thread/presentation/widgets/thread_app_bar.dart` và `thread_search_bar.dart`
- Hiện trạng: Hai widget `ThreadAppBar` (84 LOC) và `ThreadSearchBar` (124 LOC) đã được tách thành file riêng nhưng chưa được import hoặc gọi trong `ThreadScreen.dart`.
- Tác động: `ThreadScreen.dart` vẫn duy trì khối AppBar và SearchBar inline trùng lặp hơn 180 dòng mã, gây lãng phí mã nguồn và làm hiểu nhầm cho lập trình viên bảo trì.
- Hướng xử lý: Thay thế toàn bộ khối `appBar: _isSearching ? ... : ...` trong `ThreadScreen.dart` bằng `ThreadAppBar` và `ThreadSearchBar`.

2. `chat_ui` - Vẫn tồn tại God Class & God Widget kích thước lớn
- File: `lib/features/thread/presentation/screens/thread_screen.dart` (2,288 LOC) và `thread_messages_notifier.dart` (1,371 LOC)
- Hiện trạng: `ThreadScreen` đảm nhận quá nhiều trách nhiệm (render danh sách, scroll position, search debounce, deep scan 4 trang lịch sử, dialogs/bottom sheets, lifecycle). `ThreadMessagesNotifier` ôm quá nhiều logic (phân trang, WebSocket parser/dispatcher callback, system message enrichment, identity resolution).
- Tác động: Khó viết unit test, khó bảo trì và nguy cơ phát sinh side effect khi chỉnh sửa.
- Hướng xử lý: Tách tiếp thành `ThreadSearchController`, `ThreadActionMenuDialogs` và `SystemMessageEnricher`.

3. `chat_ui` - Trùng lặp & phân mảnh logic định dạng tin nhắn hệ thống
- File: `lib/features/thread/presentation/notifiers/thread_messages_notifier.dart` (`_handleMemberEventSignal` và `_enrichSystemMessageContent`)
- Hiện trạng: Cả hai phương thức đều tự bóc tách `actorId`, `targetId`, `actorName`, `targetName` từ metadata lồng nhau với hàng chục fallback keys.
- Tác động: Khi Backend thêm event type mới hoặc đổi key, nếu chỉ sửa 1 nơi sẽ dẫn đến bất đồng bộ nội dung giữa tin nhắn realtime và tin nhắn tải lại từ lịch sử.
- Hướng xử lý: Chuyển toàn bộ logic trích xuất và định dạng văn bản sang `SystemMessageTextBuilder` trong `chat_core`.

4. `chat_ui` - Nuốt ngoại lệ im lặng & hiển thị raw exception ra UI
- File: `thread_messages_notifier.dart`, `room_members_screen.dart`, `room_settings_screen.dart`
- Hiện trạng: Vẫn còn hơn 35 vị trí `catch (_) {}` nuốt ngoại lệ mà không ghi log qua `ChatLogger`. Khi API lỗi trong `RoomMembersScreen` và `RoomSettingsScreen`, code hiển thị nguyên văn `Lỗi: $e` (raw exception string) lên SnackBar.
- Tác động: Mất khả năng chẩn đoán sự cố sản xuất và làm giảm trải nghiệm người dùng cuối.
- Hướng xử lý: Bổ sung `ChatLogger.error` cho mọi khối catch và chuẩn hóa thông báo lỗi thân thiện qua `showChatToast`.

5. `chat_ui` - Gọi API dư thừa `getMembers` khi mở phòng chat
- File: `lib/features/thread/presentation/notifiers/thread_messages_notifier.dart` (`_fetchMembersIfNeeded`)
- Hiện trạng: Mỗi lần mở màn hình chat, `_fetchMembersIfNeeded()` luôn gửi HTTP request `GET /rooms/{id}/members` mặc dù danh sách thành viên đã có trong token join-room và `conversationListProvider`.
- Tác động: Gây lãng phí request mạng không cần thiết khi người dùng chuyển qua lại giữa nhiều phòng.
- Hướng xử lý: Kiểm tra danh sách participants trong state trước khi quyết định gửi HTTP request.

6. `chat_core` - Barrel file export trực tiếp các implementation classes
- File: `lib/chat_core.dart`
- Hiện trạng: Export trực tiếp 10+ file `*_impl.dart` (`AuthTokenRepositoryImpl`, `MessageRemoteDataSourceImpl`, `WebSocketRealtimeDataSourceImpl`...) ra public namespace.
- Tác động: Rò rỉ chi tiết cài đặt nội bộ ra ngoài SDK. Khách hàng sử dụng SDK có thể phụ thuộc trực tiếp vào class `Impl` thay vì Interface, gây breaking change khi refactor nội bộ.
- Hướng xử lý: Thu gọn `chat_core.dart`, chỉ export Domain Entities, Repositories Interfaces, UseCases, Exceptions và Config. Ẩn toàn bộ `*_impl.dart` vào private exports hoặc thư mục `src/`.

## 2. Mức Độ P2 - Ưu Tiên Trung Bình (Medium Priority)

1. `chat_ui` - Thiếu khả năng tùy biến Slot Builder (Level 2 Customization)
- File: `lib/core/chat_ui_config.dart`
- Hiện trạng: `ChatUiConfig` cung cấp 30+ token màu sắc nhưng hoàn toàn thiếu các slot `WidgetBuilder` để tùy biến giao diện.
- Hướng xử lý: Bổ sung `messageBubbleBuilder`, `inputBuilder`, `customAppBarBuilder` vào `ChatUiConfig`.

2. `chat_ui` - Bộ nhớ tạm Avatar và Link Preview chưa có giới hạn dung lượng LRU
- File: `thread_messages_notifier.dart` (`_userAvatarCache`) và `link_preview_fetcher.dart` (`_cache`)
- Hiện trạng: Sử dụng `Map` thông thường lưu trên RAM không có capacity cap và không có TTL.
- Hướng xử lý: Áp dụng `LruCache` giới hạn tối đa 200 phần tử để tránh phình bộ nhớ trong các nhóm lớn.

3. `chat_ui` - Thiếu hụt độ phủ kiểm thử tự động (Test Coverage)
- File: Thư mục `packages/chat_ui/test/`
- Hiện trạng: Toàn bộ package chỉ có 5 file unit test cơ bản (17 test cases), 0% widget test cho các màn hình chính và chưa test luồng realtime/phân trang.
- Hướng xử lý: Viết Unit Test cho `ThreadMessagesNotifier` (gửi tin, phân trang, dedup) và Widget Test cho `MessageInput`, `MessageBubble`.

4. `chat_core` - `MessageRemoteDataSourceImpl` tự quản lý `http.Client` riêng
- File: `lib/features/thread/data/datasources/message_remote_datasource_impl.dart`
- Hiện trạng: Không dùng chung `JsonApiClient` mà tự tạo `http.Client` và tự build headers tại hơn 10 phương thức.
- Hướng xử lý: Chuyển `MessageRemoteDataSourceImpl` sang inject và sử dụng `JsonApiClient`.

5. `chat_core` - `SystemMessageTextBuilder.customResolver` là static mutable global
- File: `lib/features/thread/domain/services/system_message_text.dart`
- Hiện trạng: Khai báo static global variable `customResolver` dễ gây flaky test khi chạy test đa luồng/isolate.
- Hướng xử lý: Inject resolver qua `ChatModuleConfig` hoặc instance parameter.

6. `chat_core` - Hardcoded `pageSize: '50'` ở các endpoints reactions
- File: `lib/features/thread/data/datasources/message_remote_datasource_impl.dart`
- Hiện trạng: Các API lấy reactions luôn gắn cứng `pageSize: 50` mà không cho phép caller truyền tham số phân trang.
- Hướng xử lý: Bổ sung tham số `pageIndex` và `pageSize` cho UseCase và DataSource.

7. `chat_core` - Thiếu Unit Tests cho `WebSocketEventParser` và `WebSocketEventDispatcher`
- File: Thư mục `packages/chat_core/test/`
- Hiện trạng: Chưa có unit test cho Parser (15+ event types) và Dispatcher (hàng đợi LRU 100 entries, bypass signal events).
- Hướng xử lý: Bổ sung test suite kiểm thử toàn bộ các kịch bản parse JSON và dedup realtime.

8. `chat_native` / Workspace - Thư mục rỗng `chat_native_platform_interface` chứa file generated
- Đường dẫn: `packages/chat_native_platform_interface/`
- Hiện trạng: Thư mục không còn mã nguồn nhưng vẫn còn `.dart_tool/pubspec.lock` và `package_config.json` trên đĩa cục bộ.
- Hướng xử lý: Xóa hoàn toàn thư mục `chat_native_platform_interface` trên đĩa để dọn dẹp workspace.

## 3. Mức Độ P3 - Ưu Tiên Thấp & Tàn Dư Codebase (Low Priority & Cleanup)

1. `chat_ui` & `chat_core` - Tàn dư Naming và Typedefs `NativeRealtimeDataSource*`
- File: `shared_providers.dart`, `websocket_realtime_datasource.dart`, `websocket_realtime_datasource_impl.dart`
- Hiện trạng: Vẫn giữ typedefs tương thích ngược `NativeRealtimeDataSource` trỏ tới `WebSocketRealtimeDataSource`.
- Hướng xử lý: Đánh dấu `@deprecated` và đổi tên gọi trực tiếp ở phiên bản Major v3.0.

2. `chat_core` - Heuristic `parseEventDate` giả định chuỗi không offset là UTC
- File: `lib/features/thread/data/models/message_model.dart`
- Hiện trạng: Tự động nối thêm `'Z'` vào chuỗi date không có offset timezone.
- Hướng xử lý: Thống nhất hợp đồng chuẩn ISO-8601 UTC với Backend.

3. `chat_core` - `Conversation.copyWith` không hỗ trợ clear null trường optional
- File: `lib/features/conversation_list/domain/entities/conversation.dart`
- Hiện trạng: Truyền `copyWith(avatarUrl: null)` vẫn giữ lại giá trị cũ.
- Hướng xử lý: Bổ sung cờ `clearAvatar` và `clearLastMessage`.

4. `chat_core` - Dead code endpoint `ChatApiEndpoints.acsThreadMessages`
- File: `lib/core/constants/chat_api_endpoints.dart`
- Hiện trạng: Endpoint REST trực tiếp Azure ACS không còn được sử dụng ở bất kỳ đâu.
- Hướng xử lý: Xóa bỏ endpoint thừa.

## 4. Bảng Tổng Hợp Phân Công & Kế Hoạch Xử Lý (Action Roadmap)

1. Giai đoạn 1: Dọn dẹp & Ổn định API (1-2 ngày)
- Tích hợp `ThreadAppBar` và `ThreadSearchBar` vào `ThreadScreen.dart`.
- Thu gọn barrel export `chat_core.dart`, ẩn toàn bộ `*_impl.dart`.
- Thêm log error cho tất cả các khối `catch` im lặng và ẩn raw exception trên UI.
- Kiểm tra cache trong `_fetchMembersIfNeeded` để bỏ request `getMembers` dư thừa.
- Xóa thư mục rỗng `packages/chat_native_platform_interface` trên disk.

2. Giai đoạn 2: Tái cấu trúc & Chuẩn hóa Network (2 ngày)
- Chuyển `MessageRemoteDataSourceImpl` sang dùng `JsonApiClient`.
- Chuyển logic bóc tách tin nhắn hệ thống về `SystemMessageTextBuilder`.
- Bổ sung các slot Builder (`messageBubbleBuilder`, `inputBuilder`) vào `ChatUiConfig`.

3. Giai đoạn 3: Kiểm thử tự động & Hoàn thiện SDK (2 ngày)
- Viết Unit Test cho `WebSocketEventParser` và `WebSocketEventDispatcher`.
- Viết Unit Test cho `ThreadMessagesNotifier` (gửi tin, phân trang, realtime dedup).
- Viết Widget Test cơ bản cho `ThreadScreen` và `MessageInput`.
