import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../../../../core/widgets/rich_message_text.dart';
import 'link_preview_card.dart';
import 'media_content.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.senderAvatarUrl,
    this.showSenderAvatar = true,
    this.isHighlighted = false,
    this.onLongPress,
    this.onLongPressStart,
    this.reactionSummary,
    this.onReactionTap,
  });

  final Message message;
  final bool isMe;
  final bool isHighlighted;
  final String? senderAvatarUrl;
  final bool showSenderAvatar;
  final VoidCallback? onLongPress;
  final GestureLongPressStartCallback? onLongPressStart;
  final MessageReactionSummary? reactionSummary;
  final VoidCallback? onReactionTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final config = ref.watch(chatUiConfigProvider);
    if (message.type == MessageType.memberJoinedUpdate ||
        message.type == MessageType.memberLeftUpdate ||
        message.type == MessageType.memberRemovedUpdate ||
        message.type == MessageType.roomUpdatedUpdate ||
        message.type == MessageType.roomPinnedUpdate ||
        message.type == MessageType.roomUnpinnedUpdate ||
        message.type == MessageType.reactionUpdate ||
        message.type == MessageType.messagePinUpdate) {
      return const SizedBox.shrink();
    }
    if (message.content.trim().isEmpty &&
        (message.metadata == null || message.metadata!.isEmpty) &&
        !message.isDeleted) {
      return const SizedBox.shrink();
    }
    if (message.type == MessageType.system) {
      final baseStyle = TextStyle(
        color: theme.colorScheme.onSurfaceVariant,
        fontSize: 12,
        height: 1.35,
      );
      return Padding(
        key: ValueKey(message.id),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
        child: Center(
          child: _buildSystemMessageText(message.content, baseStyle),
        ),
      );
    }
    final bubbleColor = isMe
        ? (config.sentBubbleColor ?? theme.colorScheme.primary)
        : (config.receivedBubbleColor ??
            theme.colorScheme.surfaceContainerHighest);
    final textColor = isMe
        ? (config.sentTextColor ?? theme.colorScheme.onPrimary)
        : (config.receivedTextColor ?? theme.colorScheme.onSurface);

    final mediaType = message.metadata?['type']?.toString().toLowerCase();
    final hasImages =
        (message.metadata?['images'] as List?)?.isNotEmpty == true;

    final files = message.metadata?['files'] as List<dynamic>?;
    Map<String, dynamic>? firstFileMap;
    if (files != null && files.isNotEmpty && files.first is Map) {
      firstFileMap = Map<String, dynamic>.from(files.first as Map);
    }
    final fileSizeRaw = message.metadata?['fileSize'] ??
        message.metadata?['size'] ??
        message.metadata?['length'] ??
        message.metadata?['bytes'] ??
        firstFileMap?['size'] ??
        firstFileMap?['fileSize'] ??
        firstFileMap?['length'] ??
        firstFileMap?['bytes'];
    final sizeBytes = (fileSizeRaw is int)
        ? fileSizeRaw
        : (int.tryParse(fileSizeRaw?.toString() ?? '') ?? 0);
    final isOver100MB = sizeBytes > 100 * 1024 * 1024;

    final isMediaMetadata = (mediaType == 'image' ||
        mediaType == 'video' ||
        hasImages) && !isOver100MB;

    final rawContent = message.content.trim();
    final isFallbackMediaText = rawContent == '[Hình ảnh]' ||
        rawContent == '[Video]' ||
        rawContent == '[Tệp tin]' ||
        RegExp(r'^\[\d+\s+hình ảnh\]$').hasMatch(rawContent);

    final hasUserText = rawContent.isNotEmpty && !isFallbackMediaText;

    final isMediaOnly = message.metadata != null &&
        isMediaMetadata &&
        !hasUserText &&
        !message.isDeleted;

    final timeColor = isMediaOnly
        ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
        : textColor.withValues(alpha: 0.6);

    final bubbleContent = GestureDetector(
      onLongPress: message.isDeleted ? null : onLongPress,
      onLongPressStart: message.isDeleted ? null : onLongPressStart,
      child: Container(
        margin: EdgeInsets.only(
          left: isMe ? 12 : 0,
          right: isMe ? 12 : 12,
          top: 4,
          bottom: reactionSummary != null && reactionSummary!.totalReactions > 0
              ? 16
              : 4,
        ),
        padding: isMediaOnly
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isMediaOnly ? Colors.transparent : bubbleColor,
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
                    color: timeColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Đã ghim',
                    style: TextStyle(
                      fontSize: 10,
                      color: timeColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            if (message.isDeleted)
              Text(
                '(Tin nhắn đã bị xoá)',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.85),
                  fontStyle: FontStyle.italic,
                ),
              )
            else ...[
              if (message.metadata != null)
                MediaContent(metadata: message.metadata!, textColor: textColor),
              if (_hasLinkInContent(message.content, message.metadata))
                LinkPreviewCard(
                  url: _extractFirstUrl(message.content)!,
                  textColor: textColor,
                ),
              if (hasUserText)
                RichMessageText(
                  content: message.content,
                  style: TextStyle(color: textColor),
                ),
            ],
            const SizedBox(height: 2),
            Text(
              _formatTime(message.createdAt),
              style: TextStyle(
                fontSize: 11,
                color: timeColor,
              ),
            ),
          ],
        ),
      ),
    );

    final summary = reactionSummary;
    String? badgeIcon;
    if (summary != null) {
      if (summary.myReactionIconUrl != null &&
          summary.myReactionIconUrl!.isNotEmpty) {
        badgeIcon = summary.myReactionIconUrl;
      } else if (summary.previewIconUrl != null &&
          summary.previewIconUrl!.isNotEmpty) {
        badgeIcon = summary.previewIconUrl;
      }
    }

    final bubble = Stack(
      clipBehavior: Clip.none,
      children: [
        bubbleContent,
        if (summary != null && summary.totalReactions > 0 && badgeIcon != null)
          Positioned(
            right: isMe ? 18 : 6,
            bottom: 3,
            child: InkWell(
              onTap: onReactionTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 26,
                constraints: const BoxConstraints(minWidth: 30),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: config.surfaceColor ?? Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.network(
                      badgeIcon,
                      width: 17,
                      height: 17,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.emoji_emotions,
                        size: 17,
                      ),
                    ),
                    if (summary.totalReactions > 1) ...[
                      const SizedBox(width: 3),
                      Text(
                        '${summary.totalReactions}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    final mainWidget = isMe
        ? Align(
            key: ValueKey(message.id),
            alignment: Alignment.centerRight,
            child: bubble,
          )
        : Align(
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
                    backgroundColor: const Color(0xFFF0F2F5),
                    backgroundImage: isNetworkAvatar(senderAvatarUrl)
                        ? NetworkImage(senderAvatarUrl!)
                        : null,
                    child: isNetworkAvatar(senderAvatarUrl)
                        ? null
                        : Text(_senderInitial,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                            )),
                  )
                else
                  const SizedBox(width: 32, height: 32),
                const SizedBox(width: 8),
                Flexible(child: bubble),
              ],
            ),
          );

    if (isHighlighted) {
      return Container(
        color: config.highlightBackgroundColor ?? const Color(0xFFEAECF0),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: mainWidget,
      );
    }

    return mainWidget;
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

  Widget _buildSystemMessageText(String text, TextStyle baseStyle) {
    final parts = text.split('**');
    if (parts.length <= 1) {
      return Text(
        text,
        textAlign: TextAlign.center,
        style: baseStyle,
      );
    }

    final spans = <TextSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      final isBold = i.isOdd;
      spans.add(
        TextSpan(
          text: parts[i],
          style: isBold
              ? baseStyle.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                )
              : baseStyle,
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
    );
  }

  static final _urlRegex = RegExp(r'(https?://[^\s<]+)');

  static String? _extractFirstUrl(String content) {
    final match = _urlRegex.firstMatch(content);
    return match?.group(0);
  }

  static bool _hasLinkInContent(
      String content, Map<String, dynamic>? metadata) {
    if (metadata != null && metadata['type'] == 'link') return false;
    return _extractFirstUrl(content) != null;
  }
}
