import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../../../../core/widgets/rich_message_text.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.senderAvatarUrl,
    this.showSenderAvatar = true,
    this.onLongPress,
    this.onLongPressStart,
    this.reactionSummary,
    this.onReactionTap,
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
  final MessageReactionSummary? reactionSummary;
  final VoidCallback? onReactionTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final config = ref.watch(chatUiConfigProvider);
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
            if (message.isDeleted)
              Text(
                '(tin nhắn đã bị xoá)',
                style: TextStyle(
                  color: textColor,
                  fontStyle: FontStyle.italic,
                ),
              )
            else ...[
              if (message.metadata != null)
                _MediaContent(metadata: message.metadata!, textColor: textColor),
              if (message.content.trim().isNotEmpty &&
                  message.content.trim() != '[Hình ảnh]' &&
                  message.content.trim() != 'Hình ảnh' &&
                  message.content.trim() != '[Tệp tin]' &&
                  message.content.trim() != 'Tệp tin')
                RichMessageText(
                  content: message.content,
                  style: TextStyle(color: textColor),
                ),
            ],
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
}

class _MediaContent extends StatelessWidget {
  const _MediaContent({
    required this.metadata,
    required this.textColor,
  });

  final Map<String, dynamic> metadata;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final type = metadata['type']?.toString().toLowerCase();

    if (type == 'image') {
      final files = metadata['files'];
      if (files is List && files.isNotEmpty) {
        final fileList = files.whereType<Map>().toList();
        return _buildImageGrid(context, fileList);
      }
      final singleUrl = metadata['url']?.toString();
      if (singleUrl != null && singleUrl.isNotEmpty) {
        return _buildSingleImage(context, singleUrl);
      }
    }

    if (type == 'video') {
      final fileName = metadata['fileName']?.toString() ?? 'Video';
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_circle_fill, color: Colors.white, size: 36),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                fileName,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final filesRaw = metadata['files'] ?? metadata['Files'];
    final fileList = (filesRaw is List)
        ? filesRaw.whereType<Map>().toList()
        : <Map>[];

    if (type == 'file' || (type == null && fileList.isNotEmpty)) {
      if (fileList.isNotEmpty) {
        return _buildFileList(context, fileList);
      }
      final singleFile = [
        {
          'fileName': metadata['fileName']?.toString() ?? 'Tệp đính kèm',
          'url': metadata['url']?.toString() ?? '',
          'fileSize': metadata['fileSize']?.toString() ?? '0',
        }
      ];
      return _buildFileList(context, singleFile);
    }

    return const SizedBox.shrink();
  }

  Widget _buildFileList(BuildContext context, List<Map> fileList) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fileList.map((item) {
        final fileName = item['fileName']?.toString() ?? 'Tệp đính kèm';
        final url = item['url']?.toString() ?? '';
        final sizeBytes = int.tryParse(item['fileSize']?.toString() ?? '0') ?? 0;
        final sizeText = _formatFileSize(sizeBytes);

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_getFileIcon(fileName), color: textColor, size: 28),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sizeText.isNotEmpty)
                      Text(
                        sizeText,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (url.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(Icons.download_for_offline_outlined, color: textColor, size: 22),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'txt':
        return Icons.article;
      default:
        return Icons.insert_drive_file;
    }
  }

  Widget _buildSingleImage(BuildContext context, String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () => _showImagePreviewDialog(
          context,
          imageUrls: [url],
          initialIndex: 0,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            width: 200,
            height: 180,
            errorBuilder: (_, __, ___) => Container(
              width: 200,
              height: 120,
              color: Colors.grey.shade300,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid(BuildContext context, List<Map> fileList) {
    final allUrls = fileList
        .map((item) => item['url']?.toString() ?? '')
        .where((url) => url.isNotEmpty)
        .toList();

    final remainingCount = fileList.length - 4;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: fileList.take(4).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final url = item['url']?.toString() ?? '';
          final isLastTile = index == 3 && remainingCount > 0;

          return GestureDetector(
            onTap: () => _showImagePreviewDialog(
              context,
              imageUrls: allUrls,
              initialIndex: index,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    width: fileList.length == 1 ? 200 : 96,
                    height: fileList.length == 1 ? 180 : 96,
                    errorBuilder: (_, __, ___) => Container(
                      width: fileList.length == 1 ? 200 : 96,
                      height: fileList.length == 1 ? 180 : 96,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                  if (isLastTile)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: Text(
                          '+${remainingCount + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showImagePreviewDialog(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    if (imageUrls.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        final pageController = PageController(initialPage: initialIndex);
        int currentIndex = initialIndex;

        return StatefulBuilder(
          builder: (context, setState) {
            return Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: pageController,
                    itemCount: imageUrls.length,
                    onPageChanged: (index) {
                      setState(() => currentIndex = index);
                    },
                    itemBuilder: (context, index) {
                      return InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Center(
                          child: Image.network(
                            imageUrls[index],
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  size: 64,
                                  color: Colors.white54,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Không thể tải ảnh',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    right: 12,
                    child: IconButton(
                      icon:
                          const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  if (imageUrls.length > 1)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${currentIndex + 1} / ${imageUrls.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
