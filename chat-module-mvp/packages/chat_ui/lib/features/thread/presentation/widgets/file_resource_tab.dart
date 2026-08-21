import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/thread_providers.dart';

class FileResourceTab extends ConsumerStatefulWidget {
  const FileResourceTab({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<FileResourceTab> createState() => _FileResourceTabState();
}

class _FileResourceTabState extends ConsumerState<FileResourceTab> {
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
        resourceType: MessageResourceType.file,
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

  Future<void> _openFile(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
            const Text('Không thể tải danh sách tệp'),
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
            Icon(Icons.folder_open_outlined, color: Colors.grey, size: 54),
            SizedBox(height: 12),
            Text(
              'Chưa có tệp đính kèm nào',
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
        final url = item.attachmentUrl ?? item.thumbUrl ?? '';

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEAECF0)),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.insert_drive_file_outlined,
                    color: Color(0xFF475467),
                    size: 22,
                  ),
                ),
                title: Text(
                  item.message.isNotEmpty ? item.message : 'Tệp đính kèm',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Bởi ${item.creator} • ${_formatDate(item.createdDate)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
                trailing: const Icon(Icons.download_rounded,
                    color: Colors.grey, size: 18),
                onTap: url.isNotEmpty ? () => _openFile(url) : null,
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
