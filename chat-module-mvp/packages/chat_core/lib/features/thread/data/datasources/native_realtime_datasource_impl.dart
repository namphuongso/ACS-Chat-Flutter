import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chat_native_platform_interface/chat_native_platform_interface.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/config/chat_module_config.dart';
import '../../../../core/utils/chat_logger.dart';
import '../../../auth_token/domain/repositories/auth_token_repository.dart';
import '../../../auth_token/domain/repositories/chat_auth_token_provider.dart';
import '../../domain/entities/message.dart';
import '../models/message_model.dart';
import 'native_realtime_datasource.dart';

/// Realtime app-wide qua backend WebSocket.
///
/// Tên class/interface cũ được giữ lại để không làm breaking các app đang
/// tích hợp. [platform] và [authTokenRepository] cũng còn trong constructor
/// cho tương thích source, nhưng realtime không còn phụ thuộc ACS native.
class NativeRealtimeDataSourceImpl implements NativeRealtimeDataSource {
  NativeRealtimeDataSourceImpl({
    required ChatModuleConfig config,
    ChatAuthTokenProvider? appTokenProvider,
    AuthTokenRepository? authTokenRepository,
    ChatNativePlatformInterface? platform,
  })  : _config = config,
        _appTokenProvider = appTokenProvider,
        _deviceId = config.deviceId ?? _createProcessDeviceId();

  final ChatModuleConfig _config;
  final ChatAuthTokenProvider? _appTokenProvider;
  final String _deviceId;

  final Map<String, StreamController<MessageModel>> _threadControllers = {};
  final Map<String, String> _threadIdsByRoom = {};
  StreamController<MessageModel>? _listController;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _connecting = false;
  bool _disposed = false;
  bool _manualClose = false;
  bool _serverConnected = false;
  bool _sessionExpired = false;
  int _reconnectAttempt = 0;
  String? _activeRoomId;

  static const _authCloseCodes = {1008, 4003, 4401, 4403};
  static String _createProcessDeviceId() {
    final random = Random.secure();
    return 'chat-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
        '${random.nextInt(1 << 32).toRadixString(16)}';
  }

  Uri _socketUri(String token) {
    final configured = _config.webSocketUrl?.trim();
    final Uri base;
    if (configured != null && configured.isNotEmpty) {
      base = Uri.parse(configured);
    } else {
      final backend = Uri.parse(_config.backendBaseUrl);
      base = backend.replace(
        scheme: backend.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws/chat/view',
        query: null,
        fragment: null,
      );
    }
    return base.replace(queryParameters: {
      ...base.queryParameters,
      _config.webSocketTokenQueryParameter: token,
      'deviceId': _deviceId,
    });
  }

  Future<void> _ensureConnected() async {
    if (_disposed || _sessionExpired || _connecting || _channel != null) {
      return;
    }
    _connecting = true;
    _manualClose = false;
    try {
      final provider = _appTokenProvider;
      if (provider == null) {
        ChatLogger.log(
            'WebSocket disabled: ChatAuthTokenProvider was not provided');
        return;
      }
      final token = await provider.getAppToken();
      final channel = WebSocketChannel.connect(_socketUri(token));
      await channel.ready.timeout(const Duration(seconds: 15));
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _reconnectAttempt = 0;
      _socketSubscription = channel.stream.listen(
        _handleSocketData,
        onError: (Object error, StackTrace stackTrace) {
          ChatLogger.log('WebSocket error: $error');
          unawaited(_handleDisconnected());
        },
        onDone: () {
          final closeCode = channel.closeCode;
          final closeReason = channel.closeReason;
          ChatLogger.log(
              'WebSocket closed: code=$closeCode reason=$closeReason');
          unawaited(_handleDisconnected(
            closeCode: closeCode,
            closeReason: closeReason,
          ));
        },
        cancelOnError: true,
      );
    } on TimeoutException catch (error) {
      ChatLogger.log('WebSocket connect timeout: $error');
      _scheduleReconnect();
    } catch (error) {
      ChatLogger.log('WebSocket connect failed: $error');
      if (_looksLikeAuthError(error.toString())) {
        _expireSession();
      } else {
        _scheduleReconnect();
      }
    } finally {
      _connecting = false;
    }
  }

  void _handleSocketData(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final event = decoded.cast<String, dynamic>();
      final prettyJson = const JsonEncoder.withIndent('  ').convert(event);
      ChatLogger.log('WebSocket event:\n$prettyJson');
      final type = event['type']?.toString();

      if (type == 'connected') {
        _serverConnected = true;
        final interval = _intValue(event['heartbeatIntervalSeconds']) ?? 30;
        _startHeartbeat(Duration(seconds: max(5, interval)));
        final roomId = _activeRoomId;
        if (roomId != null) _send({'type': 'enter_room', 'roomId': roomId});
        return;
      }
      if (type == 'error') {
        final code = event['errorCode']?.toString() ?? event['code']?.toString();
        final message = event['message']?.toString() ?? '';
        if (_looksLikeAuthError('$code $message')) _expireSession();
        return;
      }
      if (type != 'room_event') return;
      _handleRoomEvent(event);
    } catch (error) {
      ChatLogger.log('Ignored malformed WebSocket event: $error raw=$raw');
    }
  }

  void _handleRoomEvent(Map<String, dynamic> event) {
    final eventType = event['eventType']?.toString();
    final payload = event['payload'];
    if (payload is! Map) return;
    final data = payload.cast<String, dynamic>();
    final roomId = event['roomId']?.toString() ?? data['roomId']?.toString();
    // Event backend hiện chỉ trả roomId, không trả ACS threadId. Khi room
    // chưa từng được mở trong session thì dùng roomId làm routing key để màn
    // danh sách vẫn xác định và cập nhật đúng conversation.
    final threadId = data['threadId']?.toString() ??
        (roomId == null ? null : _threadIdsByRoom[roomId] ?? roomId);

    if (eventType == 'MessageReacted' ||
        eventType == 'MessageUnreacted' ||
        eventType == 'MessageReactionUpdated' ||
        (eventType != null && eventType.toLowerCase().contains('react'))) {
      final msgId = (data['messageId'] ?? data['MessageId'] ?? '').toString();
      if (threadId == null) return;
      final signal = MessageModel(
        id: msgId,
        threadId: threadId,
        senderId: (data['actorId'] ?? '').toString(),
        senderDisplayName: (data['actorName'] ?? '').toString(),
        content: data['reactionCode']?.toString() ?? '',
        type: MessageType.reactionUpdate,
        createdAt: DateTime.now(),
      );
      _emit(signal, roomId: roomId);
      return;
    }

    if (eventType == 'NewMessage' || eventType == 'MessageUpdated') {
      final rawMessage = data['message'] is Map
          ? (data['message'] as Map).cast<String, dynamic>()
          : data;
      final messageId = rawMessage['MessageId'] ??
          rawMessage['messageId'] ??
          rawMessage['id'];
      if (threadId == null || messageId == null) return;
      final usesRealtimeSchema = rawMessage.containsKey('MessageId') ||
          rawMessage.containsKey('CreatedDate') ||
          rawMessage.containsKey('SenderId');
      final message = usesRealtimeSchema
          ? MessageModel.fromWebSocketJson(rawMessage, threadId: threadId)
          : MessageModel.fromAcsJson(rawMessage, threadId: threadId);
      _emit(message, roomId: roomId);
      return;
    }

    // Payload các event còn lại chưa được backend công bố. Raw JSON đã được
    // log ở trên để bổ sung reducer mà không làm client crash.
  }

  void _emit(MessageModel message, {String? roomId}) {
    final threadController = _threadControllers[message.threadId];
    if (threadController != null && !threadController.isClosed) {
      threadController.add(message);
    }
    final listController = _listController;
    if (listController != null && !listController.isClosed) {
      listController.add(message);
    }
  }

  void _startHeartbeat(Duration interval) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) {
      _send({'type': 'heartbeat'});
    });
  }

  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(message));
  }

  Future<void> _handleDisconnected({int? closeCode, String? closeReason}) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    _channel = null;
    _serverConnected = false;
    if (_manualClose || _disposed) return;
    if (closeCode == 4001) return;
    if (_authCloseCodes.contains(closeCode) ||
        _looksLikeAuthError(closeReason ?? '')) {
      _expireSession();
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _manualClose || _sessionExpired ||
        _reconnectTimer?.isActive == true) return;
    const delays = [1, 2, 4, 8, 15, 30];
    final base = delays[min(_reconnectAttempt, delays.length - 1)];
    _reconnectAttempt++;
    final jitterMs = Random().nextInt(500);
    _reconnectTimer = Timer(Duration(seconds: base, milliseconds: jitterMs), () {
      unawaited(_ensureConnected());
    });
  }

  bool _looksLikeAuthError(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('401') ||
        normalized.contains('unauthorized') ||
        normalized.contains('token_expired') ||
        normalized.contains('token expired') ||
        normalized.contains('jwt expired');
  }

  void _expireSession() {
    if (_sessionExpired) return;
    _sessionExpired = true;
    _reconnectTimer?.cancel();
    _config.onSessionExpired?.call();
    unawaited(_closeSocket());
  }

  int? _intValue(dynamic value) => value is int
      ? value
      : value == null
          ? null
          : int.tryParse(value.toString());

  @override
  Stream<MessageModel> watchNewMessages(String roomId, String threadId) {
    _threadIdsByRoom[roomId] = threadId;
    final existing = _threadControllers[threadId];
    if (existing != null) return existing.stream;
    final controller = StreamController<MessageModel>.broadcast();
    _threadControllers[threadId] = controller;
    _activeRoomId = roomId;
    if (_serverConnected) {
      _send({'type': 'enter_room', 'roomId': roomId});
    } else {
      unawaited(_ensureConnected());
    }
    return controller.stream;
  }

  @override
  Stream<MessageModel> watchListMessages(String roomId) {
    final existing = _listController;
    if (existing != null) return existing.stream;
    _listController = StreamController<MessageModel>.broadcast();
    unawaited(_ensureConnected());
    return _listController!.stream;
  }

  @override
  Future<void> stopWatching(String threadId) async {
    final controller = _threadControllers.remove(threadId);
    final roomIds = _threadIdsByRoom.entries
        .where((entry) => entry.value == threadId)
        .map((entry) => entry.key)
        .toList();
    for (final roomId in roomIds) {
      _threadIdsByRoom.remove(roomId);
      if (_activeRoomId == roomId) _activeRoomId = null;
    }
    _send({'type': 'leave_room'});
    await controller?.close();
  }

  @override
  Future<void> stopWatchingList() async {
    final controller = _listController;
    _listController = null;
    await controller?.close();
    // Rời màn danh sách không đóng socket: kết nối thuộc session app, không
    // thuộc vòng đời của một màn hình. Socket chỉ đóng khi repository dispose
    // (logout/app teardown) hoặc phiên đăng nhập hết hạn.
  }

  Future<void> _closeSocket() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    final channel = _channel;
    _channel = null;
    _serverConnected = false;
    await channel?.sink.close();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _closeSocket();
    for (final controller in _threadControllers.values) {
      await controller.close();
    }
    _threadControllers.clear();
    _threadIdsByRoom.clear();
    await _listController?.close();
    _listController = null;
  }
}
