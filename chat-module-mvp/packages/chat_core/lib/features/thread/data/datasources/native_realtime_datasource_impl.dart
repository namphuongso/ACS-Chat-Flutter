import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/config/chat_module_config.dart';
import '../../../../core/utils/chat_logger.dart';
import '../../../auth_token/domain/repositories/chat_auth_token_provider.dart';
import '../../domain/entities/message.dart';
import '../../domain/services/system_message_text.dart';
import '../models/message_model.dart';
import 'native_realtime_datasource.dart';

typedef WebSocketRealtimeDataSourceImpl = NativeRealtimeDataSourceImpl;

/// Realtime app-wide qua backend WebSocket.
class NativeRealtimeDataSourceImpl implements NativeRealtimeDataSource {
  NativeRealtimeDataSourceImpl({
    required ChatModuleConfig config,
    ChatAuthTokenProvider? appTokenProvider,
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
    final threadId = data['threadId']?.toString() ??
        (roomId == null ? null : _threadIdsByRoom[roomId] ?? roomId);

    if (threadId == null && roomId == null) return;
    final targetId = threadId ?? roomId!;

    if (eventType == 'MessageDeleted') {
      final msgId = (data['messageId'] ?? data['MessageId'] ?? '').toString();
      if (msgId.isEmpty) return;
      final deletedAtRaw = data['deletedAtUtc']?.toString();
      final deletedAt = deletedAtRaw != null
          ? DateTime.tryParse(deletedAtRaw)
          : DateTime.now();
      final signal = MessageModel(
        id: msgId,
        threadId: targetId,
        senderId: (data['deletedBy'] ?? '').toString(),
        senderDisplayName: '',
        content: '(Tin nhắn đã bị xoá)',
        type: MessageType.text,
        createdAt: deletedAt ?? DateTime.now(),
        deletedOn: deletedAt,
      );
      _emit(signal, roomId: roomId);
      return;
    }

    if (eventType == 'MessagePinned' || eventType == 'MessageUnpinned') {
      final msgId = (data['messageId'] ?? data['MessageId'] ?? '').toString();
      if (msgId.isEmpty) return;
      final isPinned = eventType == 'MessagePinned';
      final signal = MessageModel(
        id: msgId,
        threadId: targetId,
        senderId: (data['actorId'] ?? '').toString(),
        senderDisplayName: (data['actorName'] ?? '').toString(),
        content: isPinned ? 'pin' : 'unpin',
        type: MessageType.messagePinUpdate,
        createdAt: DateTime.now(),
        pin: isPinned,
      );
      _emit(signal, roomId: roomId);
      return;
    }

    if (eventType == 'MessageReacted' ||
        eventType == 'MessageUnreacted' ||
        eventType == 'MessageReactionRemoved' ||
        eventType == 'MessageReactionUpdated' ||
        (eventType != null && eventType.toLowerCase().contains('react'))) {
      final msgId = (data['messageId'] ?? data['MessageId'] ?? '').toString();
      final signal = MessageModel(
        id: msgId,
        threadId: targetId,
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
      if (messageId == null) return;
      final usesRealtimeSchema = rawMessage.containsKey('MessageId') ||
          rawMessage.containsKey('CreatedDate') ||
          rawMessage.containsKey('SenderId');
      final message = usesRealtimeSchema
          ? MessageModel.fromWebSocketJson(rawMessage, threadId: targetId)
          : MessageModel.fromAcsJson(rawMessage, threadId: targetId);
      _emit(message, roomId: roomId);
      return;
    }

    if (eventType == 'RoomCreated') {
      final createdByName = (data['createdByName'] ?? '').toString();
      final content = SystemMessageTextBuilder.build(
            eventType: 'RoomCreated',
            json: data,
            actorFallback: createdByName,
          ) ??
          'Phòng mới đã được tạo';
      final signal = MessageModel(
        id: 'room_created_${DateTime.now().millisecondsSinceEpoch}',
        threadId: targetId,
        senderId: (data['createdByUserId'] ?? '').toString(),
        senderDisplayName: createdByName,
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'RoomCreated', ...data},
      );
      _emit(signal, roomId: roomId);
      return;
    }

    if (eventType == 'RoomUpdated') {
      final payload = (data['payload'] is Map)
          ? (data['payload'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final roomName =
          (data['roomName'] ?? payload['roomName'] ?? '').toString().trim();
      final avatarUrl =
          (data['avatarUrl'] ?? payload['avatarUrl'] ?? '').toString().trim();
      final actorName = (data['actorName'] ??
              data['updatedByName'] ??
              data['changedByName'] ??
              payload['actorName'] ??
              payload['updatedByName'] ??
              payload['changedByName'] ??
              '')
          .toString()
          .trim();
      final content = SystemMessageTextBuilder.build(
            eventType: 'RoomUpdated',
            json: data,
            payload: payload,
            actorFallback: actorName,
          ) ??
          'Thông tin nhóm đã được cập nhật';

      final eventId = (data['id'] ??
              data['eventId'] ??
              payload['id'] ??
              payload['eventId'] ??
              'room_updated_${DateTime.now().millisecondsSinceEpoch}')
          .toString();
      final signal = MessageModel(
        id: eventId,
        threadId: targetId,
        senderId: '',
        senderDisplayName: actorName,
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {
          'eventType': 'RoomUpdated',
          'id': eventId,
          'roomName': roomName,
          'avatarUrl': avatarUrl,
          'actorName': actorName,
          ...data,
        },
      );
      _emit(signal, roomId: roomId);
      return;
    }

    if (eventType == 'RoomDisbanded') {
      final content = SystemMessageTextBuilder.build(
            eventType: 'RoomDisbanded',
            json: data,
          ) ??
          'Phòng chat đã bị giải tán';
      final signal = MessageModel(
        id: 'room_disbanded_${DateTime.now().millisecondsSinceEpoch}',
        threadId: targetId,
        senderId: (data['disbandedBy'] ?? '').toString(),
        senderDisplayName: '',
        content: content,
        type: MessageType.roomDisbanded,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'RoomDisbanded', ...data},
      );
      _emit(signal, roomId: roomId);
      return;
    }

    if (eventType == 'RoomRoleChanged') {
      final payload = (data['payload'] is Map)
          ? (data['payload'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final actorName = (data['actorName'] ??
              data['changedByName'] ??
              data['actorDisplayName'] ??
              data['fromUserName'] ??
              payload['actorName'] ??
              payload['changedByName'] ??
              payload['actorDisplayName'] ??
              '')
          .toString()
          .trim();
      final targetName = (payload['userName'] ??
              payload['targetName'] ??
              payload['userDisplayName'] ??
              payload['memberName'] ??
              payload['memberUserName'] ??
              payload['toUserName'] ??
              data['targetName'] ??
              data['memberName'] ??
              data['userName'] ??
              data['memberUserName'] ??
              data['userDisplayName'] ??
              data['toUserName'] ??
              '')
          .toString()
          .trim();
      final content = SystemMessageTextBuilder.build(
            eventType: 'RoomRoleChanged',
            json: data,
            payload: payload,
            actorFallback: actorName,
            targetFallback: targetName,
          ) ??
          'Quyền Admin trong phòng đã thay đổi';

      final signal = MessageModel(
        id: 'room_role_${DateTime.now().millisecondsSinceEpoch}',
        threadId: targetId,
        senderId: actorName,
        senderDisplayName: '',
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'RoomRoleChanged', ...data},
      );
      _emit(signal, roomId: roomId);
      return;
    }

    if (eventType == 'RoomOwnershipTransferred') {
      final payload = (data['payload'] is Map)
          ? (data['payload'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final actorName = (data['actorName'] ??
              data['transferredByName'] ??
              data['fromUserName'] ??
              payload['actorName'] ??
              payload['transferredByName'] ??
              payload['fromUserName'] ??
              '')
          .toString()
          .trim();
      final targetName = (payload['toUserName'] ??
              payload['targetName'] ??
              payload['newOwnerName'] ??
              data['targetName'] ??
              data['toUserName'] ??
              data['newOwnerName'] ??
              '')
          .toString()
          .trim();

      final content = SystemMessageTextBuilder.build(
            eventType: 'RoomOwnershipTransferred',
            json: data,
            payload: payload,
            actorFallback: actorName,
            targetFallback: targetName,
          ) ??
          'Quyền Trưởng phòng đã được chuyển giao';

      final signal = MessageModel(
        id: 'room_owner_${DateTime.now().millisecondsSinceEpoch}',
        threadId: targetId,
        senderId: '',
        senderDisplayName: '',
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'RoomOwnershipTransferred', ...data},
      );
      _emit(signal, roomId: roomId);
      return;
    }

    if (eventType == 'RoomPinned' || eventType == 'RoomUnpinned') {
      final isPinned = eventType == 'RoomPinned';
      final signal = MessageModel(
        id: 'room_pin_${DateTime.now().millisecondsSinceEpoch}',
        threadId: targetId,
        senderId: '',
        senderDisplayName: '',
        content: isPinned ? 'room_pinned' : 'room_unpinned',
        type: isPinned
            ? MessageType.roomPinnedUpdate
            : MessageType.roomUnpinnedUpdate,
        createdAt: DateTime.now(),
        metadata: {
          'eventType': eventType,
          'isPinned': isPinned,
          'roomId': targetId
        },
      );
      _emit(signal, roomId: roomId);
      return;
    }

    if (eventType == 'MemberJoined') {
      final payload = (data['payload'] is Map)
          ? (data['payload'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final actorName = (data['actorName'] ??
              data['addedByName'] ??
              payload['actorName'] ??
              payload['addedByName'] ??
              '')
          .toString();
      final content = SystemMessageTextBuilder.build(
            eventType: 'MemberJoined',
            json: data,
            payload: payload,
            actorFallback: actorName,
          ) ??
          'Thành viên mới đã vào nhóm';
      final signal = MessageModel(
        id: 'member_joined_${DateTime.now().millisecondsSinceEpoch}',
        threadId: targetId,
        senderId:
            (data['actorUserId'] ?? data['addedByUserId'] ?? '').toString(),
        senderDisplayName: actorName,
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'MemberJoined', ...data},
      );
      _emit(signal, roomId: roomId);
      return;
    }

    if (eventType == 'MemberLeft') {
      final payload = (data['payload'] is Map)
          ? (data['payload'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final actorName = (data['actorName'] ??
              data['userName'] ??
              payload['actorName'] ??
              payload['userName'] ??
              '')
          .toString();
      final content = SystemMessageTextBuilder.build(
            eventType: 'MemberLeft',
            json: data,
            payload: payload,
            actorFallback: actorName,
          ) ??
          'Một thành viên đã rời khỏi nhóm';
      final signal = MessageModel(
        id: 'member_left_${DateTime.now().millisecondsSinceEpoch}',
        threadId: targetId,
        senderId: (data['userId'] ?? data['actorUserId'] ?? '').toString(),
        senderDisplayName: actorName,
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'MemberLeft', ...data},
      );
      _emit(signal, roomId: roomId);
      return;
    }

    if (eventType == 'MemberRemoved') {
      final payload = (data['payload'] is Map)
          ? (data['payload'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final removedUserId =
          (data['removedUserId'] ?? payload['removedUserId'] ?? '').toString();
      final removedByUserId = (data['removedByUserId'] ??
              data['actorUserId'] ??
              payload['removedByUserId'] ??
              payload['actorUserId'] ??
              '')
          .toString();
      final actorName = (data['actorName'] ??
              payload['actorName'] ??
              payload['removedByName'] ??
              '')
          .toString();
      final removedUserName = (data['removedUserName'] ??
              payload['removedUserName'] ??
              payload['targetName'] ??
              '')
          .toString();

      final content = SystemMessageTextBuilder.build(
            eventType: 'MemberRemoved',
            json: data,
            payload: payload,
            actorFallback: actorName,
            targetFallback: removedUserName,
          ) ??
          'Một thành viên đã bị xóa khỏi nhóm';

      final signal = MessageModel(
        id: 'member_removed_${DateTime.now().millisecondsSinceEpoch}',
        threadId: targetId,
        senderId: removedByUserId,
        senderDisplayName: actorName,
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {
          'eventType': 'MemberRemoved',
          'removedUserId': removedUserId,
          'removedByUserId': removedByUserId,
          'removedUserName': removedUserName,
          'actorName': actorName,
          ...data
        },
      );
      _emit(signal, roomId: roomId);
      return;
    }
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
      final targetRooms = <String>{};
      if (roomId != null && roomId.isNotEmpty) {
        targetRooms.add(roomId);
      }
      targetRooms.addAll(_activeRoomIds);
      targetRooms.addAll(_watchedRoomIds);
      targetRooms.addAll(_threadIdsByRoom.keys);

      if (targetRooms.isEmpty) {
        ChatLogger.log(
            '[sendReadMessage] Skipped: no target rooms for $lastVisibleMessageId');
        return;
      }

      for (final rId in targetRooms) {
        _send({
          'type': 'read',
          'roomId': rId,
          'lastVisibleMessageId': lastVisibleMessageId,
        });
      }
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

    final existing = _threadControllers[threadId];
    if (existing != null) return existing.stream;

    final controller = StreamController<MessageModel>.broadcast();
    _threadControllers[threadId] = controller;
    return controller.stream;
  }

  @override
  Stream<MessageModel> watchListMessages() {
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
      _activeRoomIds.remove(roomId);
      _watchedRoomIds.remove(roomId);
      if (_serverConnected) {
        _send({'type': 'leave_room', 'roomId': roomId});
      }
    }
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
