import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';

import '../../../../core/chat_ui_config.dart';

class PinnedMessageBanner extends StatelessWidget {
  const PinnedMessageBanner({
    super.key,
    required this.pinnedMessage,
    required this.totalPinnedCount,
    required this.currentIndex,
    required this.onTap,
    required this.onOpenList,
    required this.config,
  });

  final PinnedMessage pinnedMessage;
  final int totalPinnedCount;
  final int currentIndex;
  final VoidCallback onTap;
  final VoidCallback onOpenList;
  final ChatUiConfig config;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(10.0),
        decoration: BoxDecoration(
          color: config.pinnedMessageBackgroundColor ?? Colors.orange.shade50,
          borderRadius: BorderRadius.circular(6.0),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.push_pin,
              size: 16,
              color: config.pinnedMessageIconColor ?? Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                totalPinnedCount > 1
                    ? 'Ghim [${currentIndex + 1}/$totalPinnedCount]: ${pinnedMessage.content}'
                    : 'Tin nhắn được ghim: ${pinnedMessage.content}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: config.pinnedMessageTextColor ?? Colors.orange.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (totalPinnedCount > 0) ...[
              IconButton(
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.list,
                  size: 20,
                  color: config.pinnedMessageIconColor ?? Colors.orange,
                ),
                onPressed: onOpenList,
              ),
              const SizedBox(width: 8),
            ],
            Icon(
              Icons.chevron_right,
              size: 20,
              color: config.pinnedMessageIconColor ?? Colors.orange,
            ),
          ],
        ),
      ),
    );
  }
}
