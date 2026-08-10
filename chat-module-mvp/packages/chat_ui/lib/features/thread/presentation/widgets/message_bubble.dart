import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/avatar_utils.dart';

/// Bong bóng tin nhắn — 1 chiều (text). Group/reaction/reply chưa có
/// ở MVP, xem roadmap-tinh-nang-sau-mvp.md nhóm 3.
///
/// Tin của người khác: hiển thị ô avatar nhỏ phía trên trái + thời gian gửi.
/// Tin của mình: không avatar, có thời gian + icon trạng thái gửi.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.senderAvatarUrl,
    this.showSenderAvatar = true,
    this.onLongPress,
  });

  final Message message;
  final bool isMe;

  /// URL avatar người gửi (dùng cho tin của người khác). Nếu rỗng sẽ
  /// fallback hiển thị chữ cái đầu của tên người gửi.
  final String? senderAvatarUrl;

  /// Có hiển thị ô avatar của người gửi hay không. Chuỗi tin liên tiếp
  /// cùng 1 người gửi chỉ hiện avatar ở tin đầu tiên, các tin sau truyền
  /// `false` để chừa đúng vùng trống giữ nguyên thẳng hàng.
  final bool showSenderAvatar;

  /// Gọi khi long-press tin nhắn (mở menu ghim/actions).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor =
        isMe ? const Color(0xFF0084FF) : const Color(0xFFE4E6EB);
    final textColor =
        isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: EdgeInsets.only(
          left: isMe ? 12 : 0,
          right: isMe ? 12 : 12,
          top: 4,
          bottom: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.pin) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.push_pin,
                    size: 11,
                    color: isMe ? Colors.white70 : Colors.black45,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Đã ghim',
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe ? Colors.white70 : Colors.black45,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(message.content, style: TextStyle(color: textColor)),
            const SizedBox(height: 4),
            if (isMe)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _StatusIndicator(
                      status: message.status, textColor: textColor),
                ],
              )
            else
              Text(
                _formatTime(message.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: textColor.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
      ),
    );

    if (isMe) {
      return Align(
        // ValueKey theo message.id — giúp ListView.builder không rebuild
        // thừa (mục 6 kế hoạch gốc).
        key: ValueKey(message.id),
        alignment: Alignment.centerRight,
        child: bubble,
      );
    }

    return Align(
      key: ValueKey(message.id),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 12),
          if (showSenderAvatar)
            CircleAvatar(
              radius: 16,
              backgroundImage: isNetworkAvatar(senderAvatarUrl)
                  ? NetworkImage(senderAvatarUrl!)
                  : null,
              child: isNetworkAvatar(senderAvatarUrl)
                  ? null
                  : Text(_senderInitial),
            )
          else
            // Giữ đúng kích thước ô avatar (32x32) để các tin liên tiếp
            // cùng người gửi vẫn thẳng hàng với tin có avatar.
            const SizedBox(width: 32, height: 32),
          const SizedBox(width: 8),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  String get _senderInitial {
    final name = message.senderDisplayName.trim();
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  static String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status, required this.textColor});

  final MessageDeliveryStatus status;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final IconData? icon = switch (status) {
      MessageDeliveryStatus.sending => Icons.access_time,
      MessageDeliveryStatus.sent => Icons.check,
      MessageDeliveryStatus.failed => Icons.error_outline,
    };
    if (icon == null) return const SizedBox.shrink();
    return Icon(icon, size: 12, color: textColor.withValues(alpha: 0.7));
  }
}
