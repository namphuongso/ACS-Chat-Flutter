# Bộ Nguyên Tắc Clean Code — Chat Module (Clean Architecture)

> Phạm vi: toàn bộ workspace `chat-module-mvp` (melos monorepo).
> Tài liệu này bổ sung cho `Project-guildline_and_structure_chat.md` (cấu trúc thư mục & phân tầng) — khi có xung đột về cấu trúc, tài liệu cấu trúc là nguồn sự thật.
> Stack tham chiếu: Dart >=3.3, Riverpod 3 (`chat_ui`), pure Dart + http/web_socket_channel (`chat_core`), mocktail cho test.

---

## 1. Nguyên tắc kiến trúc & hướng phụ thuộc

1. **Hướng phụ thuộc chỉ đi vào trong (Dependency Rule):**
   `presentation → domain ← data`. Domain không được phụ thuộc bất kỳ layer nào.
2. **`chat_core` là pure Dart:** không import `package:flutter/*`, `package:flutter_riverpod/*`, hay bất kỳ UI framework nào. Nếu một file trong `chat_core` cần `BuildContext`, đó là bug kiến trúc.
3. **`chat_ui` chỉ phụ thuộc `chat_core` qua public API:** import qua barrel file `package:chat_core/chat_core.dart`; không import sâu vào file nội bộ của package khác (`package:chat_core/src/...` là cấm).
4. **Feature là đơn vị cô lập:** mỗi feature (`auth_token`, `thread`, `conversation_list`, `contact`, `read_status`) có đủ `domain/` + `data/` trong `chat_core` và `presentation/` trong `chat_ui`. Code dùng chung nằm ở `lib/core/` (core) hoặc `features/shared/` (UI).
5. **Không gọi chéo data layer của feature khác:** feature A muốn dữ liệu của feature B phải đi qua use case / repository interface của B, không import datasource của B.
6. **Không bypass layer:** widget không gọi datasource/http trực tiếp; use case không import model; notifier không tự dựng HTTP request.

---

## 2. Quy tắc tầng Domain (`chat_core/.../domain/`)

1. **Entity là dữ liệu nghiệp vụ thuần:** immutable (mọi field là `final`), constructor `const` khi có thể, có `==`/`hashCode` dựa trên giá trị.
2. **Entity không chứa JSON, không chứa annotation serialize.** Parse JSON là việc của Model ở tầng Data.
3. **Repository là abstract class/interface** đặt tại `domain/repositories/`, chỉ nói ngôn ngữ entity (`Future<Message>`, không `Map<String, dynamic>`).
4. **Use case = 1 hành động nghiệp vụ duy nhất:**
   - Lớp `XxxUseCase` nhận dependency qua constructor, expose method `call(...)`.
   - Không giữ state, không side effect ẩn, không biết UI hay HTTP tồn tại.
   - Từ 2 use case trở lên cho cùng 1 repository là bình thường; 1 use case làm 3 việc là cần tách.
5. **Enum mở cho giá trị server-driven:** dùng pattern `MessageType` (class const + `fromString` + fallback `unknown`) thay vì enum cứng khi server có thể thêm giá trị mới — đảm bảo tương thích ngược.
6. **Domain không ném exception thô:** chỉ ném `Failure`/exception nghiệp vụ đã định nghĩa trong `core/error/`.

---

## 3. Quy tắc tầng Data (`chat_core/.../data/`)

1. **Model kế thừa hoặc wrap entity** và thêm `fromJson`/`toJson`. Quy ước đặt tên `XxxModel`, file `xxx_model.dart`.
2. **Datasource là interface + Impl tách rời** (`XxxRemoteDatasource` / `XxxRemoteDatasourceImpl`) để test được bằng mock.
3. **Datasource chỉ làm 2 việc:** gọi nguồn dữ liệu (REST/WS/Native/local) và ném `ChatApiException` (hoặc exception chuẩn) khi lỗi — không tự ý xử lý nghiệp vụ, không nuốt lỗi.
4. **RepositoryImpl là nơi duy nhất:**
   - Kết hợp nhiều datasource (vd REST + Native realtime trong `MessageRepositoryImpl`).
   - Map model → entity và ngược lại.
   - Bắt exception hạ tầng và chuyển thành lỗi miền thống nhất.
5. **Mapping JSON phòng thủ:** cast có kiểm tra (`json['x'] as String? ?? fallback`), không `as` trần trên dữ liệu server; luôn có fallback cho field optional.
6. **Không cache, retry, throttle ngầm** trong datasource khi chưa được ghi chú bằng doc comment và có test đi kèm.
7. **Realtime/polling engine** (`PollingEngine`, `NativeRealtimeDatasource`) phải có cách dừng/hủy rõ ràng (`dispose`/`stop`) và không leak stream/subscription.

---

## 4. Quy tắc tầng Presentation (`chat_ui/.../presentation/`)

### 4.1 Riverpod 3
1. **Mọi provider đặt trong `providers/` hoặc `notifiers/`**, đặt tên file `xxx_providers.dart`, tên provider `xxxProvider`, notifier `XxxNotifier extends AsyncNotifier<...>` (ưu tiên `AsyncNotifier` cho dữ liệu bất đồng bộ).
2. **Widget không chứa business logic:** widget chỉ `ref.watch` để render, `ref.read` cho sự kiện one-shot (onTap, submit). Không gọi `ref.read` rồi mutate state thủ công ngoài notifier.
3. **State của notifier là immutable:** mỗi thay đổi state = gán `state = ...` / `AsyncValue` mới; không mutate list/map đang giữ trong state (tạo bản copy mới).
4. **Không tạo `Future`/side effect trong `build()`**; dùng `ref.listen` cho phản ứng theo state, `initState`/notifier method cho khởi tạo.
5. **Provider scope:** provider mặc định sống theo container; provider gắn với 1 màn hình/đối tượng (vd theo `roomId`) phải dùng `.family` và hủy đúng vòng đời.
6. **Lỗi hiển thị:** `AsyncValue.when/error` phải render trạng thái lỗi có hành động (retry) — không `print` rồi bỏ qua, không crash im lặng.

### 4.2 Widget
1. **1 widget = 1 trách nhiệm render.** `build()` vượt ~100 dòng hoặc lồng quá 4 level → tách widget con vào `widgets/`.
2. **Ưu tiên widget con là class riêng, không phải helper method** — chi tiết và ví dụ ở mục 4.3.
3. **Constructor `const` ở mọi widget có thể**; tham số `required` + `final`, không setter.
4. **Không hardcode chuỗi UI trong `build`:** text dùng chung đưa vào constants/strings; màu/spacing dùng token thiết kế có sẵn trong `core/`.
5. **Màn hình = `screens/xxx_screen.dart`**, chỉ làm nhiệm vụ lắp widget + gom provider; logic nhập liệu phức tạp (vd `message_input`) tách thành widget riêng có test.
6. **Loading/error/empty là first-class UI state** — mỗi màn hình có đủ 3 trạng thái này, không chỉ happy path.
7. **Tránh `Navigator` rải rác:** điều hướng gom về nơi dễ truy vết (screen hoặc router helper), không navigate từ trong widget lá.

### 4.3 Tổ chức component — tách widget class riêng, hạn chế helper widget

1. **Không lạm dụng helper method trả Widget** (`Widget _buildHeader()`, `_buildBubble()`, `_buildFooter()`...). Helper method:
   - Không được `const`, không được Flutter tối ưu rebuild (luôn build lại cùng widget cha), không xuất hiện riêng lẻ trong widget tree/DevTools, khó test và khó tái sử dụng.
   - Chỉ chấp nhận khi: đoạn UI rất nhỏ (< ~15 dòng), dùng đúng 1 lần trong chính class đó, không có logic/state riêng.
   - Dùng từ 2 lần trở lên, có state hoặc interaction riêng (controller, onTap, animation) → **bắt buộc tách thành Widget class riêng** trong `widgets/` rồi import vào nơi dùng.
2. **Mỗi widget class = 1 file** trong thư mục `widgets/` của feature; tên file = tên lớp (`message_bubble.dart` → `MessageBubble`), và import ở nơi sử dụng:

   ```dart
   // ❌ Tránh: screen phình to với một đống helper widget
   class ThreadScreen extends ConsumerWidget {
     Widget _buildHeader(...) => ...;      // 80 dòng
     Widget _buildMessageList(...) => ...; // 120 dòng
     Widget _buildInput(...) => ...;       // 90 dòng

     @override
     Widget build(context, ref) => Column(
       children: [_buildHeader(), _buildMessageList(), _buildInput()],
     );
   }

   // ✅ Nên: screen chỉ lắp ghép các widget class đã tách riêng
   import '../widgets/thread_header.dart';
   import '../widgets/message_list.dart';
   import '../widgets/message_input.dart';

   class ThreadScreen extends ConsumerWidget {
     @override
     Widget build(context, ref) => const Column(
       children: [
         ThreadHeader(),
         Expanded(child: MessageList()),
         MessageInput(),
       ],
     );
   }
   ```

3. **Widget giao tiếp qua constructor, không qua global:** dữ liệu/callback truyền xuống bằng tham số `required`/`final` (vd `MessageItem(message: m, onResend: ...)`). Widget lá không tự `ref.read` dữ liệu của màn hình trừ khi đó là state sở hữu của chính nó.
4. **Composition qua tham số `child`/slot, không qua cờ config:** khi cần tùy biến giao diện, nhận `Widget` (hoặc builder tối thiểu) thay vì dồn nhiều cờ boolean vào 1 "god widget" 20 tham số. Widget vượt ~6 tham số cấu hình là dấu hiệu cần tách.
5. **Nhóm widget luôn đi cùng nhau → tạo composite widget:** nếu `MessageBubble` + `MessageReactions` + `MessageMeta` luôn xuất hiện cùng chỗ, gom thành 1 widget cha để nơi dùng chỉ cần import 1 class.
6. **Phạm vi tái sử dụng quyết định vị trí đặt:**
   - Chỉ 1 feature dùng → `features/<feature>/presentation/widgets/`.
   - Nhiều feature dùng → `features/shared/presentation/widgets/`.
   - Thuần UI, không nghiệp vụ (button, avatar, badge...) → `core/widgets/`.
   - Không import widget của feature A vào feature B — cần dùng chung thì nâng lên `shared/`.
7. **Screen không chứa widget nghiệp vụ inline:** màn hình chỉ import và lắp ghép; mọi phần tử có logic render (phân nhánh theo `MessageType`, trạng thái gửi, read receipt...) phải nằm trong widget class riêng có tên theo nghiệp vụ.

---

## 5. Quy tắc Dart/Flutter chung

1. **Format:** `dart format` là bắt buộc (CI chạy `melos run format` với `--set-exit-if-changed`). Không tranh luận format bằng tay.
2. **Lint:** `flutter_lints`/`lints` theo package; không thêm `// ignore:` trừ khi kèm lý do và ticket.
3. **Đặt tên:**
   - File: `snake_case.dart`, 1 lớp chính/file, tên file = tên lớp.
   - Lớp/enum: `PascalCase`; biến/hàm/tham số: `camelCase`; hằng số top-level: `camelCase` với `const`.
   - Tên boolean đọc như câu hỏi: `isLoading`, `hasMore`, `canSend`.
   - Đặt tên theo nghiệp vụ (`sendMessage`, `unreadCount`), không theo kỹ thuật (`doIt`, `data2`, `temp`).
4. **`final`/`const` mặc định;** chỉ dùng `var` khi cần reassign và kiểu suy ra được rõ ràng.
5. **Null-safety:** cấm `!` (force unwrap) trừ khi chứng minh được khác null và có comment; ưu tiên `?.`, `??`, early return.
6. **Không dùng `dynamic`/`Map<String, dynamic>` lan qua nhiều layer** — nó chỉ tồn tại ở biên JSON (datasource/model).
7. **String interpolation** thay cộng chuỗi; collection-if/for thay xây list thủ công khi đọc rõ hơn.
8. **Async:** mọi `Future` không await phải được xử lý (await, `unawaited`, hoặc catch); không `async` trong `build`. Stream/subscription phải `cancel` trong `dispose`.
9. **Không comment code chết** — xóa và để git giữ lịch sử.
10. **Doc comment `///`** cho mọi public API (entity, repository, use case, provider, widget public): mô tả ý nghĩa nghiệp vụ, không lặp lại tên.

---

## 6. Xử lý lỗi & logging

1. **Lỗi API chuẩn hóa qua `ChatApiException`** (statusCode + code registry + message); không tự chế exception mới khi đã có loại phù hợp.
2. **Bắt exception theo loại, không `catch (_)` nuốt mọi lỗi;** nếu phải catch rộng, log + rethrow hoặc map thành trạng thái UI rõ ràng.
3. **UI không hiển thị message kỹ thuật thô** (stack trace, response body) cho user — map sang thông điệp thân thiện, giữ lỗi gốc trong log.
4. **Log có ngữ cảnh:** `[feature][layer] message` kèm id liên quan (roomId, messageId); không log token/secret/dữ liệu cá nhân.

---

## 7. Testing

1. **Mỗi use case và repository impl có unit test** với mocktail mock datasource; notifier có test cho các trạng thái loading/success/error.
2. **Test đặt đối xứng với nguồn:** `lib/features/thread/domain/usecases/send_message_usecase.dart` → `test/features/thread/domain/usecases/send_message_usecase_test.dart`.
3. **Đặt tên test:** `group('SendMessageUseCase')` + `test('returns message when repo success')` — đọc như câu hành vi.
4. **Test hành vi, không test implementation:** assert kết quả/state, không verify nội bộ private.
5. **Không test có network thật:** mọi HTTP/WS trong test phải là mock/fake.
6. **Widget test cho component nhiều logic render** (vd bubble theo type, input validation); không cần widget test cho widget chỉ dàn layout.
7. **Chạy trước khi mở PR:** `melos run analyze`, `melos run format`, `melos run test` — cả ba phải xanh.

---

## 8. Hiệu năng (Flutter)

1. `const` widget tối đa để giảm rebuild; tách widget con để phạm vi rebuild nhỏ.
2. Danh sách dài dùng `ListView.builder`/`scrollable_positioned_list`; không build toàn bộ list một lần.
3. Ảnh/video trong chat phải có placeholder + kích thước giới định; dispose controller (`video_player`, animation) trong `dispose`.
4. Không debounce/gọi API trong `build`; sự kiện input (typing, search) phải debounce ở notifier.

---

## 9. Git & Code Review

1. **Commit:** message tiếng Việt hoặc Anh nhất quán trong 1 commit, dạng `<type>(<scope>): <summary>` với type ∈ {feat, fix, refactor, test, docs, chore, perf}; scope = tên feature/package.
2. **1 PR = 1 thay đổi có thể review;** refactor tách khỏi thay đổi hành vi.
3. **Checklist review tối thiểu:**
   - [ ] Dependency rule không bị vi phạm (không import ngược tầng, `chat_core` không chạm Flutter).
   - [ ] Widget không chứa logic nghiệp vụ; state immutable.
   - [ ] Không `!`/`dynamic` lan tràn; lỗi được map chuẩn.
   - [ ] Có test cho logic mới; analyze/format/test xanh.
   - [ ] Public API có doc comment; không comment code chết.

---

## 10. Bản tóm tắt "30 giây"

- `chat_core` = nghiệp vụ thuần (entity → use case → repository interface → data impl), không Flutter.
- `chat_ui` = render + Riverpod notifier; widget mỏng, state immutable, đủ loading/error/empty.
- UI lắp ghép từ widget class riêng biệt (1 file/class trong `widgets/`), không lạm dụng helper method trả Widget.
- Đặt tên theo nghiệp vụ, `final` mặc định, cấm `!` bừa, JSON chỉ sống ở biên datasource.
- Lỗi đi qua `ChatApiException`/Failure chuẩn; UI hiện thông điệp thân thiện.
- Mọi thứ format + lint + test trước khi merge.
