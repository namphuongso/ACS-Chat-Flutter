import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';

import '../../../../core/chat_ui_config.dart';

class PinnedMessageRow extends StatelessWidget {
  const PinnedMessageRow({
    super.key,
    required this.pinnedMessage,
    required this.config,
    required this.actionIcon,
    required this.actionTooltip,
    required this.onTap,
    required this.onAction,
    this.actionColor,
  });

  final PinnedMessage pinnedMessage;
  final ChatUiConfig config;
  final IconData actionIcon;
  final String actionTooltip;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final Color? actionColor;

  @override
  Widget build(BuildContext context) {
    final secondaryColor = config.secondaryTextColor ?? Colors.grey.shade600;

    return Material(
      color: const Color(0xFFF7F8FA),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pinnedMessage.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pinnedMessage.creator.isEmpty
                          ? 'Tin nhắn đã ghim'
                          : 'Ghim bởi ${pinnedMessage.creator}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: secondaryColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: actionTooltip,
                onPressed: onAction,
                icon: Icon(actionIcon, size: 18),
                color: actionColor ?? secondaryColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
