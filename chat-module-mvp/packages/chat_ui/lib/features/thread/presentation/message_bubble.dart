import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';

/// Bong bóng tin nhắn — 1 chiều (text). Group/reaction/reply chưa có
/// ở MVP, xem roadmap-tinh-nang-sau-mvp.md nhóm 3.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  final Message message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Align(
      // ValueKey theo message.id — giúp ListView.builder không rebuild
      // thừa (mục 6 kế hoạch gốc).
      key: ValueKey(message.id),
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.content, style: TextStyle(color: textColor)),
            const SizedBox(height: 4),
            _StatusIndicator(status: message.status, textColor: textColor),
          ],
        ),
      ),
    );
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
