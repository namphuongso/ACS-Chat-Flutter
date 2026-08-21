import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';

class RoomHeaderSection extends StatelessWidget {
  const RoomHeaderSection({
    super.key,
    required this.uiConfig,
    required this.isGroup,
    required this.isAdmin,
    required this.roomDetails,
    required this.members,
    required this.currentUserId,
    required this.onPickAvatar,
    required this.onEditName,
  });

  final ChatUiConfig uiConfig;
  final bool isGroup;
  final bool isAdmin;
  final Conversation? roomDetails;
  final List<ChatMember> members;
  final String currentUserId;
  final VoidCallback onPickAvatar;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    final otherMember = !isGroup
        ? members.where((member) => member.id != currentUserId).firstOrNull
        : null;
    final displayName = isGroup
        ? (roomDetails?.roomName.isNotEmpty == true
            ? roomDetails!.roomName
            : 'Nhóm chat')
        : (otherMember?.displayName.isNotEmpty == true
            ? otherMember!.displayName
            : (roomDetails?.roomName.isNotEmpty == true
                ? roomDetails!.roomName
                : 'Người dùng'));
    final avatarUrl = isGroup
        ? roomDetails?.avatarUrl
        : (isNetworkAvatar(otherMember?.avatarUrl)
            ? otherMember?.avatarUrl
            : roomDetails?.avatarUrl);
    final hasAvatar = isNetworkAvatar(avatarUrl);

    final surface = uiConfig.surfaceColor ?? Colors.white;
    final primary =
        uiConfig.primaryActionColor ?? Theme.of(context).colorScheme.primary;
    final secondary = uiConfig.secondaryTextColor ??
        Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      color: surface,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: const Color(0xFFF0F2F5),
                backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
                child: !hasAvatar
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 32,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              if (isGroup && isAdmin)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Material(
                    color: primary,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Đổi ảnh nhóm',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.camera_alt_outlined,
                          color: Colors.white, size: 16),
                      onPressed: onPickAvatar,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  displayName,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (isGroup && isAdmin)
                IconButton(
                  tooltip: 'Đổi tên nhóm',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.edit_outlined, color: primary, size: 20),
                  onPressed: onEditName,
                ),
            ],
          ),
          Text(
            isGroup
                ? 'Nhóm trò chuyện • ${members.length} thành viên'
                : 'Trò chuyện cá nhân',
            style: TextStyle(color: secondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
