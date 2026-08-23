# Chat Module — Flutter (Clean Architecture + WebSocket Realtime)

Monorepo gồm 2 packages chính:
- `chat_core`: Domain + Data layers (Entities, Repositories, Use Cases, REST API Client, WebSocket Realtime DataSource thuần Dart). Độc lập với UI framework.
- `chat_ui`: Presentation layer (Widgets, Screens, Riverpod Providers, Notifiers, Hive Local Storage Cache).

## Bootstrap

```bash
# Cài melos (1 lần)
dart pub global activate melos

# Từ thư mục chat-module-mvp
melos bootstrap
```

`melos bootstrap` tự link `chat_core` ⇄ `chat_ui` bằng `path:` và chạy `pub get` cho toàn bộ workspace.

## Lệnh hay dùng

| Lệnh | Việc |
|---|---|
| `melos list --long` | Liệt kê danh sách và phiên bản của các package |
| `melos run analyze` | Lint toàn bộ package |
| `melos run test` | Test toàn bộ package có thư mục `test/` |
| `melos run format` | Kiểm tra format mã nguồn |

## Việc CẦN LÀM TRƯỚC KHI CHẠY THẬT (chưa verify được trong sandbox dev)

- [ ] Verify `api-version` của ACS Chat REST API dùng trong
      `chat_core/lib/data/rest/acs_rest_chat_repository.dart` (đang để
      tạm `2024-03-07`, có TODO đánh dấu trong code).
- [ ] Verify field JSON thật trả về từ ACS `listMessages`/`sendMessage`
      khớp với `Message.fromAcsJson` (đang để TODO trong
## Cấu trúc và Hướng dẫn phát triển

Xem chi tiết tại:
- `Project-guildline_and_structure_chat.md`: Đặc tả Clean Architecture và cấu trúc thư mục.
- `CLEAN_CODE_RULES.md`: Quy chuẩn đặt tên, Clean Code và Best Practices.
