import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../conversation_list/presentation/providers/conversation_providers.dart';

/// Lắng nghe và xử lý các sự kiện realtime WebSocket từ backend
/// (tin nhắn mới, ghim, reaction, cập nhật nhóm, thành viên bị xóa).
class RealtimeMessageHandler {
  const RealtimeMessageHandler({
    required this.ref,
  });

  final Ref ref;

  void handleMemberEventSignal({
    required Message message,
    required String currentUserId,
    required String? myAcsUserId,
  }) {
    final metadata = message.metadata;
    if (metadata == null) return;
    final eventType = metadata['eventType']?.toString();
    final payload = (metadata['payload'] is Map)
        ? (metadata['payload'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    if (eventType == 'MemberRemoved') {
      final removedUserId =
          (metadata['removedUserId'] ?? payload['removedUserId'] ?? '')
              .toString();

      final isSelfRemoved = (removedUserId.isNotEmpty &&
          (AcsUserUtils.isSameAcsUser(removedUserId, currentUserId) ||
              (myAcsUserId != null &&
                  AcsUserUtils.isSameAcsUser(removedUserId, myAcsUserId))));
      if (isSelfRemoved) {
        metadata['isSelf'] = true;
      }
    }
  }

  void handleRoomUpdatedSignal({
    required String roomId,
    required Message message,
  }) {
    final metadata = message.metadata;
    if (metadata == null) return;
    final eventType = metadata['eventType']?.toString();
    if (eventType != 'RoomUpdated') return;

    final payload = (metadata['payload'] is Map)
        ? (metadata['payload'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final newRoomName = payload['roomName']?.toString() ?? metadata['roomName']?.toString();
    final newAvatarUrl = payload['roomAvatar']?.toString() ?? metadata['roomAvatar']?.toString();

    if ((newRoomName != null && newRoomName.isNotEmpty) ||
        (newAvatarUrl != null && newAvatarUrl.isNotEmpty)) {
      ChatLogger.log(
        '[RealtimeMessageHandler] Updating room details for $roomId: name=$newRoomName, avatar=$newAvatarUrl',
      );
      ref.read(conversationListProvider.notifier).updateRoomDetails(
            roomId,
            roomName: newRoomName,
            avatarUrl: newAvatarUrl,
          );
    }
  }
}
