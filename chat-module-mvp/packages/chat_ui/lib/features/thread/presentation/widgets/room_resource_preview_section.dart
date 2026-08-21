import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../providers/thread_providers.dart';
import '../screens/room_resources_category_screen.dart';
import 'chat_video_player_dialog.dart';
import 'video_resource_thumbnail.dart';

class RoomResourcePreviewSection extends ConsumerWidget {
  const RoomResourcePreviewSection({
    super.key,
    required this.roomId,
    this.extraRows = const [],
  });

  final String roomId;
  final List<Widget> extraRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiConfig = ref.watch(chatUiConfigProvider);
    final surfaceColor = uiConfig.surfaceColor ?? Colors.white;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: surfaceColor,
        child: Column(
          children: [
            _ResourceGroupCard(
              roomId: roomId,
              category: RoomResourceCategory.media,
              title: 'Ảnh & video',
              icon: Icons.photo_library_outlined,
            ),
            const Divider(height: 1, indent: 16, color: Color(0xFFF2F4F7)),
            _ResourceGroupCard(
              roomId: roomId,
              category: RoomResourceCategory.file,
              title: 'Tệp đính kèm',
              icon: Icons.insert_drive_file_outlined,
            ),
            const Divider(height: 1, indent: 16, color: Color(0xFFF2F4F7)),
            _ResourceGroupCard(
              roomId: roomId,
              category: RoomResourceCategory.link,
              title: 'Liên kết chia sẻ',
              icon: Icons.link_rounded,
            ),
            for (final row in extraRows) ...[
              const Divider(height: 1, indent: 16, color: Color(0xFFF2F4F7)),
              row,
            ],
          ],
        ),
      ),
    );
  }
}

class _ResourceGroupCard extends ConsumerWidget {
  const _ResourceGroupCard({
    required this.roomId,
    required this.category,
    required this.title,
    required this.icon,
  });

  final String roomId;
  final RoomResourceCategory category;
  final String title;
  final IconData icon;

  void _openFullCategory(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RoomResourcesCategoryScreen(
          roomId: roomId,
          initialCategory: category,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(chatUiConfigProvider);
    final iconColor = config.actionIconColor ?? Colors.blueGrey;
    final asyncResult = ref.watch(
      roomResourcePreviewProvider((roomId: roomId, category: category)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row - chuẩn icon size 28 & fontSize 16 đồng nhất với các thẻ như Bình chọn, Tin nhắn ghim
        InkWell(
          onTap: () => _openFullCategory(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16, 
                        ),
                      ),
                      asyncResult.maybeWhen(
                        data: (res) => res.totalCount > 0
                            ? Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text(
                                  '(${res.totalCount})',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: config.secondaryTextColor ??
                                        Colors.grey.shade600,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Xem tất cả',
                  style: TextStyle(
                    fontSize: 13,
                    color: config.secondaryTextColor ?? Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right, color: iconColor, size: 20),
              ],
            ),
          ),
        ),

        // Body Content
        asyncResult.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (result) {
            if (result.items.isEmpty) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (category == RoomResourceCategory.media)
                    _MediaPreviewRow(items: result.items)
                  else if (category == RoomResourceCategory.file)
                    _FilePreviewList(items: result.items)
                  else
                    _LinkPreviewList(items: result.items),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MediaPreviewRow extends StatelessWidget {
  const _MediaPreviewRow({required this.items});

  final List<MessageResource> items;

  void _openMedia(BuildContext context, MessageResource item) {
    final url = item.mediaUrl ?? item.thumbUrl;
    if (url == null || url.isEmpty) return;

    if (item.resourceType == MessageResourceType.video) {
      ChatVideoPlayerDialog.show(context, url: url, title: item.message);
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isImageFileUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final lower = url.trim().toLowerCase();
    return !lower.endsWith('.mov') &&
        !lower.endsWith('.mp4') &&
        !lower.endsWith('.m4v') &&
        !lower.endsWith('.avi') &&
        !lower.endsWith('.mkv');
  }

  Widget _buildItemThumbnail(MessageResource item) {
    final isVideo = item.resourceType == MessageResourceType.video;
    final videoUrl = item.mediaUrl ?? item.thumbUrl ?? '';

    if (isVideo) {
      if (_isImageFileUrl(item.thumbUrl)) {
        return Image.network(
          item.thumbUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => VideoResourceThumbnail(videoUrl: videoUrl),
        );
      }
      return VideoResourceThumbnail(videoUrl: videoUrl);
    }

    final thumb = isNetworkAvatar(item.thumbUrl)
        ? item.thumbUrl!
        : (isNetworkAvatar(item.mediaUrl) ? item.mediaUrl! : '');

    if (thumb.isNotEmpty) {
      return Image.network(
        thumb,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.image, color: Colors.grey),
        ),
      );
    }

    return Container(
      color: Colors.grey.shade200,
      child: const Icon(Icons.image, color: Colors.grey),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Row(
        children: items.take(3).map((item) {
          final isVideo = item.resourceType == MessageResourceType.video;

          return Expanded(
            child: GestureDetector(
              onTap: () => _openMedia(context, item),
              child: Container(
                height: 84,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEAECF0)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildItemThumbnail(item),
                      if (isVideo)
                        Container(
                          color: Colors.black26,
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FilePreviewList extends StatelessWidget {
  const _FilePreviewList({required this.items});

  final List<MessageResource> items;

  Future<void> _openFile(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.take(3).map((item) {
        final url = item.attachmentUrl ?? item.thumbUrl ?? '';

        return ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.insert_drive_file_outlined,
              color: Color(0xFF475467),
              size: 20,
            ),
          ),
          title: Text(
            item.message.isNotEmpty ? item.message : 'Tệp đính kèm',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: item.creator.isNotEmpty
              ? Text(
                  'Bởi ${item.creator}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                )
              : null,
          trailing:
              const Icon(Icons.download_rounded, size: 18, color: Colors.grey),
          onTap: url.isNotEmpty ? () => _openFile(url) : null,
        );
      }).toList(),
    );
  }
}

class _LinkPreviewList extends StatelessWidget {
  const _LinkPreviewList({required this.items});

  final List<MessageResource> items;

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _extractDomain(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      return uri.host;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.take(3).map((item) {
        final rawUrl = item.linkUrl ?? item.message;
        final title = item.linkTitle != null && item.linkTitle!.isNotEmpty
            ? item.linkTitle!
            : item.message;
        final source = item.linkSource != null && item.linkSource!.isNotEmpty
            ? item.linkSource!
            : _extractDomain(rawUrl);
        return ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.link_rounded,
              color: Color(0xFF475467),
              size: 20,
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            source.isNotEmpty ? '$source • $rawUrl' : rawUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          trailing: const Icon(Icons.open_in_new_rounded,
              size: 16, color: Colors.grey),
          onTap: rawUrl.isNotEmpty ? () => _openLink(rawUrl) : null,
        );
      }).toList(),
    );
  }
}
