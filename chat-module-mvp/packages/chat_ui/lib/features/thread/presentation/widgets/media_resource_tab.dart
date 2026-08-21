import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/avatar_utils.dart';
import '../providers/thread_providers.dart';
import 'chat_video_player_dialog.dart';
import 'video_resource_thumbnail.dart';

class MediaResourceTab extends ConsumerStatefulWidget {
  const MediaResourceTab({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<MediaResourceTab> createState() => _MediaResourceTabState();
}

class _MediaResourceTabState extends ConsumerState<MediaResourceTab> {
  final _scrollController = ScrollController();
  final List<MessageResource> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _pageIndex = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPage(1);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 200 &&
        !_isLoadingMore &&
        _hasMore &&
        !_isLoading) {
      _fetchPage(_pageIndex + 1);
    }
  }

  Future<void> _fetchPage(int page) async {
    if (page == 1) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final useCase = ref.read(getMessageResourcesUseCaseProvider);
      final imageResult = await useCase(
        roomId: widget.roomId,
        resourceType: MessageResourceType.image,
        pageIndex: page,
        pageSize: 20,
      );
      final videoResult = await useCase(
        roomId: widget.roomId,
        resourceType: MessageResourceType.video,
        pageIndex: page,
        pageSize: 20,
      );

      final combined = <MessageResource>[
        ...imageResult.items,
        ...videoResult.items
      ]..sort((a, b) => b.createdDate.compareTo(a.createdDate));

      final hasMore = imageResult.hasMore || videoResult.hasMore;

      if (!mounted) return;
      setState(() {
        if (page == 1) {
          _items.clear();
        }
        _items.addAll(combined);
        _pageIndex = page;
        _hasMore = hasMore;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _openMedia(MessageResource resource) {
    final url = resource.mediaUrl ?? resource.thumbUrl;
    if (url == null || url.isEmpty) return;

    if (resource.resourceType == MessageResourceType.video) {
      ChatVideoPlayerDialog.show(context, url: url, title: resource.message);
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
          errorBuilder: (_, __, ___) =>
              VideoResourceThumbnail(videoUrl: videoUrl),
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.grey, size: 48),
            const SizedBox(height: 12),
            const Text('Không thể tải danh sách ảnh/video'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _fetchPage(1),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, color: Colors.grey, size: 54),
            SizedBox(height: 12),
            Text(
              'Chưa có ảnh hoặc video nào được gửi',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _items.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return const Center(child: CircularProgressIndicator());
        }

        final item = _items[index];
        final isVideo = item.resourceType == MessageResourceType.video;

        return GestureDetector(
          onTap: () => _openMedia(item),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEAECF0)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
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
                          size: 36,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
