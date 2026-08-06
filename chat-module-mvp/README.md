# Chat Module — Flutter (ACS + BE nội bộ)

Monorepo 3 package: `chat_core` (domain + data + provider, Dart), `chat_ui`
(widget mặc định), `chat_native_platform_interface` (native realtime —
**hiện chỉ Android**, xem `packages/chat_native_platform_interface/README.md`).

> **Trạng thái MVP**: chat 1-1 (direct), realtime qua native Android,
> chưa có group/roles/participant-management/file-upload/typing-nhận/
> read-receipt-nhận. Xem `roadmap-tinh-nang-sau-mvp.md` cho phần còn lại.

## Bootstrap

```bash
# Cài melos (1 lần)
dart pub global activate melos

# Từ thư mục gốc repo
melos bootstrap
```

`melos bootstrap` tự link `chat_core` ⇄ `chat_ui` ⇄
`chat_native_platform_interface` bằng `path:`, chạy `pub get` toàn workspace.

## Sinh Android project cho `example/`

Repo này chỉ chứa code plugin (`android/` trong
`chat_native_platform_interface`), KHÔNG chứa boilerplate Android app —
cần sinh bằng chính Flutter tooling trước khi build thử:

```bash
cd example
flutter create --platforms=android .
```

Sau đó thêm dependency ACS Android SDK vào `example/android/app/build.gradle`
nếu chưa tự động resolve qua plugin.

## Lệnh hay dùng

| Lệnh | Việc |
|---|---|
| `melos run analyze` | Lint toàn bộ package |
| `melos run test` | Test toàn bộ package có thư mục `test/` |
| `melos run format` | Kiểm tra format |

## Việc CẦN LÀM TRƯỚC KHI CHẠY THẬT (chưa verify được trong sandbox dev)

- [ ] Verify `api-version` của ACS Chat REST API dùng trong
      `chat_core/lib/data/rest/acs_rest_chat_repository.dart` (đang để
      tạm `2024-03-07`, có TODO đánh dấu trong code).
- [ ] Verify field JSON thật trả về từ ACS `listMessages`/`sendMessage`
      khớp với `Message.fromAcsJson` (đang để TODO trong
      `chat_core/lib/domain/entities/message.dart`).
- [ ] Verify tên class/method SDK Azure Communication Chat Android
      (`ChatClient.Builder()`, `startRealtimeNotifications()`,
      `addEventHandler(...)`) khớp đúng version dùng thật — có TODO
      trong `ChatNativePlugin.kt`.
- [ ] Verify body request thật của các endpoint BE chưa thấy đầy đủ lúc
      viết code (vd `POST /conversations/direct` — mình giả định field
      `targetUserId`, cần đối chiếu lại với BE team).
- [ ] Điền `com.yourorg.chatnative` bằng package name thật của tổ chức
      (đang để placeholder xuyên suốt `chat_native_platform_interface`).

## Cấu trúc

Xem `ke-hoach-chat-module-flutter.md` mục 3 và
`huong-dan-monorepo-dependency.md` mục 1.
