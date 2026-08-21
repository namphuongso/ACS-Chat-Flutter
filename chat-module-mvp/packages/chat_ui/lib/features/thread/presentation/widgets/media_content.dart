import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'video_message_content.dart';

class MediaContent extends StatelessWidget {
  const MediaContent({
    super.key,
    required this.metadata,
    required this.textColor,
  });

  final Map<String, dynamic> metadata;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final type = metadata['type']?.toString().toLowerCase();
    final images = metadata['images'] as List<dynamic>?;

    if (images != null && images.isNotEmpty) {
      final urls = images.map((e) => e.toString()).toList();
      return _buildImageGrid(context, urls);
    }

    if (type == 'image') {
      final url = metadata['url']?.toString() ?? '';
      final files = metadata['files'] as List<dynamic>?;
      if (files != null && files.isNotEmpty) {
        final urls = files
            .map((item) => (item is Map) ? (item['url']?.toString() ?? '') : '')
            .where((u) => u.isNotEmpty)
            .toList();
        if (urls.isNotEmpty) {
          return _buildImageGrid(context, urls);
        }
      }
      if (url.isNotEmpty) {
        return _buildSingleImage(context, url);
      }
    }

    if (type == 'video') {
      final url = metadata['url']?.toString() ?? '';
      final fileName = metadata['fileName']?.toString() ?? 'video.mp4';
      if (url.isNotEmpty) {
        return VideoMessageContent(
          url: url,
          fileName: fileName,
          textColor: textColor,
        );
      }
    }

    if (type == 'file') {
      final url = metadata['url']?.toString() ?? '';
      final fileName = metadata['fileName']?.toString() ?? 'Tệp tin';
      final fileSizeStr = metadata['fileSize']?.toString();
      final sizeBytes = int.tryParse(fileSizeStr ?? '') ?? 0;
      final isLargeFile = sizeBytes > 5 * 1024 * 1024;

      return Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: textColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getFileIcon(fileName), color: textColor),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sizeBytes > 0)
                    Text(
                      _formatFileSize(sizeBytes),
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                isLargeFile ? Icons.open_in_new : Icons.file_download,
                color: textColor,
              ),
              onPressed: () => _handleFileAction(context, url, sizeBytes),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  void _handleFileAction(BuildContext context, String url, int sizeBytes) {
    final isLargeFile = sizeBytes > 5 * 1024 * 1024;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isLargeFile
                    ? 'Dung lượng tệp > 5MB (${_formatFileSize(sizeBytes)}).'
                    : 'Dung lượng tệp: ${_formatFileSize(sizeBytes)}',
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.open_in_new, color: Colors.blue),
                title: const Text('Mở bằng ứng dụng thứ 3'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openFileUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _openFileUrl(String url, {required LaunchMode mode}) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: mode);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
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
            errorBuilder: (_, __, ___) => Container(
              width: 200,
              height: 140,
              color: Colors.grey.shade300,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid(BuildContext context, List<String> urls) {
    if (urls.length == 1) return _buildSingleImage(context, urls.first);
    return Container(
      width: 220,
      margin: const EdgeInsets.only(bottom: 6),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: urls.length.clamp(1, 4),
        itemBuilder: (ctx, i) {
          final url = urls[i];
          final isMore = urls.length > 4 && i == 3;
          final extraCount = urls.length - 4;
          return GestureDetector(
            onTap: () => _showImagePreviewDialog(
              context,
              imageUrls: urls,
              initialIndex: i,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                  if (isMore)
                    Container(
                      color: Colors.black54,
                      alignment: Alignment.center,
                      child: Text(
                        '+$extraCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static void _showImagePreviewDialog(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    if (imageUrls.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              PageView.builder(
                itemCount: imageUrls.length,
                controller: PageController(initialPage: initialIndex),
                itemBuilder: (context, index) => InteractiveViewer(
                  child: Image.network(
                    imageUrls[index],
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
