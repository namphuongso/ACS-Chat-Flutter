import 'dart:io';
import '../../../../core/utils/image_dimension_utils.dart';
import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/thread_providers.dart';

/// Tải media (ảnh/tệp/video) lên qua Azure Blob SAS URL, cập nhật tiến
/// trình qua [mediaUploadProgressProvider], báo lỗi qua
/// [mediaUploadErrorProvider], rời gọi callback `sendMessage` để gửi tin
/// kết quả (logic optimistic send vẫn nằm ở notifier).
///
/// Tách khỏi `ThreadMessagesNotifier` để giảm mỡ notifier; notifier giữ
/// method mỏng delegate giữ nguyên API cho widget.
class MessageMediaUploadService {
  MessageMediaUploadService({
    required Ref ref,
    required String roomId,
    required Future<void> Function(
      String content, {
      Map<String, dynamic>? metaData,
    }) sendMessage,
  })  : _ref = ref,
        _roomId = roomId,
        _sendMessage = sendMessage;

  final Ref _ref;
  final String _roomId;
  final Future<void> Function(String content, {Map<String, dynamic>? metaData})
      _sendMessage;

  /// Tải các hình ảnh được chọn lên qua Azure Blob SAS URL và gửi tin nhắn hình ảnh.
  Future<void> sendImages(
    List<({String path, String fileName})> imageFiles,
  ) async {
    if (imageFiles.isEmpty) return;
    final uploadSasUseCase = _ref.read(uploadFileViaSasUseCaseProvider);

    final initialItems = imageFiles
        .map((item) => MediaUploadItemProgress(
              fileName: item.fileName,
              path: item.path,
              progress: 0.01,
            ))
        .toList();

    _ref
        .read(mediaUploadProgressProvider.notifier)
        .setRoomProgress(_roomId, initialItems);

    final uploadedFiles = <Map<String, String>>[];
    final failedFiles = <String>[];

    try {
      for (final item in imageFiles) {
        try {
          final mimeType = ChatMimeUtils.lookupMimeType(item.fileName);
          final url = await uploadSasUseCase(
            filePath: item.path,
            fileName: item.fileName,
            contentType: mimeType,
            onProgress: (sent, total) {
              if (total > 0) {
                final ratio = (sent / total).clamp(0.01, 0.99);
                _ref
                    .read(mediaUploadProgressProvider.notifier)
                    .setItemProgress(_roomId, item.fileName, ratio);
              }
            },
          );

          _ref
              .read(mediaUploadProgressProvider.notifier)
              .setItemProgress(_roomId, item.fileName, 1.0);

          final file = File(item.path);
          final dimensions = await ImageDimensionUtils.getDimensions(file);
          final width = dimensions.width;
          final height = dimensions.height;

          final fileSize = file.existsSync() ? await file.length() : 0;

          uploadedFiles.add({
            'url': url,
            'fileName': item.fileName,
            'mimeType': mimeType,
            'width': width.toString(),
            'height': height.toString(),
            'size': fileSize.toString(),
            'fileSize': fileSize.toString(),
          });
        } catch (e, st) {
          ChatLogger.error('Upload image failed for ${item.fileName}',
              error: e, stackTrace: st);
          failedFiles.add(item.fileName);
        }
      }

      if (uploadedFiles.isNotEmpty) {
        final firstFile = uploadedFiles.first;
        final firstSize = int.tryParse(firstFile['size'] ?? '') ?? 0;
        final metaData = <String, dynamic>{
          'type': 'image',
          'url': firstFile['url']?.toString() ?? '',
          'fileName': firstFile['fileName']?.toString() ?? '',
          'size': firstSize,
          'fileSize': firstSize.toString(),
          'files': uploadedFiles
              .map((item) {
                final itemSize = int.tryParse(item['size'] ?? '') ?? 0;
                return {
                  'url': item['url']?.toString() ?? '',
                  'fileName': item['fileName']?.toString() ?? '',
                  'mimeType': item['mimeType']?.toString() ?? 'image/jpeg',
                  'size': itemSize,
                  'fileSize': itemSize.toString(),
                  'width': item['width']?.toString() ?? '0',
                  'height': item['height']?.toString() ?? '0',
                };
              })
              .toList(),
        };

        await _sendMessage('[Hình ảnh]', metaData: metaData);
      }

      _reportUploadFailures(failedFiles, imageFiles.length);
    } finally {
      _ref
          .read(mediaUploadProgressProvider.notifier)
          .setRoomProgress(_roomId, null);
    }
  }

  /// Tải các tệp tài liệu được chọn lên qua Azure Blob SAS URL và gửi tin nhắn tệp.
  Future<void> sendFiles(
    List<({String path, String fileName})> fileItems,
  ) async {
    if (fileItems.isEmpty) return;
    final uploadSasUseCase = _ref.read(uploadFileViaSasUseCaseProvider);

    final initialItems = fileItems
        .map((item) => MediaUploadItemProgress(
              fileName: item.fileName,
              path: item.path,
              progress: 0.01,
            ))
        .toList();

    _ref
        .read(mediaUploadProgressProvider.notifier)
        .setRoomProgress(_roomId, initialItems);

    final uploadedFiles = <Map<String, String>>[];
    final failedFiles = <String>[];

    try {
      for (final item in fileItems) {
        try {
          final mimeType = ChatMimeUtils.lookupMimeType(item.fileName);
          final url = await uploadSasUseCase(
            filePath: item.path,
            fileName: item.fileName,
            contentType: mimeType,
            onProgress: (sent, total) {
              if (total > 0) {
                final ratio = (sent / total).clamp(0.01, 0.99);
                _ref
                    .read(mediaUploadProgressProvider.notifier)
                    .setItemProgress(_roomId, item.fileName, ratio);
              }
            },
          );

          _ref
              .read(mediaUploadProgressProvider.notifier)
              .setItemProgress(_roomId, item.fileName, 1.0);

          final file = File(item.path);
          final fileSize = file.existsSync() ? await file.length() : 0;

          uploadedFiles.add({
            'url': url,
            'fileName': item.fileName,
            'mimeType': mimeType,
            'fileSize': fileSize.toString(),
          });
        } catch (e, st) {
          ChatLogger.error('Upload file failed for ${item.fileName}',
              error: e, stackTrace: st);
          failedFiles.add(item.fileName);
        }
      }

      if (uploadedFiles.isNotEmpty) {
        final firstFile = uploadedFiles.first;
        final metaData = <String, dynamic>{
          'type': 'file',
          'url': firstFile['url']?.toString() ?? '',
          'fileName': firstFile['fileName']?.toString() ?? '',
          'fileSize': firstFile['fileSize']?.toString() ?? '0',
          'files': uploadedFiles
              .map((item) => {
                    'url': item['url']?.toString() ?? '',
                    'fileName': item['fileName']?.toString() ?? '',
                    'mimeType': item['mimeType']?.toString() ??
                        'application/octet-stream',
                    'fileSize': item['fileSize']?.toString() ?? '0',
                  })
              .toList(),
        };

        await _sendMessage('[Tệp tin]', metaData: metaData);
      }

      _reportUploadFailures(failedFiles, fileItems.length);
    } finally {
      _ref
          .read(mediaUploadProgressProvider.notifier)
          .setRoomProgress(_roomId, null);
    }
  }

  /// Tải video được chọn lên qua Azure Blob SAS URL và gửi tin nhắn video.
  /// Mỗi video gửi 1 tin riêng (bubble đang render theo metadata['fileName']).
  Future<void> sendVideos(
    List<({String path, String fileName})> videoItems,
  ) async {
    if (videoItems.isEmpty) return;
    final uploadSasUseCase = _ref.read(uploadFileViaSasUseCaseProvider);

    final initialItems = videoItems
        .map((item) => MediaUploadItemProgress(
              fileName: item.fileName,
              path: item.path,
              progress: 0.01,
            ))
        .toList();

    _ref
        .read(mediaUploadProgressProvider.notifier)
        .setRoomProgress(_roomId, initialItems);

    final uploadedFiles = <Map<String, String>>[];
    final failedFiles = <String>[];

    try {
      for (final item in videoItems) {
        try {
          final ext = item.fileName.split('.').last.toLowerCase();
          final mimeType = ext == 'mov' ? 'video/quicktime' : 'video/mp4';

          final url = await uploadSasUseCase(
            filePath: item.path,
            fileName: item.fileName,
            contentType: mimeType,
            onProgress: (sent, total) {
              if (total > 0) {
                final ratio = (sent / total).clamp(0.01, 0.99);
                _ref
                    .read(mediaUploadProgressProvider.notifier)
                    .setItemProgress(_roomId, item.fileName, ratio);
              }
            },
          );

          _ref
              .read(mediaUploadProgressProvider.notifier)
              .setItemProgress(_roomId, item.fileName, 1.0);

          final file = File(item.path);
          final fileSize = file.existsSync() ? await file.length() : 0;

          uploadedFiles.add({
            'url': url,
            'fileName': item.fileName,
            'mimeType': mimeType,
            'fileSize': fileSize.toString(),
          });
        } catch (e, st) {
          ChatLogger.error('Upload video failed for ${item.fileName}',
              error: e, stackTrace: st);
          failedFiles.add(item.fileName);
        }
      }

      for (final item in uploadedFiles) {
        final metaData = <String, dynamic>{
          'type': 'video',
          'url': item['url'] ?? '',
          'fileName': item['fileName'] ?? '',
          'mimeType': item['mimeType'] ?? 'video/mp4',
          'fileSize': item['fileSize'] ?? '0',
        };
        await _sendMessage('[Video]', metaData: metaData);
      }

      _reportUploadFailures(failedFiles, videoItems.length);
    } finally {
      _ref
          .read(mediaUploadProgressProvider.notifier)
          .setRoomProgress(_roomId, null);
    }
  }

  /// Báo cho UI (toast) danh sách tệp upload thất bại để người dùng biết
  /// vì sao "có file gửi được, có file không".
  void _reportUploadFailures(List<String> failedFiles, int totalCount) {
    if (failedFiles.isEmpty || !_ref.mounted) return;
    final names = failedFiles.take(3).join(', ');
    final suffix = failedFiles.length > 3 ? '…' : '';
    final message = failedFiles.length == totalCount
        ? 'Không thể tải lên ${failedFiles.length} tệp: $names$suffix'
        : '${failedFiles.length}/$totalCount tệp tải lên thất bại: $names$suffix';
    _ref.read(mediaUploadErrorProvider.notifier).setError(_roomId, message);
  }
}
