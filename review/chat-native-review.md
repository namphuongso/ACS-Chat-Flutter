# Chat Native Platform Interface Code Review (`packages/chat_native_platform_interface`)

> **Ngày review:** 2026-08-21  
> **Phạm vi review:** `packages/chat_native_platform_interface` (87 dòng Dart, 150 dòng Kotlin, 119 dòng Swift, 53 dòng Gradle, 35 dòng Podspec; tổng cộng ~444 LOC, 0 file test).  
> **Tiêu chuẩn review:** Theo `review/prompt.md` (Senior Flutter Architect / SDK & Native Bridge Engineer & Code Reviewer).  
> **Bản chất package:** Flutter Native Plugin / Platform Channel Bridge kết nối tới Azure Communication Services (ACS) Chat Native SDKs (Android Chat SDK 2.1.0 & iOS Chat SDK 1.3.7).

---

## 1. Executive Summary

| Tiêu chí | Điểm | Nhận xét chi tiết |
|---|:---:|---|
| **Architecture** | **3.0/10** | **Kiến trúc bị lệch thực tế nghiêm trọng (Dead Code / Identity Crisis)**. Package được thiết kế làm cầu nối ACS Realtime Native (Trouter), nhưng toàn bộ chat module đã chuyển sang WebSocket backend thuần Dart (`/ws/chat/view`). Plugin hiện hoàn toàn không được sử dụng ở tầng Flutter nhưng vẫn bị ép kéo theo các thư viện native nặng nề của Azure. Không tuân thủ chuẩn Federated Plugin (`plugin_platform_interface`). |
| **Maintainability** | **4.0/10** | Source code ngắn gọn (~444 LOC), comment nêu rõ mục tiêu gốc; tuy nhiên thiếu cấu trúc module hóa, không có test, phụ thuộc vào các thư viện native bên thứ ba (`AzureCommunicationChat`, `AzureCore 1.0.0-beta.16`) có vòng đời phát triển độc lập và dễ gây xung đột build. |
| **Readability** | **6.5/10** | Code Dart, Kotlin và Swift được viết rõ ràng, có chú thích nguồn gốc và đối chiếu SDK; tuy nhiên flow bất đồng bộ trên iOS và Android xử lý khác nhau gây khó hiểu cho người đọc. |
| **Performance** | **4.5/10** | Tải chỉ 1 event `chatMessageReceived` dạng map nhẹ; nhưng Android khởi tạo thread tự do (`Thread {}.start()`) không qua ThreadPool, và việc kéo theo bộ SDK Azure đồ sộ làm phình dung lượng app thêm 15–25 MB và tăng thời gian khởi động app. |
| **API Efficiency** | **4.0/10** | Chỉ expose 2 method (`initialize`, `stopRealtimeNotifications`) và 1 stream (`messageEvents`); thiếu hoàn toàn các event tối quan trọng như `connectionState`, `chatMessageDeleted`, `typingIndicator`, `readReceipt`. |
| **Memory Safety** | **5.0/10** | Khi `StreamSubscription` trên Dart bị cancel, native chỉ xóa tham chiếu `eventSink = null` mà **không hề ngắt kết nối Trouter/Azure**, làm rò rỉ socket mạng và hao pin ngầm; rủi ro race condition trên biến toàn cục `chatClient`. |
| **Crash Safety** | **5.5/10** | Dart `fromMap` ép kiểu thô bạo (`as String`) dễ crash nếu payload thiếu trường; Swift ném lỗi qua `NSLog` nhưng trả kết quả `success` giả tạo cho Dart; Android có try-catch bọc luồng nhưng thread leak. |
| **Testability** | **1.0/10** | **0% Test Coverage (0 dòng test)**. Không có Unit Test cho Dart interface, không có Mock Platform Channel, không có Android Robolectric / JUnit test, không có iOS XCTest. |
| **Extensibility** | **2.5/10** | Rất khó mở rộng. Payload đóng cứng, model `NativeChatMessageEvent` không có `copyWith`, không có đa hình event; nếu muốn hỗ trợ thêm event gõ phím hoặc xóa tin thì phải sửa đồng thời cả 3 ngôn ngữ (Dart, Kotlin, Swift). |
| **UI Customizability** | **N/A** | Package thuộc tầng Native Bridge / Platform Interface, không chứa UI component. |
| **Public API Design** | **3.5/10** | Không sử dụng `PlatformInterface` với token verification; `initialize` nhận `acsUserId` nhưng cả Android và iOS đều bỏ qua không dùng; không có stream báo lỗi hoặc trạng thái kết nối (`Stream<ConnectionState>`). |
| **Production Readiness** | **3.0/10** | **❌ NOT READY / KHUYẾN NGHỊ LOẠI BỎ (STRIP ACS LEGACY)** nếu tiếp tục dùng kiến trúc WebSocket Backend; hoặc **⚠️ READY WITH MAJOR FIXES** nếu bắt buộc phải duy trì làm SDK kết nối trực tiếp Azure ACS. |

---

## 2. Architecture Assessment

### 2.1 Sơ đồ Thực tế & Bất cập Kiến trúc (Architectural Drift)

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        KIẾN TRÚC MONG MUỐN GỐC                         │
│                                                                        │
│   chat_ui  ──►  chat_core  ──►  chat_native_platform_interface        │
│                                    │               │                   │
│                                    ▼ (Method/Event)▼                   │
│                              Android (Kotlin)   iOS (Swift)            │
│                              [Azure SDK 2.1]   [Azure SDK 1.3]         │
│                                    │               │                   │
│                                    ▼               ▼                   │
│                              Azure Communication Services (Trouter)    │
└────────────────────────────────────────────────────────────────────────┘

                                    VS

┌────────────────────────────────────────────────────────────────────────┐
│                        THỰC TẾ VẬN HÀNH HIỆN TẠI                       │
│                                                                        │
│   chat_ui  ──►  chat_core (NativeRealtimeDataSourceImpl)              │
│                     │                                                  │
│                     ├───────────────────────┐                          │
│                     ▼ (Chạy thật 100%)       ▼ (Bỏ hoang / Dead Code)  │
│             Backend WebSocket              chat_native_platform_      │
│             (ws/chat/view)                 interface                  │
│                     │                               │                  │
│                     ▼                               ▼                  │
│             Backend Server                 Kéo theo 20MB Azure SDK     │
│                                            vào APK/IPA nhưng KHÔNG DÙNG│
└────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Đánh giá Thực trạng Kiến trúc: Dead Code & Phụ thuộc Vô ích

1. **Dead Code hoàn toàn ở tầng Flutter:**
   - Trong toàn bộ codebase `chat-module-mvp`, vị trí duy nhất import `chat_native_platform_interface.dart` là tại dòng 5 của file `packages/chat_core/lib/features/thread/data/datasources/native_realtime_datasource_impl.dart`.
   - Tại đây, tham số `ChatNativePlatformInterface? platform` được khai báo trong constructor nhưng **hoàn toàn không được gán vào bất kỳ biến thành viên nào và không có dòng code nào gọi đến nó**.
   - Mọi hoạt động realtime thực tế đều do `web_socket_channel` kết nối trực tiếp tới endpoint WebSocket của backend nội bộ (`_socketUri(token)`).

2. **Chi phí và Hậu quả của việc giữ Dead Plugin:**
   - **Phình to App Bundle (Binary Bloat):** Host app bị ép buộc tải và biên dịch `com.azure.android:azure-communication-chat:2.1.0` (kéo theo `azure-communication-common`, Jakarta JSON, Netty/OkHttp, Jackson) trên Android và `AzureCommunicationChat 1.3.7` + `AzureCore 1.0.0-beta.16` trên iOS. Ứng dụng tăng kích thước từ 15 MB đến 30 MB một cách lãng phí.
   - **Xung đột Build Gradle:** ACS Android SDK kéo theo nhiều jar Jakarta gây lỗi trùng lặp file `META-INF/NOTICE.md`, buộc host app phải thêm cấu hình loại trừ `packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1,NOTICE.md}" } }`.
   - **Cảnh báo Build Tools & Khả năng Tương thích Tương lai:**
     - Android: Áp dụng trực tiếp `apply plugin: 'kotlin-android'` và `kotlin-gradle-plugin:1.9.22` trong subproject `build.gradle` (bị Flutter 3.19+ cảnh báo deprecation, sẽ fail trên các bản Flutter tương lai khi chuyển sang Gradle Declarative Plugins).
     - iOS: Chưa hỗ trợ Swift Package Manager (SPM), sử dụng phiên bản `AzureCore 1.0.0-beta.16` đã rất cũ.
   - **Gây nhầm lẫn nghiêm trọng cho Developer:** Tên gọi `NativeRealtimeDataSourceImpl`, `chat_native_platform_interface`, `ChatModuleConfig.acsEndpoint` làm mọi kỹ sư mới tin rằng hệ thống đang vận hành qua Azure Cloud, trong khi thực tế chạy qua WebSocket server riêng.

---

## 3. Detailed File-by-File Code Review

### 3.1 Dart Layer: `lib/chat_native_platform_interface.dart`

```dart
// File: lib/chat_native_platform_interface.dart (87 LOC)
```

#### A. Phân tích `NativeChatMessageEvent`
1. **Lỗi Ép kiểu không an toàn (`fromMap`):**
   ```dart
   factory NativeChatMessageEvent.fromMap(Map<dynamic, dynamic> map) {
     return NativeChatMessageEvent(
       threadId: map['threadId'] as String,
       messageId: map['messageId'] as String,
       senderId: map['senderId'] as String,
       senderDisplayName: map['senderDisplayName'] as String,
       content: map['content'] as String,
       createdAtIso8601: map['createdAt'] as String,
       deletedOnIso8601: map['deletedOn'] as String?,
     );
   }
   ```
   - **Rủi ro:** Nếu native trả về `null` cho `senderDisplayName` hoặc `content` (rất phổ biến trong các sự kiện hệ thống hoặc tin nhắn media rỗng), lệnh `map['...'] as String` sẽ lập tức ném ngoại lệ runtime `TypeError: Null is not a subtype of type 'String' in type cast`.
   - **Khắc phục:** Cần dùng fallback phòng thủ: `senderDisplayName: map['senderDisplayName'] as String? ?? ''`.

2. **Trường dữ liệu "ma" (`deletedOnIso8601`):**
   - Doc comment ghi chú: *"Thời điểm tin bị xoá trên ACS (soft-delete). Có giá trị khi native nhận được event xoá tin nhắn..."*
   - **Sự thật:** Cả Android `ChatNativePlugin.kt` và iOS `ChatNativePlugin.swift` **không hề lắng nghe event xoá tin nhắn** và **không hề gán key `'deletedOn'` vào payload map**. Trường này vĩnh viễn mang giá trị `null`.

3. **Thiếu các phương thức nền tảng của Entity:**
   - Thiếu `operator ==`, `hashCode`, `toString()` và `copyWith()`, khiến việc viết unit test, so sánh state hoặc debug log qua stream gặp nhiều khó khăn.

#### B. Phân tích `ChatNativePlatformInterface`
1. **Vi phạm chuẩn Federated Plugin của Flutter:**
   - Package không kế thừa từ `PlatformInterface` (của package `plugin_platform_interface`), không có cơ chế `verifyToken()`, không có instance tĩnh mặc định `PlatformInterface.instance`.
2. **Tham số dư thừa (`acsUserId`):**
   - Hàm `initialize({required String acsToken, required String acsUserId, required String endpoint})` đóng gói `userId` vào `Map` gửi qua MethodChannel. Tuy nhiên, cả Kotlin và Swift đều **hoàn toàn không đọc key `'userId'`**.
3. **Quản lý Stream Cache (`_cachedStream`) thiếu an toàn:**
   - `_cachedStream ??= _eventChannel.receiveBroadcastStream().map(...)`
   - Nếu gọi `stopRealtimeNotifications()` rồi sau đó gọi lại `initialize()`, biến `_cachedStream` vẫn giữ stream cũ. Nếu stream cũ đã bị đóng hoặc gặp lỗi, listener mới sẽ không nhận được dữ liệu.

---

### 3.2 Android Layer: `ChatNativePlugin.kt` & `build.gradle`

```kotlin
// File: android/src/main/kotlin/com/npp/chatnative/ChatNativePlugin.kt (150 LOC)
```

#### A. Khởi tạo Thread tự do gây Race Condition & Thread Leak (P0/P1)
```kotlin
// Dòng 85-95:
Thread {
    try {
        initializeChatClient(context, token, endpoint)
        Handler(Looper.getMainLooper()).post { result.success(null) }
    } catch (e: Exception) {
        Log.e(TAG, "Initialize realtime failed", e)
        Handler(Looper.getMainLooper()).post {
            result.error("NATIVE_INIT_FAILED", e.message, null)
        }
    }
}.start()
```
- **Vấn đề:** Khởi tạo raw Java `Thread` vô tội vạ mà không có ExecutorService hay Coroutine Scope quản lý.
- **Kịch bản Race Condition:**
  1. Khi người dùng refresh token liên tục hoặc chuyển đổi tài khoản, `initialize` được gọi 2 lần sát nhau.
  2. Hai Thread A và Thread B chạy song song. Thread B chạy trước gọi `stopRealtimeNotifications()` rồi tạo `clientB`.
  3. Thread A chạy chậm hơn, sau đó ghi đè `chatClient = clientA` (vốn đã bị client B stop).
  4. Hệ quả: `chatClient` lưu trữ một instance đã chết, luồng nhận tin nhắn bị vô hiệu hóa hoàn toàn.
- **Kịch bản Engine Detached:**
  - Nếu Flutter Engine detach (`onDetachedFromEngine`) trong lúc Thread đang chạy `initializeChatClient`, biến `applicationContext` đã bị set về `null`, nhưng Thread vẫn tiếp tục chạy ngầm, gọi `client.startRealtimeNotifications(context)` với biến context cục bộ, gây rò rỉ bộ nhớ (Memory Leak) và giữ socket mở ngầm.

#### B. Nuốt chửng lỗi Realtime (Error Swallowing)
```kotlin
// Dòng 111-113:
client.startRealtimeNotifications(context) { throwable ->
    Log.w(TAG, "Realtime error: ${throwable.message}", throwable)
}
```
- **Vấn đề:** Callback báo lỗi mất kết nối, rớt mạng, hoặc token hết hạn của Azure Trouter chỉ được ghi ra `Log.w`.
- **Hệ quả:** Phía Flutter Dart hoàn toàn "mù thông tin" khi kết nối realtime native bị đứt. Không có cách nào để UI hiển thị trạng thái "Đang kết nối lại..." hoặc kích hoạt cơ chế refresh token tự động.

#### C. Mất Event khi Flutter chưa kịp Listen (Event Dropping)
```kotlin
// Dòng 131:
Handler(Looper.getMainLooper()).post { eventSink?.success(payload) }
```
- **Vấn đề:** Nếu `initialize` hoàn tất và có tin nhắn tới trước khi Flutter kịp gọi `messageEvents.listen()` (lúc này `eventSink` vẫn là `null`), tin nhắn đó sẽ bị bỏ qua vĩnh viễn mà không có hàng đợi đệm (buffer/queue).

#### D. Không ngắt kết nối khi Hủy Stream (Resource Leak)
```kotlin
// Dòng 146-148:
override fun onCancel(arguments: Any?) {
    eventSink = null
}
```
- **Vấn đề:** Khi toàn bộ listener phía Flutter hủy lắng nghe (`subscription.cancel()`), `onCancel` chỉ set `eventSink = null` mà **không hề gọi `stopRealtimeNotifications()`**.
- **Hệ quả:** Kết nối mạng tới máy chủ Azure Trouter vẫn tiếp tục duy trì ngầm, tiêu tốn băng thông và pin thiết bị cho đến khi app bị hệ điều hành tắt hẳn.

---

### 3.3 iOS Layer: `ChatNativePlugin.swift` & `chat_native_platform_interface.podspec`

```swift
// File: ios/chat_native_platform_interface/Classes/ChatNativePlugin.swift (119 LOC)
```

#### A. Lệch Hợp đồng Bất đồng bộ giữa iOS và Android (Async Contract Broken) (P0/P1)
```swift
// Dòng 44-49:
do {
    try initializeChatClient(token: token, endpoint: endpoint)
    result(nil) // <-- TRẢ VỀ SUCCESS NGAY LẬP TỨC CHO FLUTTER!
} catch {
    result(FlutterError(code: "NATIVE_INIT_FAILED", message: error.localizedDescription, details: nil))
}
```
Và trong `initializeChatClient`:
```swift
// Dòng 84-93:
client.startRealTimeNotifications { [weak self] result in
    switch result {
    case .success:
        self?.chatClient?.register(event: ChatEventId.chatMessageReceived) { event in
            self?.handleChatEvent(event)
        }
    case .failure(let error):
        NSLog("ChatNative: startRealTimeNotifications failed: %@", error.localizedDescription)
    }
}
```
- **Vấn đề nghiêm trọng:**
  - Trên **Android**: Hàm `initialize` chờ cho đến khi `startRealtimeNotifications()` hoàn tất thì mới gửi `result.success(null)` hoặc `result.error(...)` về cho Flutter.
  - Trên **iOS**: Hàm `initializeChatClient` gọi `client.startRealTimeNotifications` (hàm bất đồng bộ có completion handler), nhưng lại **trả `result(nil)` về cho Flutter ngay tức khắc** trước khi Azure SDK thực sự kết nối!
  - Nếu kết nối thất bại (`case .failure(let error)`), Swift chỉ in ra `NSLog`, còn phía Flutter đã nhận `result(nil)` và tưởng rằng kết nối đã thành công mỹ mãn!
- **Hệ quả:** Flutter không thể bắt được lỗi khởi tạo realtime trên iOS; mọi cơ chế fallback offline hoặc thông báo lỗi cho người dùng đều bị vô hiệu hóa.

#### B. Rủi ro Race Condition khi Đăng ký Event
- Trong completion handler của `startRealTimeNotifications`, code gọi `self?.chatClient?.register(...)`.
- Nếu trước khi completion handler này kích hoạt, người dùng đã chuyển màn hình và gọi `stopRealtimeNotifications()` (set `chatClient = nil`), closure sẽ không đăng ký được event hoặc đăng ký lên một instance không hợp lệ.

#### C. Thiếu Privacy Manifest (iOS 17+ Requirement)
- Từ năm 2024, Apple bắt buộc mọi SDK/Plugin có thu thập dữ liệu hoặc sử dụng các API nhạy cảm (User Defaults, File Timestamps, System Boot Time...) phải đính kèm tệp `PrivacyInfo.xcprivacy`.
- `chat_native_platform_interface` hoàn toàn thiếu file này, có nguy cơ khiến app bị từ chối khi submit lên Apple App Store.

---

## 4. Critical Issues (P0 / P1)

### P0-1 — Dead Code nhưng Ép Host App Phụ thuộc Bộ SDK Azure Nặng nề

```text
Issue: chat_native_platform_interface là dead code nhưng vẫn được khai báo làm dependency bắt buộc trong chat_core
File: packages/chat_core/pubspec.yaml (dòng 18-19), packages/chat_core/lib/features/thread/data/datasources/native_realtime_datasource_impl.dart (dòng 5, 26)
Severity: P0 (Kiến trúc) / P1 (App Size & Build Stability)
Category: Architecture / Dead Dependency / Build Overhead

Current behavior:
1. chat_core phụ thuộc chat_native_platform_interface.
2. NativeRealtimeDataSourceImpl nhận `ChatNativePlatformInterface? platform` nhưng không hề dùng.
3. Toàn bộ realtime chạy qua WebSocket của Backend nội bộ.
4. Tuy nhiên, Gradle và CocoaPods của Host App vẫn phải tải và link toàn bộ Azure SDK (Android: 2.1.0, iOS: 1.3.7).

Problem:
1. Phình to kích thước ứng dụng vô ích (+15MB đến +25MB).
2. Xung đột tài nguyên build (META-INF/NOTICE.md trên Android).
3. Đánh lừa kiến trúc sư và developer về phương thức giao tiếp thực tế của hệ sinh thái Chat.

Why it is dangerous:
Lãng phí tài nguyên của người dùng cuối khi tải app, làm tăng nguy cơ fail build khi nâng cấp Gradle/Flutter mới, và gây khó khăn cho việc bảo trì.

Recommended solution:
Quyết định dứt khoát: LOẠI BỎ (STRIP) chat_native_platform_interface ra khỏi chat_core và chat_ui.
1. Xóa dependency `chat_native_platform_interface` trong chat_core/pubspec.yaml.
2. Xóa import và tham số `platform` trong `NativeRealtimeDataSourceImpl`.
3. Đổi tên `NativeRealtimeDataSourceImpl` thành `WebSocketRealtimeDataSourceImpl` (giữ typedef alias để tương thích ngược nếu cần).
```

---

### P1-1 — Hợp đồng Bất đồng bộ bị Vỡ trên iOS (Silent Async Failure)

```text
Issue: initialize trên iOS trả về result(nil) trước khi startRealTimeNotifications hoàn thành, nuốt trọn mọi exception
File: ios/chat_native_platform_interface/Classes/ChatNativePlugin.swift
Class: ChatNativePlugin
Method: handle (dòng 37-50) & initializeChatClient (dòng 68-94)
Severity: P1
Category: Reliability / Error Handling / Async Flow

Current behavior:
Khi Flutter gọi `initialize()`, Swift thực thi `try initializeChatClient(...)` rồi lập tức gọi `result(nil)`.
Bên trong, `client.startRealTimeNotifications` chạy ngầm. Khi gặp lỗi (sai token, mất mạng, endpoint không hợp lệ), 
nhánh `.failure(let error)` chỉ ghi NSLog và không có kênh nào báo lại cho Flutter.

Problem:
Flutter luôn nhận được kết quả "Thành công", trong khi thực tế kết nối Native đã thất bại hoàn toàn.

Why it is dangerous:
UI không biết kết nối đã hỏng để retry hoặc chuyển sang cơ chế polling/WebSocket fallback, dẫn đến tình trạng im lặng mất tin nhắn (Silent Failure).

Reproduction scenario:
1. Truyền một `acsToken` rác hoặc ngắt kết nối mạng.
2. Gọi `ChatNativePlatformInterface().initialize(...)`.
3. Phía Flutter: `await initialize(...)` hoàn thành trơn tru không ném lỗi.
4. Phía Native: Console Xcode in log lỗi, nhưng app không có phản ứng gì.

Recommended solution:
Lưu `result` của FlutterMethodCall lại và chỉ kích hoạt `result(nil)` hoặc `result(FlutterError(...))` bên trong completion handler của `startRealTimeNotifications`:
```swift
client.startRealTimeNotifications { [weak self] startResult in
    switch startResult {
    case .success:
        self?.chatClient?.register(event: ChatEventId.chatMessageReceived) { event in
            self?.handleChatEvent(event)
        }
        result(nil)
    case .failure(let error):
        result(FlutterError(code: "NATIVE_INIT_FAILED", message: error.localizedDescription, details: nil))
    }
}
```
```

---

### P1-2 — Khởi tạo Thread Không Kiểm soát và Race Condition trên Android

```text
Issue: Sử dụng Thread {}.start() tự do, không đồng bộ hóa khi re-init và không thể hủy bỏ
File: android/src/main/kotlin/com/npp/chatnative/ChatNativePlugin.kt
Class: ChatNativePlugin
Method: initializeChatClientAsync (dòng 77-96)
Severity: P1
Category: Concurrency / Thread Safety / Memory Leak

Current behavior:
Mỗi lần gọi initialize, một Thread mới được tạo ra bằng `Thread { ... }.start()`.

Problem:
1. Không có cơ chế hủy (cancellation) hoặc xếp hàng (queueing).
2. Nếu token refresh liên tục hoặc mạng chập chờn kích hoạt init nhiều lần, các Thread sẽ tranh chấp biến toàn cục `chatClient`.
3. Khi engine detached, Thread vẫn tiếp tục chạy và giữ tham chiếu rác.

Why it is dangerous:
Gây crash không đoán trước được, tạo ra các "Zombie Thread" chạy ngầm tiêu tốn CPU và làm sai lệch trạng thái `chatClient`.

Recommended solution:
Sử dụng một SingleThreadExecutor hoặc Coroutine Scope có tuần tự hóa (Mutex/Channel), đồng thời kiểm tra cờ hủy trước khi gán `chatClient`:
```kotlin
private val initExecutor = Executors.newSingleThreadExecutor()

private fun initializeChatClientAsync(token: String, endpoint: String, result: Result) {
    initExecutor.execute {
        try {
            initializeChatClient(context, token, endpoint)
            Handler(Looper.getMainLooper()).post { result.success(null) }
        } catch (e: Exception) {
            Handler(Looper.getMainLooper()).post { result.error("NATIVE_INIT_FAILED", e.message, null) }
        }
    }
}
```
```

---

### P1-3 — Rò rỉ Socket và Tiêu hao Năng lượng khi Hủy Stream Event

```text
Issue: onCancel của StreamHandler không dừng kết nối Trouter native
File: android/.../ChatNativePlugin.kt (dòng 146-148), ios/.../ChatNativePlugin.swift (dòng 63-66)
Severity: P1
Category: Resource Leak / Battery Drain

Current behavior:
Khi listener phía Flutter hủy lắng nghe stream (`subscription.cancel()`), hàm `onCancel` trên cả Android và iOS chỉ gán `eventSink = null`.

Problem:
Kết nối ngầm của Azure Chat Client (Trouter socket / long-polling) vẫn tiếp tục duy trì hoạt động trên tầng native.

Why it is dangerous:
Thiết bị tiếp tục tiêu tốn pin và dữ liệu di động (3G/4G) cho một kết nối mà không còn bất kỳ thành phần nào trong ứng dụng cần sử dụng.

Recommended solution:
Tự động ngắt realtime notifications khi không còn listener nào, hoặc cung cấp cơ chế đếm tham chiếu (Reference Counting).
```

---

## 5. Crash & Reliability Audit

| Ký hiệu / Đoạn mã | File & Dòng | Mức độ | Kịch bản lỗi & Hậu quả |
|---|---|:---:|---|
| `map['threadId'] as String` | `lib/.../chat_native_platform_interface.dart:30-36` | **Cao** | Nếu server/native trả thiếu bất kỳ field nào trong 6 field bắt buộc, ném `TypeError` và làm crash stream của Flutter. |
| `Thread { ... }.start()` | `android/.../ChatNativePlugin.kt:85` | **Cao** | OutOfMemoryError nếu khởi tạo luồng quá nhiều lần; race condition ghi đè client. |
| `deletedOnIso8601` | `lib/.../chat_native_platform_interface.dart:26` | **Trung bình** | Logic "chết": Dart khai báo để hứng tin xóa, nhưng native không bao giờ gửi key này. |
| `AzureCore 1.0.0-beta.16` | `ios/.../chat_native_platform_interface.podspec:24` | **Trung bình** | Sử dụng pod beta từ nhiều năm trước, nguy cơ xung đột ký hiệu và build fail khi nâng cấp Xcode / CocoaPods. |
| `buildscript` trong plugin | `android/build.gradle:4-14` | **Thấp** | Gradle deprecation warning, có nguy cơ không tương thích với Gradle 9.0+. |

---

## 6. Lifecycle & Resource Matrix

| Sự kiện Vòng đời | Hành vi Kỳ vọng | Hành vi Thực tế trong Plugin Native | Đánh giá & Rủi ro |
|---|---|---|---|
| **Khởi tạo (`initialize`)** | Kết nối tới Azure ACS, thông báo kết quả chính xác về Flutter | Android chờ kết nối; iOS trả về `success` giả tạo trước khi kết nối | ❌ **Lỗi P1-1 trên iOS**: Flutter không bắt được lỗi kết nối. |
| **Lắng nghe (`messageEvents`)** | Mở EventChannel, bắt đầu nhận tin nhắn | Gán `eventSink = events`. Nếu tin đến trước khi listen sẽ bị mất | ⚠️ Thiếu hàng đợi đệm (Event Buffer). |
| **Hủy Lắng nghe (`cancel`)** | Hủy stream và đóng socket nếu không còn ai nghe | Chỉ set `eventSink = null`, giữ nguyên socket Trouter | ❌ **Lỗi P1-3**: Rò rỉ socket và hao pin ngầm. |
| **Token Refresh (Re-init)** | Đóng client cũ tuần tự, tạo client mới an toàn | Android tạo Thread tự do chạy đua; iOS huỷ client cũ không đồng bộ | ⚠️ Nguy cơ Race condition giữa 2 client. |
| **App vào Background** | Gọi `stopRealtimeNotifications` để giải phóng socket | Phụ thuộc hoàn toàn vào việc Flutter chủ động gọi hàm `stop` | Tốt nếu Flutter gọi; nguy hiểm nếu Flutter quên gọi. |
| **Engine Detached** | Dọn dẹp sạch sẽ toàn bộ channel, client và context | Gán null các biến; nhưng background thread có thể vẫn đang chạy | ⚠️ Nguy cơ truy cập context đã bị hủy. |

---

## 7. Public API Review

### 7.1 Đánh giá Thiết kế Public API (`lib/chat_native_platform_interface.dart`)

```dart
// Hiện trạng Public API:
abstract class / class ChatNativePlatformInterface {
  Future<void> initialize({
    required String acsToken,
    required String acsUserId, // <-- THAM SỐ THỪA (Native không dùng)
    required String endpoint,
  });

  Stream<NativeChatMessageEvent> get messageEvents;

  Future<void> stopRealtimeNotifications();
}
```

#### Những thiếu sót lớn của Public API:
1. **Thiếu kênh trạng thái kết nối (`connectionStateStream`):** Consumer không có cách nào biết được trạng thái kết nối native hiện tại là `connecting`, `connected`, `disconnected`, hay `tokenExpired`.
2. **Thiếu kênh báo lỗi (`errorStream`):** Mọi lỗi rớt mạng ngầm của Azure Trouter bị chôn vùi trong native log.
3. **Thiếu các loại sự kiện cần thiết:** Không hỗ trợ sự kiện xóa tin nhắn (`deletedMessageEvents`), sửa tin nhắn (`editedMessageEvents`), trạng thái đang gõ (`typingEvents`), và đã đọc (`readReceiptEvents`).
4. **Không tuân thủ mẫu chuẩn Flutter Platform Interface:**
   - Chuẩn Flutter khuyến nghị sử dụng package `plugin_platform_interface` với mẫu:
     ```dart
     abstract class ChatNativePlatformInterface extends PlatformInterface {
       static ChatNativePlatformInterface get instance => _instance;
       static set instance(ChatNativePlatformInterface instance) { ... }
     }
     ```
   - Việc viết một concrete class thông thường khiến việc viết Unit Test bằng mock ở các tầng trên (`chat_core`, `chat_ui`) trở nên phức tạp hơn.

---

## 8. Testability & Test Coverage

- **Hiện trạng Test:** **0 dòng test / 0% độ phủ**.
- **Các kịch bản hoàn toàn chưa được kiểm thử tự động:**
  1. ❌ Kiểm tra `NativeChatMessageEvent.fromMap` với dữ liệu chuẩn, dữ liệu thiếu trường, dữ liệu chứa null.
  2. ❌ Kiểm tra `ChatNativePlatformInterface.initialize` gọi đúng Method Name và Map Arguments qua mock BinaryMessenger.
  3. ❌ Kiểm tra `ChatNativePlatformInterface.messageEvents` chuyển đổi đúng payload từ EventChannel.
  4. ❌ Kiểm tra xử lý lỗi khi MethodChannel ném `PlatformException`.
  5. ❌ Unit test native trên Android (JUnit/Robolectric) và iOS (XCTest).

---

## 9. Hai Phương án Kiến trúc Chiến lược (Strategic Options)

Dự án đang đứng trước 2 ngã rẽ rõ ràng. Cần đưa ra quyết định kiến trúc dứt khoát:

```text
                               ┌────────────────────────────────────────┐
                               │   QUYẾT ĐỊNH KIẾN TRÚC CHO NATIVE SDK  │
                               └──────────────────┬─────────────────────┘
                                                  │
                 ┌────────────────────────────────┴────────────────────────────────┐
                 ▼                                                                 ▼
   【PHƯƠNG ÁN 1 (KHUYẾN NGHỊ)】                                     【PHƯƠNG ÁN 2 (DUY TRÌ ACS)】
   LOẠI BỎ TOÀN BỘ ACS NATIVE                                       CHUẨN HÓA THÀNH FEDERATED PLUGIN
   ───────────────────────────                                       ────────────────────────────────
   • Xóa bỏ package chat_native_platform_interface.                  • Tái cấu trúc theo chuẩn Federated Plugin.
   • Giảm ngay 15-25 MB kích thước app.                              • Tách thành 4 sub-packages.
   • Loại bỏ xung đột build Gradle/CocoaPods.                        • Sửa toàn bộ lỗi bất đồng bộ và race condition.
   • Đúng với thực tế vận hành WebSocket.                            • Hỗ trợ đầy đủ các loại sự kiện ACS.
```

### Phương án 1 (Khuyến nghị mạnh mẽ): Loại bỏ hoàn toàn `chat_native_platform_interface`
- **Lý do:** Toàn bộ hệ thống Chat đã chuyển đổi sang WebSocket của Backend nội bộ (`NativeRealtimeDataSourceImpl` kết nối `/ws/chat/view`). Backend đóng vai trò làm gateway điều phối và bảo mật token, không cho client kết nối trực tiếp lên Azure ACS. Do đó, việc duy trì plugin native này là hoàn toàn dư thừa.
- **Hành động cụ thể:**
  1. Xóa `packages/chat_native_platform_interface`.
  2. Xóa dependency `chat_native_platform_interface` trong `packages/chat_core/pubspec.yaml` và `packages/chat_ui/pubspec_overrides.yaml`.
  3. Trong `packages/chat_core`: Xóa import và tham số `ChatNativePlatformInterface? platform` trong constructor của `NativeRealtimeDataSourceImpl`.
  4. Đổi tên `NativeRealtimeDataSourceImpl` $\to$ `WebSocketRealtimeDataSourceImpl` (tạo `typedef NativeRealtimeDataSourceImpl = WebSocketRealtimeDataSourceImpl` để đảm bảo tương thích ngược).
  5. Xóa `acsEndpoint` bắt buộc trong `ChatModuleConfig`.

### Phương án 2: Nếu bắt buộc giữ để hỗ trợ chế độ kết nối trực tiếp ACS (Dual-mode)
Nếu trong tương lai dự án muốn cung cấp cả 2 chế độ: (A) Chạy qua WebSocket Backend và (B) Chạy trực tiếp qua Azure ACS SDK, thì package này phải được đập đi xây lại theo chuẩn **Federated Plugin**:
1. Cài đặt `plugin_platform_interface` cho package này.
2. Tách thành cấu trúc:
   - `chat_native_platform_interface` (Chỉ chứa abstract interface + tokens).
   - `chat_native_android` (Triển khai Android Kotlin chuyên biệt).
   - `chat_native_ios` (Triển khai iOS Swift chuyên biệt).
3. Sửa lỗi bất đồng bộ trên iOS (`startRealTimeNotifications` completion handler).
4. Sử dụng Coroutine / SingleThreadExecutor trên Android thay cho `Thread {}.start()`.
5. Bổ sung các event còn thiếu (`deletedOn`, `typingIndicator`, `connectionState`).

---

## 10. Refactoring Priority Matrix

| Mức độ | Vấn đề | File liên quan | Tác động | Độ phức tạp | Đề xuất giải pháp |
|:---:|---|---|:---:|:---:|---|
| **P0** | Dead code nhưng ép host app kéo theo 20MB Azure SDK | `chat_core/pubspec.yaml`, `native_realtime_datasource_impl.dart` | Rất lớn (Size & Kiến trúc) | Thấp | **Xóa bỏ hoàn toàn package** hoặc gỡ bỏ liên kết khỏi `chat_core`. |
| **P1** | Lệch bất đồng bộ và nuốt lỗi kết nối trên iOS | `ios/.../ChatNativePlugin.swift` | Lớn (Crash/Silent Fail) | Thấp | Trả `result` bên trong completion handler của `startRealTimeNotifications`. |
| **P1** | Khởi tạo Thread tự do gây Race Condition trên Android | `android/.../ChatNativePlugin.kt` | Lớn (Stability) | Thấp | Thay `Thread {}` bằng `Executors.newSingleThreadExecutor()`. |
| **P1** | Rò rỉ Socket và hao pin khi Stream bị Cancel | `ChatNativePlugin.kt`, `ChatNativePlugin.swift` | Trung bình (Pin/Mạng) | Thấp | Gọi `stopRealtimeNotifications()` khi không còn listener. |
| **P2** | Ép kiểu không an toàn trong `fromMap` | `lib/.../chat_native_platform_interface.dart` | Trung bình | Rất thấp | Dùng toán tử `as String? ?? ''` phòng thủ. |
| **P2** | Trực tiếp apply `kotlin-android` và `buildscript` cũ | `android/build.gradle` | Thấp (Build Tool) | Thấp | Migrate sang chuẩn Gradle mới của Flutter. |
| **P2** | Thiếu file `PrivacyInfo.xcprivacy` trên iOS | `ios/` | Trung bình (App Store) | Rất thấp | Bổ sung file cấu hình Privacy Manifest. |

---

## 11. Actionable Migration Plan

### Kế hoạch Triển khai theo Phương án 1 (Gỡ bỏ Dead Code - Khuyến nghị):

#### Bước 1: Dọn dẹp Core & Phụ thuộc
- Mở `packages/chat_core/pubspec.yaml`, xóa bỏ dòng:
  ```yaml
  chat_native_platform_interface:
    path: ../chat_native_platform_interface
  ```
- Mở `packages/chat_core/lib/features/thread/data/datasources/native_realtime_datasource_impl.dart`:
  - Xóa dòng import `package:chat_native_platform_interface/...`.
  - Xóa tham số `ChatNativePlatformInterface? platform` khỏi constructor.

#### Bước 2: Dọn dẹp Cấu hình và Tên gọi gây hiểu nhầm
- Trong `packages/chat_core/lib/core/config/chat_module_config.dart`:
  - Đánh dấu `@deprecated` cho trường `acsEndpoint` hoặc chuyển thành optional `String? acsEndpoint = null`.
- Cập nhật tài liệu `MIGRATION_GUIDE_V2.md` và `README.md` để giải thích rõ hệ thống đang chạy qua WebSocket Backend, không cần cấu hình `ACS_ENDPOINT`.

#### Bước 3: Đóng gói và Lưu trữ (Archive)
- Xóa thư mục `packages/chat_native_platform_interface` khỏi workspace chính (hoặc chuyển vào nhánh lưu trữ `archive/native-acs-plugin`).

---

## 12. Production Readiness Verdict

```text
❌ NOT READY / KHUYẾN NGHỊ LOẠI BỎ (STRIP ACS LEGACY)
```

> **Kết luận của Senior Architect:**  
> `chat_native_platform_interface` là một **mảnh ghép di sản (legacy artifact)** của giai đoạn thiết kế ban đầu khi dự án dự kiến giao tiếp trực tiếp với Azure SDK. Hiện tại, kiến trúc toàn hệ thống đã chuyển dịch hoàn toàn sang **WebSocket Backend**. Việc tiếp tục duy trì package này chỉ mang lại tác hại (tăng kích thước app 15–25 MB, xung đột build Gradle, mã nguồn chứa lỗi bất đồng bộ và race condition) mà không mang lại bất kỳ giá trị vận hành thực tế nào.  
> 
> **Hành động ưu tiên số 1:** Gỡ bỏ package này khỏi cây phụ thuộc của `chat_core` và `chat_ui`.
