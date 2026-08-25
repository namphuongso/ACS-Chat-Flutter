import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/chat_ui_config.dart';
import 'video_message_content.dart';

class MediaContent extends ConsumerWidget {
  const MediaContent({
    super.key,
    required this.metadata,
    required this.textColor,
  });

  final Map<String, dynamic> metadata;
  final Color textColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = metadata['type']?.toString().toLowerCase();
    final images = metadata['images'] as List<dynamic>?;

    final files = metadata['files'] as List<dynamic>?;
    Map<String, dynamic>? firstFileMap;
    if (files != null && files.isNotEmpty && files.first is Map) {
      firstFileMap = Map<String, dynamic>.from(files.first as Map);
    }

    final fileSizeRaw = metadata['fileSize'] ??
        metadata['size'] ??
        metadata['length'] ??
        metadata['bytes'] ??
        firstFileMap?['size'] ??
        firstFileMap?['fileSize'] ??
        firstFileMap?['length'] ??
        firstFileMap?['bytes'];

    final sizeBytes = (fileSizeRaw is int)
        ? fileSizeRaw
        : (int.tryParse(fileSizeRaw?.toString() ?? '') ?? 0);
    final isOver100MB = sizeBytes > 100 * 1024 * 1024;

    if (images != null && images.isNotEmpty && !isOver100MB) {
      final urls = images.map((e) => e.toString()).toList();
      return _buildImageGrid(context, urls);
    }

    if (type == 'image' && !isOver100MB) {
      final url = metadata['url']?.toString() ?? '';
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

    if (type == 'file' || isOver100MB) {
      final files = metadata['files'] as List<dynamic>?;
      if (files != null && files.isNotEmpty) {
        if (files.length > 1) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < files.length; i++) ...[
                if (i > 0) const SizedBox(height: 4),
                _buildSingleFileCard(
                  context,
                  ref,
                  (files[i] is Map)
                      ? Map<String, dynamic>.from(files[i] as Map)
                      : metadata,
                ),
              ],
            ],
          );
        }
        return _buildSingleFileCard(
          context,
          ref,
          (files.first is Map)
              ? Map<String, dynamic>.from(files.first as Map)
              : metadata,
        );
      }
      return _buildSingleFileCard(context, ref, metadata);
    }

    return const SizedBox.shrink();
  }

  Widget _buildSingleFileCard(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> fileData,
  ) {
    String url = fileData['url']?.toString() ?? '';
    String fileName = fileData['fileName']?.toString() ?? '';
    if (fileName.isEmpty && url.isNotEmpty) {
      try {
        final uri = Uri.parse(url);
        final lastSegment = uri.pathSegments.last;
        if (lastSegment.isNotEmpty) {
          fileName = Uri.decodeComponent(lastSegment);
        }
      } catch (_) {}
    }
    if (fileName.isEmpty) {
      fileName = 'Tệp tin';
    }

    final fileSizeRaw = fileData['fileSize'] ??
        fileData['size'] ??
        fileData['length'] ??
        fileData['bytes'];

    final sizeBytes = (fileSizeRaw is int)
        ? fileSizeRaw
        : (int.tryParse(fileSizeRaw?.toString() ?? '') ?? 0);
    final isLargeFile = sizeBytes > 5 * 1024 * 1024;

    return InkWell(
      onTap: () => _handleFileAction(context, ref, url, fileName, sizeBytes),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(top: 2, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            Icon(
              isLargeFile ? Icons.open_in_new : Icons.file_download,
              color: textColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _handleFileAction(BuildContext context, WidgetRef ref, String url,
      String fileName, int sizeBytes) {
    final isLargeFile = sizeBytes > 5 * 1024 * 1024;
    final config = ref.read(chatUiConfigProvider);
    if (config.onFileTap != null) {
      config.onFileTap!(
        context,
        fileName: fileName,
        url: url,
        sizeBytes: sizeBytes,
        isLargeFile: isLargeFile,
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sizeBytes > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        isLargeFile
                            ? 'Dung lượng tệp: ${_formatFileSize(sizeBytes)} (Không hỗ trợ xem trước)'
                            : 'Dung lượng tệp: ${_formatFileSize(sizeBytes)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isLargeFile
                              ? Colors.red.shade700
                              : const Color(0xFF64748B),
                          fontWeight:
                              isLargeFile ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 16),
              ListTile(
                enabled: !isLargeFile,
                leading: Icon(
                  Icons.remove_red_eye_outlined,
                  color: isLargeFile ? Colors.grey : const Color(0xFF0066FF),
                ),
                title: Text(
                  'Xem trước (Quick Look)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isLargeFile ? Colors.grey : Colors.black87,
                  ),
                ),
                subtitle: Text(
                  isLargeFile
                      ? 'Tệp trên 5MB không hỗ trợ xem trước'
                      : 'Xem trực tiếp nội dung tệp tin',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                onTap: isLargeFile
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _openFileUrl(url, mode: LaunchMode.inAppBrowserView);
                      },
              ),
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined,
                    color: Color(0xFF10B981)),
                title: const Text(
                  'Tải về thiết bị',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Mở trình duyệt ngoài/trình tải tệp hệ thống',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
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

  static Future<void> _openFileUrl(String url,
      {required LaunchMode mode}) async {
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
      padding: const EdgeInsets.only(bottom: 2),
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

  Widget _buildGridTile(
    BuildContext context,
    List<String> urls,
    int index, {
    bool isMore = false,
    int extraCount = 0,
  }) {
    final url = urls[index];
    return AspectRatio(
      aspectRatio: 1.0,
      child: GestureDetector(
        onTap: () => _showImagePreviewDialog(
          context,
          imageUrls: urls,
          initialIndex: index,
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
      ),
    );
  }

  Widget _buildImageGrid(BuildContext context, List<String> urls) {
    if (urls.isEmpty) return const SizedBox.shrink();
    if (urls.length == 1) return _buildSingleImage(context, urls.first);

    final displayCount = urls.length.clamp(2, 4);
    final isMore = urls.length > 4;
    final extraCount = urls.length - 4;

    Widget buildRow(int startIndex, int count) {
      return Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _buildGridTile(
                context,
                urls,
                startIndex + i,
                isMore: isMore && (startIndex + i == 3),
                extraCount: extraCount,
              ),
            ),
          ],
          if (count < 2) ...[
            const SizedBox(width: 4),
            const Expanded(child: SizedBox.shrink()),
          ],
        ],
      );
    }

    return Container(
      width: 220,
      margin: const EdgeInsets.only(bottom: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildRow(0, displayCount >= 2 ? 2 : displayCount),
          if (displayCount > 2) ...[
            const SizedBox(height: 4),
            buildRow(2, displayCount - 2),
          ],
        ],
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
