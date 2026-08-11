import 'dart:async';

import 'package:chat_native_platform_interface/chat_native_platform_interface.dart';

import '../../../../core/config/chat_module_config.dart';

import '../../../auth_token/domain/repositories/auth_token_repository.dart';
import '../../domain/entities/message.dart';
import '../models/message_model.dart';
import 'native_realtime_datasource.dart';

/// Implement qua EventChannel (Giai đoạn 2). Chỉ mở 1 kết nối native duy
/// nhất, fan-out theo threadId cho từng controller Dart.
class NativeRealtimeDataSourceImpl implements NativeRealtimeDataSource {
  NativeRealtimeDataSourceImpl({
    required ChatModuleConfig config,
    required AuthTokenRepository authTokenRepository,
    ChatNativePlatformInterface? platform,
  })  : _config = config,
        _authTokenRepository = authTokenRepository,
        _platform = platform ?? ChatNativePlatformInterface();

  final ChatModuleConfig _config;
  final AuthTokenRepository _authTokenRepository;
  final ChatNativePlatformInterface _platform;

  bool _initialized = false;
  final Map<String, StreamController<MessageModel>> _threadControllers = {};
  StreamController<MessageModel>? _listController;
  StreamSubscription<NativeChatMessageEvent>? _nativeSub;

  Future<void> _ensureInitialized(String roomId) async {
    if (_initialized) return;
    try {
      final token = await _authTokenRepository.getAccessToken(roomId);
      await _platform.initialize(
        acsToken: token.token,
        acsUserId: token.acsUserId,
        endpoint: _config.acsEndpoint,
      );
      _initialized = true;
      _nativeSub = _platform.messageEvents.listen(_forwardEvent);
    } catch (_) {
      // Init lỗi (native chưa đăng ký / mất mạng / token hết hạn) — không
      // crash. Stream chỉ không emit gì, lần gọi sau sẽ thử lại.
    }
  }

  void _forwardEvent(NativeChatMessageEvent event) {
    final model = MessageModel(
      id: event.messageId,
      threadId: event.threadId,
      senderId: event.senderId,
      senderDisplayName: event.senderDisplayName,
      content: event.content,
      type: MessageType.text,
      createdAt: DateTime.parse(event.createdAtIso8601).toLocal(),
      deletedOn: event.deletedOnIso8601 != null
          ? DateTime.parse(event.deletedOnIso8601!).toLocal()
          : null,
    );

    final threadController = _threadControllers[event.threadId];
    if (threadController != null && !threadController.isClosed) {
      threadController.add(model);
    }

    final listController = _listController;
    if (listController != null && !listController.isClosed) {
      listController.add(model);
    }
  }

  @override
  Stream<MessageModel> watchNewMessages(String roomId, String threadId) {
    final existing = _threadControllers[threadId];
    if (existing != null) return existing.stream;

    final controller = StreamController<MessageModel>.broadcast();
    _threadControllers[threadId] = controller;
    // Fire-and-forget init — nếu init lỗi, stream đơn giản không emit gì,
    // UI vẫn hoạt động bình thường với lịch sử đã load qua REST.
    unawaited(_ensureInitialized(roomId));
    return controller.stream;
  }

  @override
  Stream<MessageModel> watchListMessages(String roomId) {
    final existing = _listController;
    if (existing != null) return existing.stream;

    final controller = StreamController<MessageModel>.broadcast();
    _listController = controller;
    unawaited(_ensureInitialized(roomId));
    return controller.stream;
  }

  @override
  Future<void> stopWatching(String threadId) async {
    final controller = _threadControllers.remove(threadId);
    await controller?.close();
    await _maybeStopNative();
  }

  @override
  Future<void> stopWatchingList() async {
    final controller = _listController;
    _listController = null;
    await controller?.close();
    await _maybeStopNative();
  }

  /// Chỉ đóng kết nối native khi KHÔNG còn bất kỳ ai đang theo dõi
  /// (thread đang mở hoặc list hội thoại) — realtime list không được
  /// bị dừng nhầm khi đóng 1 thread.
  Future<void> _maybeStopNative() async {
    if (_threadControllers.isNotEmpty || _listController != null) return;
    if (_initialized) {
      await _platform.stopRealtimeNotifications();
      await _nativeSub?.cancel();
      _nativeSub = null;
      _initialized = false;
    }
  }

  @override
  Future<void> dispose() async {
    for (final c in _threadControllers.values) {
      await c.close();
    }
    _threadControllers.clear();
    await _listController?.close();
    _listController = null;
    await _nativeSub?.cancel();
    _nativeSub = null;
  }
}
