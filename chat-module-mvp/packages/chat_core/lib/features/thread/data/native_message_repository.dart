import 'dart:async';

import 'package:chat_native_platform_interface/chat_native_platform_interface.dart';

import '../../auth_token/domain/auth_token_repository.dart';
import '../../conversation_list/domain/conversation.dart';
import '../domain/message.dart';
import '../domain/message_repository.dart';
import 'rest_message_repository.dart';

/// Đúng quyết định kiến trúc #6 (repository pattern) + mục 4 Giai đoạn 2
/// kế hoạch gốc: CHỈ override [watchNewMessages]/[stopWatching] qua
/// native, mọi method khác delegate y nguyên sang [RestMessageRepository]
/// — không viết lại send/list/participant/token.
class NativeMessageRepository implements MessageRepository {
  NativeMessageRepository({
    required RestMessageRepository restRepository,
    required AuthTokenRepository authTokenRepository,
    ChatNativePlatformInterface? platform,
  })  : _rest = restRepository,
        _authTokenRepository = authTokenRepository,
        _platform = platform ?? ChatNativePlatformInterface();

  final RestMessageRepository _rest;
  final AuthTokenRepository _authTokenRepository;
  final ChatNativePlatformInterface _platform;

  bool _initialized = false;
  final Map<String, StreamController<Message>> _threadControllers = {};
  StreamSubscription<NativeChatMessageEvent>? _nativeSub;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    final token = await _authTokenRepository.getAccessToken();
    await _platform.initialize(
      acsToken: token.token,
      acsUserId: token.user.acsUserId ?? token.user.id,
      endpoint: token.endpoint,
    );
    _initialized = true;

    // 1 subscription duy nhất native → fan-out theo threadId cho từng
    // stream controller Dart (đúng "native chỉ mở 1 kết nối duy nhất").
    _nativeSub = _platform.messageEvents.listen((event) {
      final controller = _threadControllers[event.threadId];
      if (controller == null || controller.isClosed) return;
      controller.add(Message(
        id: event.messageId,
        threadId: event.threadId,
        senderId: event.senderId,
        senderDisplayName: event.senderDisplayName,
        content: event.content,
        type: MessageType.text,
        createdAt: DateTime.parse(event.createdAtIso8601),
      ));
    });
  }

  @override
  Stream<Message> watchNewMessages(String threadId) {
    final existing = _threadControllers[threadId];
    if (existing != null) return existing.stream;

    final controller = StreamController<Message>.broadcast();
    _threadControllers[threadId] = controller;
    // Fire-and-forget init — nếu init lỗi, stream đơn giản không emit gì,
    // UI vẫn hoạt động bình thường với lịch sử đã load qua REST.
    unawaited(_ensureInitialized());
    return controller.stream;
  }

  @override
  Future<void> stopWatching(String threadId) async {
    final controller = _threadControllers.remove(threadId);
    await controller?.close();

    // Không còn thread nào theo dõi → đóng hẳn kết nối native, đúng
    // mục 6 kế hoạch gốc ("đóng kết nối khi background").
    if (_threadControllers.isEmpty && _initialized) {
      await _platform.stopRealtimeNotifications();
      await _nativeSub?.cancel();
      _initialized = false;
    }
  }

  @override
  Future<Message> sendMessage({required String threadId, required String content}) =>
      _rest.sendMessage(threadId: threadId, content: content);

  @override
  Future<PaginatedResult<Message>> listMessages({
    required String threadId,
    String? startTime,
    String? cursor,
  }) =>
      _rest.listMessages(threadId: threadId, startTime: startTime, cursor: cursor);

  Future<void> dispose() async {
    for (final c in _threadControllers.values) {
      await c.close();
    }
    _threadControllers.clear();
    await _nativeSub?.cancel();
    await _rest.dispose();
  }
}
