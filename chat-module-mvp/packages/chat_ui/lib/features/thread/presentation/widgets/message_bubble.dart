import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';
 
class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.senderAvatarUrl,
    this.showSenderAvatar = true,
    this.onLongPress,
    this.onLongPressStart,
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

  /// Vị trí long-press — dùng để neo context menu mở ngay vị trí ngón tay.
  final GestureLongPressStartCallback? onLongPressStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final config = ref.watch(chatUiConfigProvider);
    final bubbleColor = isMe
        ? (config.sentBubbleColor ?? theme.colorScheme.primary)
        : (config.receivedBubbleColor ??
            theme.colorScheme.surfaceContainerHighest);
    final textColor = isMe
        ? (config.sentTextColor ?? theme.colorScheme.onPrimary)
        : (config.receivedTextColor ?? theme.colorScheme.onSurface);

    final bubble = GestureDetector(
      onLongPress: message.isDeleted ? null : onLongPress,
      onLongPressStart: message.isDeleted ? null : onLongPressStart,
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
                    color: textColor.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Đã ghim',
                    style: TextStyle(
                      fontSize: 10,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(
              message.isDeleted ? '(tin nhắn đã bị xoá)' : message.content,
              style: TextStyle(
                color: textColor,
                fontStyle: message.isDeleted ? FontStyle.italic : null,
              ),
            ),
            const SizedBox(height: 4),
            if (isMe)
              Text(
                _formatTime(message.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: textColor.withValues(alpha: 0.6),
                ),
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
