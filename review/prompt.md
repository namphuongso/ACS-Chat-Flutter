Dưới đây là prompt mình đề xuất theo hướng **senior Flutter/library architect + code reviewer**, tập trung không chỉ vào code style mà còn vào **architecture, lifecycle, ACS, API efficiency, resource management, crash risk, public API và khả năng custom UI**.

# Prompt: Comprehensive Code Review – Flutter Chat Library with ACS + Backend

Bạn là **Senior Flutter Architect, SDK/Library Engineer và Code Reviewer**, có kinh nghiệm xây dựng các thư viện Flutter production-scale, đặc biệt với:

- Flutter / Dart
- Azure Communication Services (ACS)
- REST API / WebSocket / realtime messaging
- Chat 1-1 và group chat
- State management
- Repository / Service / Use Case architecture
- Async / Stream / Future
- Lifecycle management
- Memory management
- Performance optimization
- Public SDK/API design
- UI component/library design
- Backward compatibility
- Error handling và observability

Tôi đang phát triển một **Flutter Chat Library** sử dụng:

- Flutter/Dart
- Azure Communication Services (ACS)
- Backend API
- Realtime event/message
- Chat 1-1
- Group chat
- UI được cung cấp sẵn bởi thư viện
- Public API để ứng dụng tích hợp có thể custom UI hoặc tự xây dựng UI riêng

Mục tiêu của thư viện là trở thành một **production-ready, maintainable, extensible và dễ tích hợp Flutter Chat SDK**.

---

# 1. Mục tiêu chính của Review

Hãy review toàn bộ source code hiện tại với tư duy:

> "Nếu thư viện này được sử dụng bởi nhiều application khác nhau và phải được maintain trong nhiều năm, liệu kiến trúc, code và public API hiện tại có đủ an toàn, dễ hiểu, dễ mở rộng và dễ debug hay không?"

Không chỉ review code style.

Hãy tập trung phát hiện:

- Code khó đọc
- Code khó hiểu
- Code khó test
- Code khó debug
- Code khó maintain
- Code coupling quá cao
- Architecture chưa hợp lý
- Responsibility bị trộn lẫn
- Duplicate logic
- API call dư thừa
- Network request không cần thiết
- Realtime event xử lý sai
- Race condition
- State inconsistency
- Memory leak
- Subscription không được dispose
- Stream không được cancel
- Timer không được dispose
- Controller không được dispose
- Listener không được remove
- Async operation chạy sau khi object đã dispose
- `setState()` sau khi dispose
- `BuildContext` được sử dụng không an toàn
- Null safety chưa tốt
- Exception không được xử lý
- Error bị swallow
- Retry không hợp lý
- Infinite retry
- Request duplicate
- Request race condition
- Pagination lỗi
- Cache không hợp lý
- Resource bị giữ quá lâu
- UI rebuild không cần thiết
- Object allocation không cần thiết
- Subscription/event listener bị đăng ký nhiều lần
- ACS client/resource lifecycle sai
- Backend API và ACS responsibility bị trộn lẫn
- Public API khó sử dụng
- API dễ bị breaking change
- UI component khó custom
- Library consumer bị phụ thuộc implementation detail
- Abstraction không cần thiết
- Over-engineering
- Under-engineering

---

# 2. Review Architecture

Hãy phân tích kiến trúc hiện tại trước khi review từng file.

## Kiểm tra

### 2.1 Separation of Concerns

Xác định rõ:

- UI
- State
- Domain/business logic
- Repository
- API client
- ACS client
- Realtime event handling
- Cache
- Local storage
- Models
- DTO
- Mapper
- Error handling
- Configuration
- Dependency injection

Kiểm tra xem một class có đang làm quá nhiều responsibility hay không.

Ví dụ:

```text
Widget
 ├── gọi API
 ├── gọi ACS
 ├── parse response
 ├── update state
 ├── xử lý pagination
 ├── xử lý realtime
 └── xử lý error
```

Nếu phát hiện pattern tương tự, hãy đánh dấu là vấn đề architecture.

---

# 3. Folder / Module Structure

Review cấu trúc project.

Đánh giá:

- Folder structure
- Feature boundaries
- Dependency direction
- Naming
- File size
- Class size
- Module coupling
- Circular dependency
- Shared/common code
- Internal/private implementation
- Public API

Hãy trả lời:

1. Cấu trúc hiện tại có dễ tìm code không?
2. Developer mới có thể hiểu architecture nhanh không?
3. Khi bug xảy ra, developer có biết cần tìm ở đâu không?
4. Feature mới có thể thêm mà không ảnh hưởng feature cũ không?
5. Có module nào đang quá lớn không?
6. Có module nào đang chứa nhiều responsibility không?

Nếu cần refactor structure, đề xuất structure cụ thể.

Ví dụ:

```text
lib/
├── chat_sdk.dart
├── src/
│   ├── core/
│   ├── domain/
│   ├── data/
│   ├── realtime/
│   ├── presentation/
│   └── infrastructure/
└── ...
```

Không bắt buộc sử dụng structure trên. Hãy đề xuất structure phù hợp với source code thực tế.

---

# 4. ACS Integration Review

Review đặc biệt kỹ phần Azure Communication Services.

Kiểm tra:

- ACS client initialization
- ACS client lifecycle
- Chat thread lifecycle
- Message lifecycle
- Realtime notification
- Event listener
- Event subscription
- Event unsubscription
- Connection state
- Authentication/token lifecycle
- Token refresh
- Token expiration
- Thread initialization
- Message loading
- Message sending
- Message editing
- Message deletion
- Read receipt
- Typing indicator
- Participant management
- Group chat
- Pagination
- Reconnection

Đặc biệt kiểm tra:

> Có trường hợp ACS listener được register nhiều lần không?

Ví dụ:

```dart
init() {
  client.onMessage.addListener(...);
}
```

Nếu `init()` được gọi nhiều lần thì có tạo duplicate listener không?

Kiểm tra:

```text
init
dispose
re-init
background
foreground
reconnect
logout
login
switch conversation
```

---

# 5. API Efficiency

Đây là phần **ưu tiên rất cao**.

Hãy audit toàn bộ API/network call.

Tìm:

- Duplicate request
- Request được gọi nhiều lần
- API call trong `build()`
- API call do rebuild
- API call do lifecycle callback
- API call do state update
- API call bị trigger bởi nhiều layer
- API call không cần thiết
- API call có thể cache
- API call có thể batch
- API call có thể deduplicate
- API call có thể reuse result
- API call bị gọi lại khi screen resume
- API call bị gọi lại khi widget rebuild
- API call bị gọi lại khi pagination
- API call bị race condition
- Concurrent request tới cùng resource

Ví dụ cần phát hiện:

```text
Widget
 → Provider
   → Repository
      → API
```

nhưng cùng lúc:

```text
Service
 → Repository
    → API
```

dẫn tới duplicate request.

---

# 6. Request Deduplication

Kiểm tra các trường hợp:

```text
Request A đang pending
Request A được gọi lại
→ có tạo Request B không?
```

Nếu không cần thiết, đề xuất cơ chế:

```text
in-flight request
request cache
request deduplication
mutex/lock
single-flight
```

Đặc biệt chú ý:

- Conversation detail
- Message list
- Participants
- User profile
- Unread count
- Token
- Chat thread initialization

---

# 7. Pagination Review

Review pagination thật kỹ.

Kiểm tra:

- Duplicate message
- Missing message
- Ordering
- Cursor handling
- Page loading state
- Concurrent pagination
- Load more khi request trước chưa hoàn thành
- Pull-to-refresh
- Realtime message + pagination interaction
- Deleted message
- Edited message
- Message inserted giữa các page

Ví dụ:

```text
Page 1
A B C D

Realtime:
X

Load Page 2:
D E F G
```

Đảm bảo:

```text
X A B C D E F G
```

không bị:

```text
X A B C D D E F G
```

---

# 8. Realtime Event Review

Review toàn bộ realtime flow.

Phân tích:

```text
ACS Event
    ↓
Event Handler
    ↓
State
    ↓
Repository / Cache
    ↓
UI
```

Kiểm tra:

- Duplicate event
- Event ordering
- Event replay
- Event mất
- Event xử lý nhiều lần
- Event tới sau dispose
- Event tới khi conversation không còn active
- Event tới trong lúc pagination
- Event tới trong lúc refresh
- Event tới trước khi initialization hoàn tất
- Race condition giữa REST API và realtime event

Đặc biệt kiểm tra:

```text
REST response
+
Realtime event
```

có thể tạo duplicate state hay không.

---

# 9. Async / Concurrency Review

Audit toàn bộ:

- `Future`
- `async/await`
- `Stream`
- `StreamSubscription`
- `Timer`
- `Completer`
- `Future.wait`
- `Isolate`
- callback
- event listener

Tìm:

```text
race condition
deadlock
duplicate execution
late execution
cancel không đúng
dispose không đúng
```

Đặc biệt tìm:

```dart
await something();

if (!mounted) {
  ...
}
```

và những trường hợp tương đương trong non-Widget class.

Kiểm tra async operation có thể chạy sau khi object bị dispose hay không.

---

# 10. Lifecycle & Memory Leak

Audit lifecycle của:

- Widget
- Controller
- ViewModel
- Provider
- Repository
- ACS client
- Stream
- StreamSubscription
- Timer
- ScrollController
- TextEditingController
- AnimationController
- FocusNode
- Event listener
- ChangeNotifier
- ValueNotifier

Tìm:

```text
listener không remove
subscription không cancel
controller không dispose
timer không cancel
ACS listener không unregister
object giữ reference tới object khác quá lâu
```

Đánh giá khả năng:

```text
Memory Leak
Resource Leak
Zombie Object
Zombie Listener
Zombie Request
```

---

# 11. Crash Risk Review

Tìm tất cả potential crash.

Đặc biệt:

```dart
!
.first
.single
[index]
late
cast
as
```

và:

- Null handling
- Empty list
- Invalid state
- Race condition
- Unexpected backend response
- Unexpected ACS response
- Widget disposed
- Missing initialization
- Invalid configuration
- Token expired
- Network failure
- Reconnection failure

Mỗi potential crash phải chỉ rõ:

```text
File
Class
Method
Problem
Scenario
Impact
Fix
```

---

# 12. Error Handling

Review error architecture.

Kiểm tra:

- Exception type
- Domain error
- Network error
- ACS error
- Authentication error
- Authorization error
- Timeout
- Cancellation
- Parse error
- Unknown error

Không nên có:

```dart
catch (_) {}
```

hoặc:

```dart
catch (e) {
  print(e);
}
```

nếu khiến error bị mất.

Đề xuất error flow:

```text
Infrastructure Error
        ↓
Repository Error
        ↓
Domain Error
        ↓
Public SDK Error
        ↓
Application/UI
```

---

# 13. Retry / Timeout / Cancellation

Review:

- Retry policy
- Retry count
- Backoff
- Timeout
- Cancellation
- Network recovery

Phát hiện:

```text
infinite retry
retry request không cần thiết
retry request không idempotent
retry khi authentication failed
retry khi user logout
```

Đề xuất strategy phù hợp.

---

# 14. State Management

Review cách quản lý state.

Đánh giá:

- State ownership
- State mutation
- Immutable state
- Derived state
- Loading state
- Error state
- Empty state
- Pagination state
- Realtime state
- Conversation switching
- Multi-conversation state

Tìm các state không có source of truth rõ ràng.

Ví dụ:

```text
Widget A có message list
Controller B cũng có message list
Repository C cũng có message list
```

Đánh giá nguy cơ state inconsistency.

---

# 15. UI Architecture

Thư viện phải cung cấp UI sẵn nhưng vẫn phải dễ custom.

Review:

- Widget hierarchy
- Component responsibility
- Rebuild
- State/UI separation
- Theme
- Styling
- Layout
- Accessibility
- Localization
- Empty state
- Loading state
- Error state

Kiểm tra widget có quá nhiều logic không.

Ví dụ không nên:

```dart
ChatScreen
 ├── API
 ├── ACS
 ├── pagination
 ├── realtime
 ├── state
 ├── message parsing
 └── UI
```

---

# 16. UI Customization API

Đây là một tiêu chí quan trọng.

Đánh giá thư viện có cho phép consumer:

### Option A – Dùng UI mặc định

```dart
ChatView(
  conversationId: id,
);
```

### Option B – Customize một phần

```dart
ChatView(
  messageBuilder: ...,
  inputBuilder: ...,
  appBarBuilder: ...,
);
```

### Option C – Tự xây dựng UI

Consumer có thể sử dụng:

```dart
chatController.messages
chatController.sendMessage(...)
chatController.loadMore(...)
chatController.retry(...)
chatController.markAsRead(...)
```

Hãy đánh giá API hiện tại có hỗ trợ tốt cả 3 level này không.

---

# 17. Public API Review

Review những API mà library expose ra ngoài.

Đặc biệt:

```text
ChatClient
ChatService
ChatController
ChatRepository
ChatMessage
Conversation
Participant
ChatState
ChatError
```

Đánh giá:

- API có dễ hiểu không?
- Naming có nhất quán không?
- API có expose implementation detail không?
- Consumer có bị phụ thuộc ACS SDK trực tiếp không?
- Consumer có cần hiểu internal architecture không?
- API có quá nhiều method không?
- API có method dư thừa không?
- API có nguy cơ breaking change không?
- API có dễ mock/test không?

---

# 18. Avoid Leaking ACS Implementation

Đặc biệt kiểm tra:

> Library có đang expose trực tiếp ACS model/object ra public API hay không?

Ví dụ cần xem xét:

```dart
Future<ChatMessageModel> getMessage();
```

trong đó `ChatMessageModel` phụ thuộc trực tiếp ACS.

Ưu tiên đánh giá abstraction:

```text
ACS
 ↓
ACS Adapter
 ↓
Library Domain Model
 ↓
Public API
```

Mục tiêu:

> Consumer không nên phải biết implementation phía dưới đang sử dụng ACS như thế nào.

---

# 19. Performance Review

Audit performance:

- Widget rebuild
- ListView
- ListView.builder
- Sliver
- Message list
- Large conversation
- Image/file message
- Avatar
- Video
- Attachment
- Scroll
- Pagination
- Memory
- Serialization
- JSON parsing
- Object allocation
- Stream event frequency

Đặc biệt kiểm tra chat conversation có:

```text
1,000 messages
5,000 messages
10,000 messages
```

thì library có vấn đề gì không.

---

# 20. Resource Management

Review:

- Memory
- Network
- CPU
- Disk
- Cache
- Image cache
- Stream
- Timer
- Subscription
- Controller
- HTTP client
- ACS client

Mục tiêu:

> Không giữ resource lâu hơn thời gian cần thiết.

---

# 21. Caching

Đánh giá có nên cache:

- Conversation
- Message
- Participant
- User
- Avatar
- Unread count
- Token
- Thread metadata

Kiểm tra:

```text
Cache invalidation
Cache TTL
Memory cache
Persistent cache
Realtime invalidation
```

Không được đề xuất cache chỉ để "tăng performance" nếu nó làm architecture phức tạp không cần thiết.

---

# 22. Security Review

Kiểm tra:

- Token
- Access token
- Sensitive data
- Logging
- Exception
- API credentials
- Storage
- User data
- Message content

Đặc biệt:

```text
Không log token
Không log sensitive information
Không expose credential
```

---

# 23. Testability

Đánh giá khả năng unit test.

Các thành phần quan trọng phải có thể test độc lập:

```text
Repository
Service
UseCase
State
Controller
Message mapper
Pagination
Realtime event handler
Error handling
```

Kiểm tra dependency có dễ mock không.

---

# 24. Code Quality

Review:

- Naming
- Function size
- Class size
- Nesting
- Duplication
- Comments
- Magic number
- Magic string
- Constants
- Extension
- Utility
- Generic abstraction
- SOLID
- DRY
- KISS
- YAGNI

Không áp dụng SOLID một cách máy móc.

Nếu abstraction làm code khó hiểu hơn nhưng không mang lại lợi ích thực tế, hãy đánh dấu là:

```text
Over-engineering
```

---

# 25. API Call & Resource Matrix

Hãy tạo bảng:

| Operation         | Current API Call | Trigger | Có dư thừa? | Cache? | Deduplicate? | Risk |
| ----------------- | ---------------- | ------- | ----------- | ------ | ------------ | ---- |
| Load conversation | ...              | ...     | ...         | ...    | ...          | ...  |
| Load messages     | ...              | ...     | ...         | ...    | ...          | ...  |
| Send message      | ...              | ...     | ...         | ...    | ...          | ...  |
| Mark as read      | ...              | ...     | ...         | ...    | ...          | ...  |
| Load participants | ...              | ...     | ...         | ...    | ...          | ...  |
| Realtime event    | ...              | ...     | ...         | ...    | ...          | ...  |

---

# 26. Lifecycle Matrix

Tạo matrix:

| Lifecycle           | Expected Behavior | Current Behavior | Risk |
| ------------------- | ----------------- | ---------------- | ---- |
| Initialize          | ...               | ...              | ...  |
| Open conversation   | ...               | ...              | ...  |
| Switch conversation | ...               | ...              | ...  |
| Background          | ...               | ...              | ...  |
| Foreground          | ...               | ...              | ...  |
| Logout              | ...               | ...              | ...  |
| Login again         | ...               | ...              | ...  |
| Dispose             | ...               | ...              | ...  |
| Reconnect           | ...               | ...              | ...  |

---

# 27. Critical Scenarios

Hãy kiểm tra source code dựa trên các scenario thực tế sau:

## Scenario 1

```text
Open Chat
→ API load messages
→ realtime event
→ close Chat
```

## Scenario 2

```text
Open Chat
→ close Chat
→ open Chat lại
```

## Scenario 3

```text
Open Chat
→ background app
→ foreground
```

## Scenario 4

```text
Open Chat
→ OS kill app
→ open app lại
```

## Scenario 5

```text
Open Chat
→ switch conversation
→ switch lại conversation cũ
```

## Scenario 6

```text
Load messages
→ user scroll lên
→ load more
→ realtime message tới cùng lúc
```

## Scenario 7

```text
Send message
→ network slow
→ retry
```

## Scenario 8

```text
Send message
→ network disconnected
→ reconnect
```

## Scenario 9

```text
Token expired
→ API call
→ refresh token
→ retry
```

## Scenario 10

```text
Widget disposed
→ async operation complete
```

Tìm potential bug trong từng scenario.

---

# 28. Critical Bug Classification

Mỗi issue phải được phân loại:

### P0 – Critical

Có thể:

- Crash app
- Memory leak nghiêm trọng
- Data loss
- Duplicate message nghiêm trọng
- Infinite request
- Infinite retry
- Security issue

### P1 – High

Có thể:

- Sai state
- API request dư thừa đáng kể
- Realtime sai
- Pagination sai
- Resource leak
- UX nghiêm trọng

### P2 – Medium

- Maintainability
- Performance
- Code duplication
- Architecture
- Testability

### P3 – Low

- Naming
- Style
- Minor refactor

---

# 29. Output Format

Không chỉ nói:

> "Code này nên refactor."

Phải chỉ rõ:

```text
Issue:
File:
Class:
Method:
Severity:
Category:

Current behavior:
...

Problem:
...

Why it is dangerous:
...

Reproduction scenario:
...

Recommended solution:
...

Example:
...
```

---

# 30. Review Result

Cuối cùng hãy tạo báo cáo theo structure:

# Chat Library Code Review

## 1. Executive Summary

Đánh giá tổng quan:

```text
Architecture: X/10
Maintainability: X/10
Readability: X/10
Performance: X/10
API Efficiency: X/10
Memory Safety: X/10
Crash Safety: X/10
Testability: X/10
Extensibility: X/10
UI Customizability: X/10
Public API Design: X/10
Production Readiness: X/10
```

---

## 2. Architecture Assessment

Đánh giá:

- Điểm mạnh
- Điểm yếu
- Architectural smell
- Coupling
- Responsibility
- Dependency direction

---

## 3. Critical Issues

Liệt kê P0/P1 trước.

---

## 4. API Efficiency Issues

Liệt kê toàn bộ:

- Duplicate API
- Unnecessary API
- Race condition
- Missing cache
- Missing deduplication

---

## 5. Memory / Resource Issues

Liệt kê:

- Memory leak
- Listener leak
- Stream leak
- Timer leak
- Controller leak
- ACS resource leak

---

## 6. Crash / Reliability Issues

Liệt kê potential crash và unstable behavior.

---

## 7. Realtime / ACS Issues

Đánh giá riêng ACS integration.

---

## 8. UI Architecture

Đánh giá:

- Default UI
- Custom UI
- Widget composition
- Rebuild
- State separation

---

## 9. Public API Review

Đánh giá API dành cho library consumer.

---

## 10. Performance Review

Đánh giá performance trong:

```text
small chat
medium chat
large chat
```

---

## 11. Testability

Đánh giá khả năng test và đề xuất test cases còn thiếu.

---

# 31. Refactoring Priority

Tạo bảng:

| Priority | Issue | File | Impact   | Effort | Recommendation |
| -------- | ----- | ---- | -------- | ------ | -------------- |
| P0       | ...   | ...  | Critical | Medium | ...            |
| P1       | ...   | ...  | High     | Low    | ...            |
| P2       | ...   | ...  | Medium   | Medium | ...            |

---

# 32. Recommended Target Architecture

Sau khi review, hãy đề xuất:

```text
Current Architecture
        ↓
Problems
        ↓
Target Architecture
        ↓
Migration Steps
```

Target architecture phải ưu tiên:

1. Dễ hiểu
2. Dễ debug
3. Dễ test
4. Dễ maintain
5. Ít coupling
6. Không API call dư thừa
7. Không resource leak
8. Không crash
9. Dễ mở rộng
10. Dễ custom UI
11. Public API rõ ràng
12. Không expose implementation detail

---

# 33. Migration Plan

Không đề xuất rewrite toàn bộ nếu không cần.

Chia thành:

### Phase 1 – Critical Fixes

Fix:

- Crash
- Memory leak
- API duplicate
- Race condition
- Data consistency

### Phase 2 – Architecture

Refactor:

- Responsibility
- Dependency
- Repository
- State
- ACS adapter

### Phase 3 – UI

Refactor:

- Widget
- Component
- Theme
- Customization API

### Phase 4 – Public API

Ổn định:

- Public interfaces
- Models
- Errors
- Controllers
- Extension points

### Phase 5 – Testing

Bổ sung:

- Unit tests
- Integration tests
- Widget tests
- Lifecycle tests
- Realtime tests
- Pagination tests
- Failure tests

---

# 34. Rules khi Review

Tuân thủ các nguyên tắc:

### Rule 1

**Không refactor chỉ để code "đẹp hơn".**

Refactor phải có lý do cụ thể:

```text
Maintainability
Performance
Reliability
Testability
Extensibility
```

### Rule 2

Ưu tiên:

```text
Correctness
→ Reliability
→ Resource efficiency
→ Maintainability
→ Performance
→ Readability
→ Style
```

### Rule 3

Không tạo abstraction nếu abstraction không mang lại giá trị thực tế.

### Rule 4

Không sử dụng pattern chỉ vì "best practice".

Phải giải thích:

```text
Problem
→ Why current implementation is bad
→ Why proposed solution solves it
```

### Rule 5

Không chỉ review từng file độc lập.

Phải review **flow xuyên suốt**:

```text
UI
→ Controller
→ Service
→ Repository
→ Backend / ACS
→ Realtime
→ State
→ UI
```

### Rule 6

Nếu code hiện tại đã tốt, hãy nói rõ:

```text
KEEP
```

Không refactor unnecessary.

### Rule 7

Nếu có nhiều cách sửa, hãy so sánh:

```text
Option A
Option B
Option C
```

và chọn option phù hợp nhất cho library.

---

# 35. Final Goal

Sau review, tôi muốn có câu trả lời rõ ràng cho:

> "Nếu publish thư viện này cho nhiều Flutter application sử dụng, phần nào có thể gây lỗi production?"

và:

> "Tôi cần sửa gì trước khi publish?"

Cuối báo cáo phải có:

# Production Readiness Verdict

Một trong:

```text
❌ NOT READY
⚠️ READY WITH MAJOR FIXES
🟡 READY WITH MINOR FIXES
✅ PRODUCTION READY
```

Kèm theo:

```text
Must Fix Before Release:
1.
2.
3.

Should Fix:
1.
2.
3.

Nice to Have:
1.
2.
3.
```

---

# Important

Hãy **đọc và hiểu toàn bộ source code trước khi đưa ra kết luận**.

Không đánh giá chỉ dựa trên một vài file.

Khi phát hiện một issue, hãy trace dependency và flow liên quan để xác định impact thực tế.

Đặc biệt ưu tiên tìm các bug dạng:

```text
Duplicate API call
Race condition
Memory leak
Event listener duplication
Async-after-dispose
State inconsistency
Realtime + REST conflict
Pagination bug
Token lifecycle bug
Resource leak
Crash
Infinite retry
Unnecessary rebuild
```

Mục tiêu cuối cùng không phải là tạo ra code "cầu kỳ" mà là:

> **Một Flutter Chat Library có architecture rõ ràng, code dễ đọc, dễ debug, dễ test, ít API call dư thừa, sử dụng resource hợp lý, ổn định khi chạy realtime, khó crash, dễ maintain, dễ mở rộng và có Public API đủ tốt để consumer vừa dùng UI có sẵn vừa có thể tự xây dựng UI riêng.**
