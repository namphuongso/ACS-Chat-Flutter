import 'package:chat_core/chat_core.dart';
import 'identity_resolver.dart';

/// Xây dựng và bổ sung thông tin hiển thị (bôi đậm tên người tham gia)
/// cho các tin nhắn sự kiện hệ thống.
class SystemMessageEnricher {
  const SystemMessageEnricher({
    required this.identityResolver,
  });

  final IdentityResolver identityResolver;

  Message enrich({
    required String roomId,
    required Message message,
    required String currentUserId,
    String? myAcsUserId,
  }) {
    if (message.type != MessageType.system || message.metadata == null) {
      return message;
    }
    // Nếu tin nhắn hệ thống đã được format chứa bôi đậm tên (**), giữ nguyên nội dung
    if (message.content.contains('**')) return message;

    final metadata = message.metadata!;
    final eventType = metadata['eventType']?.toString();
    if (eventType == null) return message;

    final payload = (metadata['payload'] is Map)
        ? (metadata['payload'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final String? actorId = (metadata['actorUserId'] ??
            metadata['actorId'] ??
            metadata['addedByUserId'] ??
            metadata['removedByUserId'] ??
            metadata['changedByUserId'] ??
            metadata['transferredByUserId'] ??
            payload['actorUserId'] ??
            payload['addedByUserId'] ??
            payload['removedByUserId'] ??
            payload['changedByUserId'])
        ?.toString();
    final String? targetId = (metadata['removedUserId'] ??
            metadata['userId'] ??
            metadata['memberUserId'] ??
            metadata['targetUserId'] ??
            metadata['toUserId'] ??
            metadata['transferredToUserId'] ??
            payload['removedUserId'] ??
            payload['targetUserId'] ??
            payload['toUserId'])
        ?.toString();

    final rawActorName = metadata['actorName']?.toString() ??
        metadata['actorDisplayName']?.toString() ??
        metadata['changedByName']?.toString() ??
        metadata['addedByName']?.toString() ??
        metadata['removedByName']?.toString() ??
        metadata['transferredByName']?.toString() ??
        metadata['updatedByName']?.toString() ??
        payload['actorName']?.toString() ??
        payload['actorDisplayName']?.toString() ??
        payload['changedByName']?.toString() ??
        payload['addedByName']?.toString() ??
        payload['removedByName']?.toString();
    final rawTargetName = metadata['removedUserName']?.toString() ??
        metadata['removedUserDisplayName']?.toString() ??
        metadata['targetName']?.toString() ??
        metadata['targetDisplayName']?.toString() ??
        metadata['userName']?.toString() ??
        metadata['memberName']?.toString() ??
        metadata['toUserName']?.toString() ??
        metadata['newOwnerName']?.toString() ??
        payload['removedUserName']?.toString() ??
        payload['removedUserDisplayName']?.toString() ??
        payload['targetName']?.toString() ??
        payload['targetDisplayName']?.toString() ??
        payload['userName']?.toString() ??
        payload['toUserName']?.toString();

    final actorName = (rawActorName != null && rawActorName.trim().isNotEmpty)
        ? rawActorName.trim()
        : (actorId != null && actorId.isNotEmpty
            ? identityResolver.getDisplayName(roomId, actorId, '')
            : '');
    final targetName =
        (rawTargetName != null && rawTargetName.trim().isNotEmpty)
            ? rawTargetName.trim()
            : (targetId != null && targetId.isNotEmpty
                ? identityResolver.getDisplayName(roomId, targetId, '')
                : '');

    final isSelfRemoved = eventType == 'MemberRemoved' &&
        targetId != null &&
        (AcsUserUtils.isSameAcsUser(targetId, currentUserId) ||
            (myAcsUserId != null &&
                AcsUserUtils.isSameAcsUser(targetId, myAcsUserId)));

    final newContent = SystemMessageTextBuilder.build(
      eventType: eventType,
      json: metadata,
      payload: payload,
      actorFallback: actorName,
      targetFallback: targetName,
      joinedUserFallbacks: targetName.isNotEmpty ? [targetName] : const [],
      isSelfRemoved: isSelfRemoved,
    );

    if (newContent != null && newContent.isNotEmpty) {
      return message.copyWith(content: newContent);
    }
    return message;
  }
}
