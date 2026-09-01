import 'dart:math';
import '../../domain/entities/message.dart';
import '../../domain/services/system_message_text.dart';
import '../models/message_model.dart';

/// Pure parser converting raw WebSocket room_event payloads into MessageModel entities.
class WebSocketEventParser {
  static int _eventIdCounter = 0;

  static String _generateUniqueEventId(String prefix) {
    _eventIdCounter++;
    final randomHex = Random().nextInt(1 << 32).toRadixString(16);
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_eventIdCounter}_$randomHex';
  }

  static MessageModel? parseRoomEvent(
    Map<String, dynamic> event, {
    Map<String, String> threadIdsByRoom = const {},
  }) {
    final eventType = event['eventType']?.toString();
    final payload = event['payload'];
    if (payload is! Map) return null;
    final data = payload.cast<String, dynamic>();
    final roomId = event['roomId']?.toString() ?? data['roomId']?.toString();
    final threadId = data['threadId']?.toString() ??
        (roomId == null ? null : threadIdsByRoom[roomId] ?? roomId);

    if (threadId == null && roomId == null) return null;
    final targetId = threadId ?? roomId!;

    if (eventType == 'MessageDeleted') {
      final msgId = (data['messageId'] ?? data['MessageId'] ?? '').toString();
      if (msgId.isEmpty) return null;
      final deletedAtRaw = (data['deletedAtUtc'] ??
              data['deletedAt'] ??
              data['deletedOn'] ??
              data['DeletedAtUtc'])
          ?.toString();
      final deletedAt = deletedAtRaw != null && deletedAtRaw.isNotEmpty
          ? DateTime.tryParse(deletedAtRaw)?.toLocal()
          : DateTime.now();
      return MessageModel(
        id: msgId,
        threadId: targetId,
        senderId: (data['deletedBy'] ?? '').toString(),
        senderDisplayName: '',
        content: '',
        type: MessageType.text,
        createdAt: DateTime.tryParse(
              (data['createdDate'] ??
                      data['createdOn'] ??
                      data['CreatedDate'] ??
                      '')
                  .toString(),
            )?.toLocal() ??
            deletedAt ??
            DateTime.now(),
        deletedOn: deletedAt ?? DateTime.now(),
      );
    }

    if (eventType == 'MessagePinned' || eventType == 'MessageUnpinned') {
      final msgId = (data['messageId'] ?? data['MessageId'] ?? '').toString();
      if (msgId.isEmpty) return null;
      final isPinned = eventType == 'MessagePinned';
      return MessageModel(
        id: msgId,
        threadId: targetId,
        senderId: (data['actorId'] ?? '').toString(),
        senderDisplayName: (data['actorName'] ?? '').toString(),
        content: isPinned ? 'pin' : 'unpin',
        type: MessageType.messagePinUpdate,
        createdAt: DateTime.now(),
        pin: isPinned,
      );
    }

    if (eventType == 'MessageReacted' ||
        eventType == 'MessageUnreacted' ||
        eventType == 'MessageReactionRemoved' ||
        eventType == 'MessageReactionUpdated' ||
        (eventType != null && eventType.toLowerCase().contains('react'))) {
      final msgId = (data['messageId'] ?? data['MessageId'] ?? '').toString();
      final actorId = (data['actorId'] ?? '').toString();
      final code = data['reactionCode']?.toString() ?? '';
      return MessageModel(
        id: 'react_${msgId}_${actorId}_${code}_${DateTime.now().microsecondsSinceEpoch}',
        threadId: targetId,
        senderId: actorId,
        senderDisplayName: (data['actorName'] ?? '').toString(),
        content: code,
        type: MessageType.reactionUpdate,
        createdAt: DateTime.now(),
        metadata: {'targetMessageId': msgId, ...data},
      );
    }

    if (eventType == 'NewMessage' || eventType == 'MessageUpdated') {
      final rawMessage = data['message'] is Map
          ? (data['message'] as Map).cast<String, dynamic>()
          : data;
      final messageId = rawMessage['MessageId'] ??
          rawMessage['messageId'] ??
          rawMessage['id'];
      if (messageId == null) return null;
      final usesRealtimeSchema = rawMessage.containsKey('MessageId') ||
          rawMessage.containsKey('CreatedDate') ||
          rawMessage.containsKey('SenderId');
      final parsed = usesRealtimeSchema
          ? MessageModel.fromWebSocketJson(rawMessage, threadId: targetId)
          : MessageModel.fromServerJson(rawMessage, threadId: targetId);

      if (eventType == 'MessageUpdated') {
        final meta = parsed.metadata != null
            ? Map<String, dynamic>.from(parsed.metadata!)
            : <String, dynamic>{};
        meta['eventType'] = 'MessageUpdated';
        return MessageModel(
          id: parsed.id,
          threadId: parsed.threadId,
          senderId: parsed.senderId,
          senderDisplayName: parsed.senderDisplayName,
          content: parsed.content,
          type: parsed.type,
          createdAt: parsed.createdAt,
          status: parsed.status,
          pin: parsed.pin,
          deletedOn: parsed.deletedOn,
          metadata: meta,
        );
      }
      return parsed;
    }

    if (eventType == 'RoomCreated') {
      final createdByName = (data['createdByName'] ?? '').toString();
      final content = SystemMessageTextBuilder.build(
            eventType: 'RoomCreated',
            json: data,
            actorFallback: createdByName,
          ) ??
          'Phòng mới đã được tạo';
      return MessageModel(
        id: _generateUniqueEventId('room_created'),
        threadId: targetId,
        senderId: (data['createdByUserId'] ?? '').toString(),
        senderDisplayName: createdByName,
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'RoomCreated', ...data},
      );
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
              _generateUniqueEventId('room_updated'))
          .toString();
      return MessageModel(
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
    }

    if (eventType == 'RoomDisbanded') {
      final content = SystemMessageTextBuilder.build(
            eventType: 'RoomDisbanded',
            json: data,
          ) ??
          'Phòng chat đã bị giải tán';
      return MessageModel(
        id: _generateUniqueEventId('room_disbanded'),
        threadId: targetId,
        senderId: (data['disbandedBy'] ?? '').toString(),
        senderDisplayName: '',
        content: content,
        type: MessageType.roomDisbanded,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'RoomDisbanded', ...data},
      );
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

      return MessageModel(
        id: _generateUniqueEventId('room_role'),
        threadId: targetId,
        senderId: actorName,
        senderDisplayName: '',
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'RoomRoleChanged', ...data},
      );
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

      return MessageModel(
        id: _generateUniqueEventId('room_owner'),
        threadId: targetId,
        senderId: '',
        senderDisplayName: '',
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'RoomOwnershipTransferred', ...data},
      );
    }

    if (eventType == 'RoomPinned' || eventType == 'RoomUnpinned') {
      final isPinned = eventType == 'RoomPinned';
      return MessageModel(
        id: _generateUniqueEventId('room_pin'),
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
      return MessageModel(
        id: _generateUniqueEventId('member_joined'),
        threadId: targetId,
        senderId:
            (data['actorUserId'] ?? data['addedByUserId'] ?? '').toString(),
        senderDisplayName: actorName,
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'MemberJoined', ...data},
      );
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
      return MessageModel(
        id: _generateUniqueEventId('member_left'),
        threadId: targetId,
        senderId: (data['userId'] ?? data['actorUserId'] ?? '').toString(),
        senderDisplayName: actorName,
        content: content,
        type: MessageType.system,
        createdAt: DateTime.now(),
        metadata: {'eventType': 'MemberLeft', ...data},
      );
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

      return MessageModel(
        id: _generateUniqueEventId('member_removed'),
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
    }

    return null;
  }
}
