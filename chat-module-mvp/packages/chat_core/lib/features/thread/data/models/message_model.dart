import 'dart:convert';

import '../../domain/entities/message.dart';

class MessageModel extends Message {
  const MessageModel({
    required super.id,
    required super.threadId,
    required super.senderId,
    required super.senderDisplayName,
    required super.content,
    required super.type,
    required super.createdAt,
    super.status = MessageDeliveryStatus.sent,
    super.metadata,
    super.pin = false,
    super.deletedOn,
  });

  factory MessageModel.fromAcsJson(Map<String, dynamic> rawJson,
      {required String threadId}) {
    final itemType = rawJson['itemType']?.toString();
    final json = (itemType != null && rawJson['data'] is Map)
        ? (rawJson['data'] as Map).cast<String, dynamic>()
        : rawJson;

    if (itemType == 'event' || json.containsKey('eventType')) {
      final eventType = json['eventType']?.toString() ?? '';
      final payload = (json['payload'] is Map)
          ? (json['payload'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      final actorName = (json['actorName'] ??
              json['actorDisplayName'] ??
              json['senderDisplayName'] ??
              json['createdByName'] ??
              json['updatedByName'] ??
              (json['actor'] is Map ? (json['actor']['displayName'] ?? json['actor']['userName']) : null) ??
              payload['actorName'] ??
              payload['actorDisplayName'] ??
              payload['changedByName'] ??
              payload['addedByName'] ??
              payload['removedByName'] ??
              payload['updatedByName'] ??
              payload['fromUserName'] ??
              (payload['actor'] is Map ? (payload['actor']['displayName'] ?? payload['actor']['userName']) : null) ??
              '')
          .toString()
          .trim();

      final String content;
      if (eventType == 'RoomOwnershipTransferred') {
        final toUserName = (payload['toUserName'] ??
                payload['targetName'] ??
                payload['targetDisplayName'] ??
                payload['newOwnerName'] ??
                (payload['targetUser'] is Map ? (payload['targetUser']['displayName'] ?? payload['targetUser']['userName']) : null) ??
                '')
            .toString()
            .trim();
        if (actorName.isNotEmpty && toUserName.isNotEmpty) {
          content = '**$actorName** đã chuyển quyền Trưởng phòng cho **$toUserName**';
        } else if (toUserName.isNotEmpty) {
          content = '**$toUserName** đã trở thành Trưởng phòng mới';
        } else if (actorName.isNotEmpty) {
          content = '**$actorName** đã chuyển quyền Trưởng phòng';
        } else {
          content = 'Quyền Trưởng phòng đã được chuyển giao';
        }
      } else if (eventType == 'RoomRoleChanged') {
        final userName = (payload['userName'] ??
                payload['targetName'] ??
                payload['targetDisplayName'] ??
                payload['memberName'] ??
                payload['memberUserName'] ??
                payload['userDisplayName'] ??
                payload['toUserName'] ??
                '')
            .toString()
            .trim();
        final rawActorName = (json['actorName'] ??
                json['actorDisplayName'] ??
                payload['actorName'] ??
                payload['changedByName'] ??
                payload['actorDisplayName'] ??
                payload['fromUserName'] ??
                '')
            .toString()
            .trim();
        final isAdmin = payload['isAdmin'] == true ||
            payload['role']?.toString().toLowerCase() == 'admin' ||
            payload['newRole']?.toString().toLowerCase() == 'admin';

        final actor = rawActorName.isNotEmpty ? rawActorName : actorName;

        if (actor.isNotEmpty && userName.isNotEmpty) {
          content = isAdmin
              ? '**$actor** đã phong **$userName** làm Admin'
              : '**$actor** đã gỡ quyền Admin của **$userName**';
        } else if (userName.isNotEmpty) {
          content = isAdmin
              ? '**$userName** đã được phong làm Admin'
              : '**$userName** đã bị gỡ quyền Admin';
        } else if (actor.isNotEmpty) {
          content = isAdmin
              ? '**$actor** đã thêm Admin mới'
              : '**$actor** đã gỡ quyền Admin';
        } else {
          content = 'Quyền Admin trong phòng đã thay đổi';
        }
      } else if (eventType == 'MemberRemoved') {
        final removedUserName = (payload['removedUserName'] ??
                payload['removedUserDisplayName'] ??
                payload['targetName'] ??
                payload['targetDisplayName'] ??
                payload['userName'] ??
                (payload['removedUser'] is Map ? (payload['removedUser']['displayName'] ?? payload['removedUser']['userName']) : null) ??
                json['removedUserName'] ??
                json['targetName'] ??
                '')
            .toString()
            .trim();
        if (actorName.isNotEmpty && removedUserName.isNotEmpty) {
          content = '**$actorName** đã xóa **$removedUserName** khỏi nhóm';
        } else if (removedUserName.isNotEmpty) {
          content = '**$removedUserName** đã bị xóa khỏi nhóm';
        } else if (actorName.isNotEmpty) {
          content = '**$actorName** đã xóa một thành viên khỏi nhóm';
        } else {
          content = 'Một thành viên đã bị xóa khỏi nhóm';
        }
      } else if (eventType == 'MemberJoined') {
        final addedUsers = payload['addedUsers'] as List? ?? json['addedUsers'] as List? ?? const [];
        final addedNames = addedUsers
            .map((u) => u is Map ? (u['displayName'] ?? u['userName'] ?? u['userDisplayName'])?.toString().trim() : u.toString().trim())
            .where((n) => n != null && n.isNotEmpty)
            .cast<String>()
            .join(', ');
        final targetNames = addedNames.isNotEmpty
            ? addedNames
            : (payload['targetName'] ?? payload['targetDisplayName'] ?? payload['userName'] ?? payload['addedUserName'] ?? '').toString().trim();

        if (actorName.isNotEmpty && targetNames.isNotEmpty) {
          content = '**$actorName** đã thêm **$targetNames** vào nhóm';
        } else if (targetNames.isNotEmpty) {
          content = '**$targetNames** đã vào nhóm';
        } else if (actorName.isNotEmpty) {
          content = '**$actorName** đã thêm thành viên mới vào nhóm';
        } else {
          content = 'Thành viên mới đã vào nhóm';
        }
      } else if (eventType == 'MemberLeft') {
        final userName = actorName.isNotEmpty
            ? actorName
            : (payload['userName'] ?? payload['targetName'] ?? payload['actorDisplayName'] ?? '').toString().trim();
        if (userName.isNotEmpty) {
          content = '**$userName** đã rời khỏi nhóm';
        } else {
          content = 'Một thành viên đã rời khỏi nhóm';
        }
      } else if (eventType == 'RoomUpdated') {
        final roomName = (payload['roomName'] ?? json['roomName'] ?? '').toString().trim();
        final avatarUrl = (payload['avatarUrl'] ?? json['avatarUrl'] ?? '').toString().trim();
        final rawActorName = (json['actorName'] ??
                payload['actorName'] ??
                payload['updatedByName'] ??
                '')
            .toString()
            .trim();
        final actor = rawActorName.isNotEmpty ? rawActorName : actorName;
        final isAvatarChanged = payload['isAvatarChanged'] == true;
        final isNameChanged = payload['isNameChanged'] == true;

        if (isNameChanged && isAvatarChanged) {
          content = actor.isNotEmpty
              ? '**$actor** đã đổi tên và ảnh đại diện nhóm'
              : 'Tên và ảnh đại diện nhóm đã được cập nhật';
        } else if (isAvatarChanged) {
          content = actor.isNotEmpty
              ? '**$actor** đã cập nhật ảnh đại diện nhóm'
              : 'Ảnh đại diện nhóm đã được cập nhật';
        } else if (isNameChanged) {
          content = actor.isNotEmpty
              ? '**$actor** đã đổi tên nhóm thành **$roomName**'
              : 'Tên nhóm đã được đổi thành **$roomName**';
        } else if (actor.isNotEmpty && roomName.isNotEmpty) {
          content = '**$actor** đã đổi tên nhóm thành **$roomName**';
        } else if (roomName.isNotEmpty) {
          content = 'Tên nhóm đã được đổi thành **$roomName**';
        } else if (actor.isNotEmpty) {
          content = avatarUrl.isNotEmpty
              ? '**$actor** đã cập nhật ảnh đại diện nhóm'
              : '**$actor** đã cập nhật thông tin nhóm';
        } else {
          content = avatarUrl.isNotEmpty
              ? 'Ảnh đại diện nhóm đã được cập nhật'
              : 'Thông tin nhóm đã được cập nhật';
        }
      } else if (eventType == 'RoomCreated' ||
          eventType == 'CreateRoom' ||
          eventType == 'RoomCreate') {
        final creatorName = (json['actorName'] ??
                payload['actorName'] ??
                payload['createdByName'] ??
                payload['createdUser']?['userName'] ??
                actorName)
            .toString()
            .trim();
        final roomName =
            (payload['roomName'] ?? json['roomName'] ?? '').toString().trim();
        if (creatorName.isNotEmpty && roomName.isNotEmpty) {
          content = '**$creatorName** đã tạo nhóm **$roomName**';
        } else if (creatorName.isNotEmpty) {
          content = '**$creatorName** đã tạo nhóm chat';
        } else if (roomName.isNotEmpty) {
          content = 'Nhóm **$roomName** đã được tạo';
        } else {
          content = 'Nhóm chat đã được tạo';
        }
      } else if (eventType == 'RoomDisbanded' ||
          eventType == 'RoomClosed' ||
          eventType == 'CloseRoom') {
        content = actorName.isNotEmpty
            ? '**$actorName** đã giải tán nhóm'
            : 'Phòng chat đã bị giải tán';
      } else {
        content = 'Sự kiện hệ thống trong phòng';
      }

      final createdRaw = (json['createdDate'] ??
              json['createdOn'] ??
              rawJson['createdDate'] ??
              '')
          .toString();

      final isDisbandEvent = eventType == 'RoomDisbanded' ||
          eventType == 'RoomClosed' ||
          eventType == 'CloseRoom';

      return MessageModel(
        id: (json['id'] ??
                rawJson['id'] ??
                'event_${DateTime.now().millisecondsSinceEpoch}')
            .toString(),
        threadId: threadId,
        senderId: (json['actorUserId'] ?? '').toString(),
        senderDisplayName: actorName,
        content: content,
        type: isDisbandEvent ? MessageType.roomDisbanded : MessageType.system,
        createdAt: DateTime.tryParse(createdRaw)?.toLocal() ?? DateTime.now(),
        metadata: {'eventType': eventType, ...json, ...payload},
      );
    }

    final rawType = json['type'] as String? ?? 'text';
    final sender = json['senderDisplayName'] as String? ?? 'Unknown';
    final senderMap =
        json['senderCommunicationIdentifier'] as Map<String, dynamic>?;
    final senderId = senderMap?['rawId']?.toString() ??
        (json['sender'] as Map<String, dynamic>?)?['communicationIdentifier']
            ?.toString() ??
        json['senderId'] as String? ??
        '';

    return MessageModel(
      id: (json['id'] ?? rawJson['id'] ?? '').toString(),
      threadId: threadId,
      senderId: senderId,
      senderDisplayName: sender,
      content: _contentFromAcsJson(json, rawType),
      type: MessageType.fromString(rawType),
      createdAt: () {
        final rawStr = json['createdOn']?.toString() ??
            json['createdAt']?.toString() ??
            rawJson['createdDate']?.toString();
        if (rawStr != null && rawStr.isNotEmpty) {
          final parsed = DateTime.tryParse(rawStr);
          if (parsed != null) return parsed.toLocal();
        }
        return DateTime.now();
      }(),
      deletedOn: () {
        final rawStr = json['deletedOn']?.toString();
        if (rawStr != null && rawStr.isNotEmpty) {
          return DateTime.tryParse(rawStr)?.toLocal();
        }
        return null;
      }(),
      metadata: _metadataFromJson(
          json['metadata'] ?? json['metaData'] ?? json['Metadata']),
    );
  }

  /// Payload realtime của backend hiện dùng PascalCase và không bọc trong
  /// object `content` giống API get-messages.
  factory MessageModel.fromWebSocketJson(
    Map<String, dynamic> json, {
    required String threadId,
  }) {
    final deletedOn = json['DeletedDate'] ?? json['deletedDate'];
    return MessageModel(
      id: (json['MessageId'] ?? json['messageId'] ?? json['id']).toString(),
      threadId: threadId,
      senderId:
          (json['SenderId'] ?? json['senderId'] ?? '').toString(),
      senderDisplayName:
          (json['SenderName'] ?? json['senderName'] ?? '').toString(),
      content: (json['Content'] ?? json['content'] ?? '').toString(),
      type: MessageType.fromString(
        (json['Type'] ?? json['type'] ?? 'text').toString(),
      ),
      createdAt: DateTime.tryParse(
                (json['CreatedDate'] ?? json['createdDate'] ?? '').toString(),
              )?.toLocal() ??
          DateTime.now(),
      deletedOn: deletedOn == null
          ? null
          : DateTime.tryParse(deletedOn.toString())?.toLocal(),
      metadata: _metadataFromJson(json['Metadata'] ??
          json['metadata'] ??
          json['MetaData'] ??
          json['metaData']),
    );
  }

  static Map<String, dynamic>? _metadataFromJson(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      if (raw.isEmpty) return null;
      return raw.cast<String, dynamic>();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded.isNotEmpty) {
          return decoded.cast<String, dynamic>();
        }
      } catch (_) {}
    }
    return null;
  }

  static String _contentFromAcsJson(Map<String, dynamic> json, String rawType) {
    final content = json['content'];
    if (content is! Map) return content as String? ?? '';
    final map = content.cast<String, dynamic>();

    if (rawType == 'participantAdded' || rawType == 'participantRemoved') {
      final names = (map['participants'] as List? ?? const [])
          .whereType<Map>()
          .map((participant) => participant['displayName']?.toString().trim())
          .whereType<String>()
          .where((name) => name.isNotEmpty)
          .toList();
      if (names.isEmpty) {
        return rawType == 'participantAdded'
            ? 'Đã thêm thành viên vào nhóm'
            : 'Đã xóa thành viên khỏi nhóm';
      }
      final joinedNames = names.join(', ');
      return rawType == 'participantAdded'
          ? '**$joinedNames** đã được thêm vào nhóm'
          : '**$joinedNames** đã bị xóa khỏi nhóm';
    }

    if (rawType == 'topicUpdated') {
      final topic = map['topic']?.toString().trim() ?? '';
      return topic.isEmpty
          ? 'Tên nhóm đã được cập nhật'
          : 'Tên nhóm đã được đổi thành "**$topic**"';
    }

    return map['message'] as String? ?? '';
  }
}
