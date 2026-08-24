# Chat Native Platform Interface — Review Part 5

> **Ngày review:** 2026-08-24  
> **Commit hiện tại:** `1b83532` (`feature/phase-02`)  
> **Prompt áp dụng:** `review/prompt.md`  
> **Phạm vi:** `chat-module-mvp/packages/chat_native_platform_interface` tại HEAD và snapshot nguồn cuối cùng trước khi bị xoá.

## 1. Kết luận chính

```text
❌ KHÔNG THỂ ĐÁNH GIÁ PRODUCTION-READY Ở TRẠNG THÁI HIỆN TẠI — package không còn source ở HEAD
```

- Tại HEAD `1b83532`, Git không còn file nào của package này. Toàn bộ 9 file, tương đương 560 dòng, đã bị xoá trong commit `8f8991d` sau khi realtime chuyển sang WebSocket backend. Đây là hướng kiến trúc đúng nếu `WebSocketRealtimeDataSource*` là đường dẫn production duy nhất.
- Thư mục package vẫn tồn tại trên máy local nhưng chỉ chứa artifact không được track: `.dart_tool/pubspec.lock`. Điều này dễ gây hiểu nhầm rằng package vẫn active; nên xoá artifact local và tránh commit thư mục rỗng này.
- Vì prompt yêu cầu review toàn bộ source, báo cáo này cũng đánh giá snapshot nguồn cuối cùng tại `8f8991d^` để giữ lại các bài học quan trọng và kiểm soát rủi ro nếu code native ACS được khôi phục hoặc copy vào module khác.
- Snapshot cuối chỉ là một plugin cầu nối nhỏ với ranh giới trách nhiệm tốt, nhưng chưa đạt chuẩn production SDK: thiếu state machine, lỗi realtime bị nuốt, có race khi re-initialize, payload parsing dễ crash và không có automated test.

## 2. Bảng tổng hợp vấn đề

| ID | Mức độ | Vấn đề | Trạng thái tại HEAD | Đánh giá |
|---|:--:|---|:--:|---|
| N-Q5-001 | P2 | Package đã bị xoá khỏi Git nhưng vẫn còn thư mục/artifact local và tài liệu tham chiếu lịch sử | ❌ Cần dọn dẹp | Không ảnh hưởng runtime nếu Git tree sạch, nhưng gây nhầm lẫn khi duyệt workspace |
| N-Q5-002 | P1 | Concurrent/repeated `initialize` có thể leak client hoặc register handler sai client trong snapshot cũ | N/A — đã xoá | Bắt buộc sửa nếu khôi phục code |
| N-Q5-003 | P1 | `initialize` trả về thành công trước khi realtime thực sự start; lỗi start/token chỉ log | N/A — đã xoá | Consumer không thể biết kết nối fail |
| N-Q5-004 | P1 | iOS có thể gọi stale `eventSink` sau khi listener cancel/engine detach | N/A — đã xoá | Crash/error tiềm ẩn |
| N-Q5-005 | P1 | Dart parser dùng cast trực tiếp và không có event schema/lifecycle error | N/A — đã xoá | Payload sai làm chết stream |
| N-Q5-006 | P2 | Android chạy init bằng raw thread không quản lý generation/detach | N/A — đã xoá | Zombie init/client sau engine detach |
| N-Q5-007 | P2 | Android gửi `Date.toString()` vào field tên `createdAtIso8601` | N/A — đã xoá | Format khác ISO 8601 và lệch giữa hai platform |
| N-Q5-008 | P2 | API contract sai/thừa: `acsUserId` ignored, `deletedOn` không được emit, mô tả token refresh không đúng implementation | N/A — đã xoá | Public API gây hiểu nhầm |
| N-Q5-009 | P2 | Nhiều instance Dart dùng chung global channels nhưng mỗi instance cache stream riêng | N/A — đã xoá | Listener thứ hai có thể bị mất event |
| N-Q5-010 | P2 | Cancel listener cuối không tự stop ACS; việc stop phụ thuộc host gọi đúng lifecycle | N/A — đã xoá | Dễ leak connection/pin/network |
| N-Q5-011 | P2 | Không có Dart/native/integration test cho channel, token refresh, re-init, reconnect và background/foreground | N/A — đã xoá | Chưa đủ điều kiện đóng gói SDK |

## 3. Kiến trúc snapshot cuối

### 3.1 Điểm tốt

- Package giữ đúng ranh giới mỏng: chỉ khởi tạo ACS realtime và forward `chatMessageReceived`, không chứa UI, REST hay business logic.
- Payload qua `EventChannel` được thu gọn thành các field cần thiết thay vì serialize object của ACS SDK.
- Channel name rõ ràng và nhất quán trên Android/iOS/Dart.
- README ghi rõ minSdk, iOS version, dependency ACS và các kịch bản test tay cần thiết.
- Plugin cố gắng cleanup client và handler trong `onDetachedFromEngine`.

### 3.2 Hạn chế kiến trúc

Snapshot cũ chỉ hỗ trợ đúng một loại event: tin nhắn mới. Các yêu cầu trong prompt như connection state, reconnect status, typing indicator, read receipt, edit/delete message và participant management đều không có contract riêng. Nếu tầng WebSocket mới đảm nhận các phần đó thì chấp nhận được; ngược lại, đây là under-engineering nghiêm trọng đối với một chat SDK production.

Thiết kế hiện tại cũng đẩy toàn bộ ownership lifecycle sang host app: host phải nhớ listen stream, gọi `initialize`, gọi `stopRealtimeNotifications`, refresh token rồi initialize lại đúng lúc. Một public SDK nên cung cấp state machine rõ ràng và callback lỗi thay vì chỉ trả `Future<void>`.

## 4. Phân tích chi tiết

### 4.1 N-Q5-002 — Race khi initialize nhiều lần — P1

Android `initializeChatClientAsync` tạo một raw `Thread` cho mỗi lần gọi:

```kotlin
Thread {
    try {
        initializeChatClient(context, token, endpoint)
        Handler(Looper.getMainLooper()).post { result.success(null) }
    } catch (e: Exception) {
        ...
    }
}.start()
```

Bên trong `initializeChatClient`, luồng A và B đều có thể chạy đoạn `stopRealtimeNotifications()` gần như đồng thời, sau đó cùng build/start client. Khi luồng A gán `chatClient = clientA` rồi luồng B gán `chatClient = clientB`, `clientA` không còn reference để stop và trở thành zombie connection/handler.

iOS có biến thể nguy hiểm khác. Completion của lần start cũ capture `[weak self]`; nếu token refresh tạo `clientB` trước khi completion của `clientA` chạy, callback cũ thấy `self?.chatClient` đang là `clientB` và có thể register event lên nhầm client mới. Điều này gây duplicate handler hoặc đăng ký sai lifecycle.

**Khuyến nghị:** đưa mọi transition vào một state machine serialized trên executor/queue riêng và gắn `generationId` cho từng lần initialize. Callback cũ phải so sánh generation trước khi register, emit event hoặc mutate state. Đồng thời chặn hoặc queue request khi đang `initializing/stopping`.

### 4.2 N-Q5-003 — Lỗi realtime bị nuốt — P1

Cả hai nền tảng trả về thành công ngay sau khi gọi start, dù quá trình start là asynchronous:

```kotlin
client.startRealtimeNotifications(context) { throwable ->
    Log.w(TAG, "Realtime error: ${throwable.message}", throwable)
}
```

```swift
case .failure(let error):
    NSLog("ChatNative: startRealTimeNotifications failed: %@", error.localizedDescription)
```

Dart chỉ nhận `Future<void>` và không có stream/connection state cho lỗi khởi tạo, token hết hạn hay reconnect failure. Với SDK public, đây là lỗi quan sátability: ứng dụng sẽ tưởng realtime sẵn sàng, trong khi gateway connect hoặc token validation có thể đã thất bại.

**Khuyến nghị:** `initialize` phải hoàn tất khi realtime start thật sự success hoặc thất bại với error code có cấu trúc. Ngoài ra cần expose ít nhất `connectionState`: `uninitialized`, `initializing`, `ready`, `reconnecting`, `failed`, `stopped`.

### 4.3 N-Q5-004 — Stale event sink trên iOS — P1

`handleChatEvent` đọc `eventSink` trên background callback, sau đó dispatch closure đã capture sink:

```swift
guard let eventSink = eventSink else { return }
...
DispatchQueue.main.async { eventSink(payload) }
```

Giữa thời điểm guard và closure chạy trên main queue, listener có thể đã cancel hoặc engine detach, khiến `eventSink` cũ vẫn được gọi. Flutter EventChannel không cho phép gửi event sau completion/cancel.

**Khuyến nghị:** dispatch payload về main trước, rồi đọc lại `self?.eventSink` bên trong closure. Sau đó validate state/generation trước khi gọi sink.

### 4.4 N-Q5-005 — Dart parser không an toàn — P1

```dart
_eventChannel.receiveBroadcastStream()
  .map((event) => NativeChatMessageEvent.fromMap(event as Map));
```

`fromMap` cast trực tiếp mọi field bắt buộc sang `String`. Một native payload thiếu field, sai type hoặc platform gửi shape mới sẽ ném `TypeError` vào stream. Với broadcast stream, lỗi parsing có thể terminate listener và SDK không có cơ chế phân biệt lỗi dữ liệu với lỗi connection.

**Khuyến nghị:** tách decoder defensive: kiểm tra `Map`, field type, null/rỗng và giá trị hợp lệ. Public model nên trả về typed parse result hoặc emit event envelope `{schemaVersion, eventType, payload, error?}` thay vì để exception không kiểm soát đi qua channel.

### 4.5 N-Q5-006 — Android init thread không quản lý vòng đời — P2

Raw `Thread` không lưu reference, không đặt tên, không cancel và không kiểm tra generation. Nếu engine detach trong lúc network call đang chạy, luồng vẫn có thể build client, start notification, register handler và post result về channel đã detach. Việc set `applicationContext = null` không huỷ được work đang chạy vì context đã được truyền vào closure.

**Khuyến nghị:** dùng single background executor có lifecycle rõ ràng, lưu job/task theo generation và kiểm tra `isAttached` trước khi mutate plugin hoặc trả result.

### 4.6 N-Q5-007 — Timestamp không đồng nhất — P2

Android gửi:

```kotlin
"createdAt" to messageEvent.createdOn.toString()
```

Nhưng Dart đặt tên field là `createdAtIso8601`. `java.util.Date.toString()` thường trả format kiểu `Mon Aug 24 ... GMT+07:00`, không phải ISO 8601. iOS dùng `requestString`, nên hai platform không đảm bảo cùng một contract.

**Khuyến nghị:** chọn wire format rõ ràng, ví dụ epoch milliseconds hoặc chuỗi UTC ISO 8601 do plugin tự format, rồi document trong schema chung cho cả Android/iOS.

### 4.7 N-Q5-008 — Public API lệch thực tế — P2

Các điểm lệch cụ thể trong snapshot cuối:

- Dart yêu cầu `acsUserId`, nhưng Kotlin/Swift không đọc hay sử dụng giá trị này.
- Model khai báo `deletedOnIso8601`, nhưng native không gửi key `deletedOn`; do đó soft-delete không thể xảy ra qua path này.
- README nói refresh token khiến native “tự update credential, không tạo lại toàn bộ connection”, nhưng implementation luôn stop old client rồi tạo `ChatClient` mới.

**Khuyến nghị:** bỏ parameter không dùng hoặc dùng nó để validate identity. Nếu không hỗ trợ delete event, xoá field khỏi public model. Token refresh cần mô tả chính xác: tạo lại client và restart notification, kèm điều kiện chống re-init không cần thiết khi token không đổi.

### 4.8 N-Q5-009 — Multi-instance Dart không an toàn — P2

`ChatNativePlatformInterface` là class instantiable, nhưng method/event channel là global per engine. Hai instance Dart có thể tạo hai broadcast stream từ cùng một `EventChannel`; native chỉ giữ một `eventSink`, nên `onListen` của instance sau ghi đè sink của instance trước và `onCancel` của instance trước có thể làm instance sau ngắt event.

**Khuyến nghị:** nếu muốn một native connection phục vụ nhiều consumer, hãy cache stream ở static/application scope, cung cấp factory singleton hoặc inject chung một instance qua DI. Nếu cho phép nhiều connection độc lập, native phải hỗ trợ nhiều session và định danh channel/session rõ ràng.

### 4.9 N-Q5-010 — Resource lifecycle phụ thuộc caller — P2

Khi listener Dart cuối cùng cancel, native chỉ set `eventSink = nil/null`, không stop realtime. Điều này có thể chủ động để giữ connection cho các màn hình khác, nhưng README không đủ rành mạch về ownership và không có safety net ngoài engine detach. Host quên gọi stop khi app background sẽ giữ Trouter connection, tiêu pin/network và khó debug.

**Khuyến nghị:** chọn một policy rõ ràng: auto-stop khi listener cuối cancel, hoặc expose ref-counted session với `acquire/release`. Đồng thời thêm hook foreground/background và logging/state event để host có thể audit.

### 4.10 N-Q5-011 — Thiếu test — P2

Snapshot không có `test/`, integration test hay native unit test. README xác nhận phần native chỉ được test tay và chưa cover automated test. Với các lỗi concurrency, lifecycle và channel contract ở trên, đây là thiếu hụt blocking nếu package tiếp tục tồn tại.

Bộ test tối thiểu cần có:

- Dart decoder với payload hợp lệ, thiếu field, sai type, empty map.
- Multiple listener/multiple instance behavior.
- Initialize success/failure và callback sau timeout.
- Repeated/concurrent initialize và token refresh.
- Background/foreground, detach engine và cancel listener.
- Native integration thật cho receive, reconnect, token expiry.

## 5. Hiệu quả API và resource

Package không gọi REST business API, nên không có vấn đề duplicate conversation/message request nội bộ. Tuy nhiên mỗi lần `initialize` là một operation đắt đỏ: tạo credential/client và restart realtime notification. Vì vậy cần single-flight và tránh gọi lại khi token không đổi. Token refresh nên được trigger theo expiry thực tế, không theo widget rebuild hay screen resume.

## 6. Realtime correctness

Snapshot cũ không có deduplication, replay buffer hay ordering contract. Việc dedup ở tầng repository/UI có thể chấp nhận được, nhưng SDK cần document rõ guarantee: event có thể duplicate không, event nào bị hỗ trợ, event đến trước initialization hoàn tất được xử lý thế nào, và lỗi REST + realtime được reconcile ra sao.

Hiện tại chỉ có `chatMessageReceived`, nên không thể đáp ứng các use case edit/delete/read receipt/typing/participant/group lifecycle ở layer này. Nếu các feature đó thuộc backend WebSocket mới, cần một ADR ghi rõ ranh giới và ngăn việc tái sử dụng native ACS path song song mà không có coordination.

## 7. Trạng thái hiện tại và cleanup

Việc remove package trong `8f8991d` là quyết định kiến trúc hợp lý khi realtime đã chuyển về backend WebSocket. Tuy nhiên cần hoàn tất các việc sau:

1. Xoá artifact local `.dart_tool/pubspec.lock` của package đã remove; không giữ thư mục rỗng trông giống package active.
2. Thêm architectural decision record ngắn: package bị remove, replacement là `WebSocketRealtimeDataSource*`, native ACS không phải fallback runtime.
3. Rà soát tài liệu onboarding/cấu trúc để không mô tả native package là thành phần hiện hành.
4. Trong bản major, đổi tên alias `NativeRealtimeDataSource*` còn sót trong `chat_core` thành `WebSocket...` tương ứng để tránh nhầm với native bridge đã bị xoá.
5. Thêm lint/architecture test cấm import hoặc khôi phục dependency native ACS mà không qua decision mới.

## 8. Khuyến nghị ưu tiên

### Nếu package giữ nguyên trạng thái đã xoá

| Ưu tiên | Action |
|---|---|
| P2 | Dọn artifact local và cập nhật tài liệu cấu trúc/onboarding |
| P3 | Ghi ADR về việc loại bỏ native ACS realtime |
| P3 | Rename alias `NativeRealtimeDataSource*` trong major |

### Nếu bắt buộc khôi phục hoặc copy code này

| Ưu tiên | Action |
|---|---|
| P1 | Thêm connection state machine và serialize initialize/stop bằng generation guard |
| P1 | Trả kết quả initialize theo completion thật của ACS realtime, không swallow lỗi async |
| P1 | Sửa stale `eventSink` trên iOS và defensive decoding trên Dart |
| P2 | Chuẩn hoá timestamp/event schema và bỏ API fields không dùng |
| P2 | Định nghĩa ownership stop/reconnect/background và multi-listener policy |
| P2 | Bổ sung Dart unit tests, native tests và integration matrix thật thiết bị |

## 9. Verdict

```text
HEAD:        ✅ Remove native package — hợp lý, nhưng cần cleanup artifact/tài liệu
Snapshot cũ: ❌ Not production-ready nếu khôi phục nguyên trạng
Tổng thể:    ⚠️ Chỉ đóng gói production khi realtime duy nhất là WebSocket backend và các tham chiếu native còn sót được dọn sạch
```
