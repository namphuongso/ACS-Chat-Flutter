# Project Guidelines and Structure - Chat Module

Tài liệu này đặc tả cấu trúc thư mục, kiến trúc phân tầng (Clean Architecture), quy chuẩn đặt mã nguồn và quản lý state bằng Riverpod cho riêng Chat Module.

---

## 1. Kiến Trúc Tổng Quan (Clean Architecture + Feature-Based)

Chat Module được thiết kế chia làm 2 packages chính để tách biệt hoàn toàn giữa Logic nghiệp vụ và Giao diện UI:
1. **`chat_core`**: Chứa lớp **Domain** (Nghiệp vụ, Entities, Repositories, UseCases) và lớp **Data** (Repository implementations, Local/Remote Datasources, Models). Package này độc lập hoàn toàn với framework UI và Riverpod.
2. **`chat_ui`**: Chứa lớp **Presentation** (Widgets, Screens, Riverpod Providers, Notifiers). Package này phụ thuộc vào `chat_core` và `flutter_riverpod`.

Mỗi package được tổ chức theo từng tính năng (**Feature-Based**) để dễ dàng cô lập và phát triển độc lập.

---

## 2. Cấu Trúc Thư Mục Chi Tiết

### 2.1 Cấu trúc `chat_core` (Lớp Domain & Data)

```txt
packages/chat_core/lib/
├── chat_core.dart                        # Barrel file export tất cả domain entities, repositories, usecases & data models
└── features/
    ├── auth_token/                       # Tính năng quản lý xác thực & ACS token
    │   ├── domain/
    │   │   ├── entities/                 # Domain entities thô (vd: ChatAccessToken)
    │   │   ├── repositories/             # Repository interfaces (vd: AuthTokenRepository)
    │   │   └── usecases/                 # Use cases nghiệp vụ (vd: GetAccessTokenUseCase)
    │   └── data/
    │       ├── datasources/              # Data sources lấy dữ liệu thô (vd: AuthTokenRemoteDatasource)
    │       ├── models/                   # Data models chứa logic parse JSON (vd: ChatAccessTokenModel)
    │       └── repositories/             # Implementation của Repository (vd: AuthTokenRepositoryImpl)
    │
    ├── conversation_list/                # Tính năng danh sách hội thoại
    │   ├── domain/
    │   │   ├── entities/                 # Conversation, PaginatedResult
    │   │   ├── repositories/             # ConversationRepository interface
    │   │   └── usecases/                 # ListConversationsUseCase, GetOrCreateDirectConversationUseCase, GetConversationUseCase
    │   └── data/
    │       ├── datasources/              # ConversationRemoteDatasource, ConversationRemoteDatasourceImpl
    │       ├── models/                   # ConversationModel
    │       └── repositories/             # ConversationRepositoryImpl
    │
    ├── thread/                           # Tính năng chat room / nhắn tin
    │   ├── domain/
    │   │   ├── entities/                 # Message, MessageType
    │   │   ├── repositories/             # MessageRepository interface
    │   │   └── usecases/                 # SendMessageUseCase, ListMessagesUseCase, WatchNewMessagesUseCase, StopWatchingMessagesUseCase
    │   └── data/
    │       ├── datasources/              # MessageRemoteDatasource, NativeRealtimeDatasource, PollingEngine
    │       ├── models/                   # MessageModel
    │       └── repositories/             # MessageRepositoryImpl (kết hợp REST & Native)
    │
    ├── read_status/                      # Tính năng trạng thái đã đọc
    │   ├── domain/
    │   │   ├── repositories/             # ReadStatusRepository
    │   │   └── usecases/                 # MarkAsReadUseCase
    │   └── data/
    │       ├── datasources/              # ReadStatusRemoteDatasource, ReadStatusRemoteDatasourceImpl
    │       └── repositories/             # ReadStatusRepositoryImpl
    │
    └── shared/                           # Logic & entities dùng chung toàn bộ core
        ├── domain/
        │   └── entities/                 # ChatUser, ChatModuleConfig, ChatApiException
        └── data/
            ├── json_api_client.dart      # REST API Client dùng chung để bọc http requests
            └── models/                   # ChatUserModel
```

### 2.2 Cấu trúc `chat_ui` (Lớp Presentation)

```txt
packages/chat_ui/lib/
├── chat_ui.dart                          # Barrel file export UI widgets/screens & Riverpod providers cho host app
└── features/
    ├── conversation_list/
    │   └── presentation/
    │       ├── screens/                  # Màn hình chính (vd: ConversationList)
    │       ├── providers/                # Riverpod providers (vd: conversationListProvider)
    │       └── notifiers/                # StateNotifier / Notifiers (vd: ConversationListNotifier)
    │
    ├── thread/
    │   └── presentation/
    │       ├── screens/                  # ThreadScreen
    │       ├── widgets/                  # Sub-widgets (vd: MessageBubble, MessageInput)
    │       ├── providers/                # threadMessagesProvider, messageRepositoryProvider
    │       └── notifiers/                # ThreadMessagesNotifier
    │
    └── shared/
        └── presentation/
            └── providers/                # Shared providers (vd: chatModuleConfigProvider, chatAuthTokenProviderProvider)
```

---

## 3. Quy Tắc Phân Tầng và Phát Triển

### 3.1 Domain Layer (Nghiệp Vụ Cốt Lõi)
- **Entities**: Lớp chứa dữ liệu nghiệp vụ thuần túy, **bắt buộc** không chứa bất kỳ logic serialization nào (như `fromJson`, `toJson`).
- **Repositories**: Các interface định nghĩa các hành động nghiệp vụ dưới dạng lớp trừu tượng (`abstract class`).
- **Use Cases**: Đại diện cho một ca sử dụng nghiệp vụ duy nhất. Lớp Presentation (Notifiers) sẽ tương tác trực tiếp với các Use Cases này để thực thi logic thay vì gọi thẳng Repository.

### 3.2 Data Layer (Dữ Liệu Thô & Hạ Tầng)
- **Models**: Kế thừa các Entities tương ứng từ Domain layer, bổ sung các phương thức serialize/deserialize (`fromJson`, `toJson`).
- **Datasources**: Tương tác trực tiếp với API Client (`JsonApiClient` bọc http) hoặc Native EventChannel.
- **Repository Implementations**: Implement các repository interface từ Domain layer. Có hậu tố `*RepositoryImpl` (ví dụ: `MessageRepositoryImpl`). Đây là nơi điều phối các nguồn dữ liệu từ local/remote datasources.

### 3.3 Presentation Layer (Giao Diện & Trạng Thái)
- **Providers & Notifiers**: Chỉ đặt tại `chat_ui`. Quản lý state của widget/screen bằng Riverpod.
- **Screens & Widgets**: Nhận state từ Provider và điều khiển hành vi qua Notifier.
