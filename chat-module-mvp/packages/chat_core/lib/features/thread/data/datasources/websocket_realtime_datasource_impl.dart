import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/config/chat_module_config.dart';
import '../../../../core/utils/chat_logger.dart';
import '../../../auth_token/domain/repositories/chat_auth_token_provider.dart';
import '../models/message_model.dart';
import 'websocket_event_dispatcher.dart';
import 'websocket_event_parser.dart';
import 'websocket_realtime_datasource.dart';

/// Alias tương thích ngược cho tên cũ.
typedef NativeRealtimeDataSourceImpl = WebSocketRealtimeDataSourceImpl;

/// Realtime app-wide qua backend WebSocket.
class WebSocketRealtimeDataSourceImpl implements WebSocketRealtimeDataSource {
  WebSocketRealtimeDataSourceImpl({
    required ChatModuleConfig config,
    ChatAuthTokenProvider? appTokenProvider,
  })  : _config = config,
        _appTokenProvider = appTokenProvider,
        _deviceId = config.deviceId ?? _createProcessDeviceId();

  final ChatModuleConfig _config;
  final ChatAuthTokenProvider? _appTokenProvider;
  final String _deviceId;
  final WebSocketEventDispatcher _dispatcher = WebSocketEventDispatcher();

  final Map<String, String> _threadIdsByRoom = {};

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
  final Set<String> _activeRoomIds = {};
  final Set<String> _watchedRoomIds = {};
  DateTime _lastReceivedTime = DateTime.now();
  String? _lastVisibleMessageId;

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
      _lastReceivedTime = DateTime.now();
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
      _lastReceivedTime = DateTime.now();
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return;
      final event = decoded.cast<String, dynamic>();
      if (ChatLogger.enabled) {
        final prettyJson = const JsonEncoder.withIndent('  ').convert(event);
        ChatLogger.log('WebSocket event:\n$prettyJson');
      }
      final type = event['type']?.toString();

      if (type == 'connected') {
        _serverConnected = true;
        final interval = _intValue(event['heartbeatIntervalSeconds']) ?? 30;
        _startHeartbeat(Duration(seconds: max(5, interval)));
        final roomsToEnter = {..._activeRoomIds, ..._watchedRoomIds};
        for (final roomId in roomsToEnter) {
          _send({'type': 'enter_room', 'roomId': roomId});
        }
        return;
      }
      if (type == 'error') {
        final code =
            event['errorCode']?.toString() ?? event['code']?.toString();
        final message = event['message']?.toString() ?? '';
        if (_looksLikeAuthError('$code $message')) _expireSession();
        return;
      }
      if (type != 'room_event') return;
      
      final parsedMessage = WebSocketEventParser.parseRoomEvent(
        event,
        threadIdsByRoom: _threadIdsByRoom,
      );
      if (parsedMessage != null) {
        _dispatcher.emit(parsedMessage);
      }
    } catch (error) {
      ChatLogger.log('Ignored malformed WebSocket event: $error raw=$raw');
    }
  }

  void _startHeartbeat(Duration interval) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(interval, (_) {
      if (DateTime.now().difference(_lastReceivedTime) > interval * 2) {
        ChatLogger.log(
            'WebSocket idle timeout — no packet received for ${interval.inSeconds * 2}s. Reconnecting...');
        unawaited(_handleDisconnected());
        return;
      }
      final msg = <String, dynamic>{'type': 'heartbeat'};
      if (_lastVisibleMessageId != null && _lastVisibleMessageId!.isNotEmpty) {
        msg['lastVisibleMessageId'] = _lastVisibleMessageId;
      }
      _send(msg);
    });
  }

  bool _isAppPaused = false;

  @override
  void sendReadMessage(String lastVisibleMessageId, {String? roomId}) {
    if (lastVisibleMessageId.isEmpty) return;
    if (_isAppPaused) {
      ChatLogger.log(
          '[sendReadMessage] Skipped: app is paused / in background');
      return;
    }
    if (_lastVisibleMessageId == lastVisibleMessageId) {
      ChatLogger.log(
          '[sendReadMessage] Skipped: already sent for $lastVisibleMessageId');
      return;
    }
    _lastVisibleMessageId = lastVisibleMessageId;
    if (_serverConnected) {
      final targetRoomId = (roomId != null && roomId.isNotEmpty)
          ? roomId
          : (_activeRoomIds.isNotEmpty ? _activeRoomIds.first : null);

      if (targetRoomId == null || targetRoomId.isEmpty) {
        ChatLogger.log(
            '[sendReadMessage] Skipped: no target room for $lastVisibleMessageId');
        return;
      }

      _send({
        'type': 'read',
        'roomId': targetRoomId,
        'lastVisibleMessageId': lastVisibleMessageId,
      });
    } else {
      ChatLogger.log('[sendReadMessage] Skipped: _serverConnected is false');
    }
  }

  @override
  void clearReadMessageState() {
    _lastVisibleMessageId = null;
  }

  @override
  void leaveActiveRoom() {
    _isAppPaused = true;
    final roomsToLeave = {
      ..._activeRoomIds,
      ..._watchedRoomIds,
      ..._threadIdsByRoom.keys
    };
    if (_serverConnected && roomsToLeave.isNotEmpty) {
      for (final roomId in roomsToLeave) {
        _send({
          'type': 'leave_room',
          'roomId': roomId,
          if (_lastVisibleMessageId != null &&
              _lastVisibleMessageId!.isNotEmpty)
            'lastVisibleMessageId': _lastVisibleMessageId,
        });
      }
    }
    _lastVisibleMessageId = null;
    _activeRoomIds.clear();
  }

  @override
  void resetSession() {
    _sessionExpired = false;
    _reconnectAttempt = 0;
    if (!_disposed && _channel == null) {
      unawaited(_ensureConnected());
    }
  }

  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    final encoded = jsonEncode(message);
    ChatLogger.log('WebSocket send: $encoded');
    channel.sink.add(encoded);
  }

  Future<void> _handleDisconnected(
      {int? closeCode, String? closeReason}) async {
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
    if (_disposed ||
        _manualClose ||
        _sessionExpired ||
        _reconnectTimer?.isActive == true) return;
    const delays = [1, 2, 4, 8, 15, 30];
    final base = delays[min(_reconnectAttempt, delays.length - 1)];
    _reconnectAttempt++;
    final jitterMs = Random().nextInt(500);
    _reconnectTimer =
        Timer(Duration(seconds: base, milliseconds: jitterMs), () {
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
    _isAppPaused = false;
    _threadIdsByRoom[roomId] = threadId;
    _activeRoomIds.add(roomId);
    _watchedRoomIds.add(roomId);
    _lastVisibleMessageId = null;

    if (_serverConnected) {
      _send({'type': 'enter_room', 'roomId': roomId});
    } else {
      unawaited(_ensureConnected());
    }

    return _dispatcher.watchNewMessages(threadId);
  }

  @override
  Stream<MessageModel> watchListMessages() {
    unawaited(_ensureConnected());
    return _dispatcher.watchListMessages();
  }

  @override
  Future<void> stopWatching(String threadId) async {
    final roomIds = _threadIdsByRoom.entries
        .where((entry) => entry.value == threadId)
        .map((entry) => entry.key)
        .toList();
    for (final roomId in roomIds) {
      _threadIdsByRoom.remove(roomId);
      _activeRoomIds.remove(roomId);
      _watchedRoomIds.remove(roomId);
      if (_serverConnected) {
        _send({'type': 'leave_room', 'roomId': roomId});
      }
    }
    await _dispatcher.stopWatching(threadId);
    _checkIdleSocketClose();
  }

  @override
  Future<void> stopWatchingList() async {
    await _dispatcher.stopWatchingList();
    _checkIdleSocketClose();
  }

  void _checkIdleSocketClose() {
    if (_dispatcher.threadControllers.isEmpty &&
        _threadIdsByRoom.isEmpty &&
        _watchedRoomIds.isEmpty) {
      unawaited(_closeSocket());
    }
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
    await _dispatcher.dispose();
    _threadIdsByRoom.clear();
  }
}
