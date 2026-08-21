import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/thread_providers.dart';

class LinkResourceTab extends ConsumerStatefulWidget {
  const LinkResourceTab({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<LinkResourceTab> createState() => _LinkResourceTabState();
}

class _LinkResourceTabState extends ConsumerState<LinkResourceTab> {
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
      final result = await useCase(
        roomId: widget.roomId,
        resourceType: MessageResourceType.link,
        pageIndex: page,
        pageSize: 20,
      );

      if (!mounted) return;
      setState(() {
        if (page == 1) {
          _items.clear();
        }
        _items.addAll(result.items);
        _pageIndex = page;
        _hasMore = result.hasMore;
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
            const Text('Không thể tải danh sách liên kết'),
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
            Icon(Icons.link_off_rounded, color: Colors.grey, size: 54),
            SizedBox(height: 12),
            Text(
              'Chưa có link liên kết nào',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: _items.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final item = _items[index];
        final rawUrl = item.linkUrl ?? item.message;
        final title = item.linkTitle != null && item.linkTitle!.isNotEmpty
            ? item.linkTitle!
            : item.message;
        final source = item.linkSource != null && item.linkSource!.isNotEmpty
            ? item.linkSource!
            : _extractDomain(rawUrl);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEAECF0)),
          ),
          child: InkWell(
            onTap: rawUrl.isNotEmpty ? () => _openLink(rawUrl) : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F4F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.link_rounded,
                      color: Color(0xFF475467),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1D2939),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          source.isNotEmpty ? '$source • $rawUrl' : rawUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.open_in_new_rounded,
                      size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
