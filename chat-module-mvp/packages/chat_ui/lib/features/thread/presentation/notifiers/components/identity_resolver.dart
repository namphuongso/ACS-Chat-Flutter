import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../conversation_list/presentation/providers/conversation_providers.dart';

/// Xử lý ánh xạ danh tính ACS User ID, kiểm tra tin nhắn của bản thân (isMe),
/// và lấy tên hiển thị của thành viên.
class IdentityResolver {
  const IdentityResolver({
    required this.currentUserId,
    required this.ref,
  });

  final String currentUserId;
  final Ref ref;

  bool isMe(String senderId, String? myAcsUserId) {
    if (senderId.isEmpty) return false;
    if (AcsUserUtils.isSameAcsUser(senderId, currentUserId)) return true;
    if (myAcsUserId != null && myAcsUserId.isNotEmpty) {
      if (AcsUserUtils.isSameAcsUser(senderId, myAcsUserId)) return true;
    }
    return false;
  }

  String getDisplayName(String roomId, String userId, [String fallback = '']) {
    if (userId.isEmpty) return fallback;
    final conversations = ref.read(conversationListProvider);
    final conv = conversations.where((c) => c.id == roomId).firstOrNull;
    if (conv != null) {
      final p = conv.participants
          .where((member) => AcsUserUtils.isSameAcsUser(member.id, userId))
          .firstOrNull;
      if (p != null && p.displayName.isNotEmpty) {
        return p.displayName;
      }
    }
    return fallback;
  }
}
