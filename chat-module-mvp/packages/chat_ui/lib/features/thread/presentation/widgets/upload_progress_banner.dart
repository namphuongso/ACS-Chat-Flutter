import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../providers/thread_providers.dart';

class UploadProgressBanner extends ConsumerWidget {
  const UploadProgressBanner({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressState = ref.watch(mediaUploadProgressProvider);
    final items = progressState[roomId];

    if (items == null || items.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalCount = items.length;
    final completedCount = items.where((i) => i.progress >= 1.0).length;
    final totalProgress = items.fold<double>(0.0, (sum, i) => sum + i.progress);
    final overallPercent =
        ((totalProgress / totalCount) * 100).toInt().clamp(0, 100);

    final config = ref.watch(chatUiConfigProvider);
    final theme = Theme.of(context);
    final primary = config.primaryActionColor ?? theme.colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (config.surfaceColor ?? theme.colorScheme.surface)
            .withValues(alpha: 0.6),
        border: Border(
          top: BorderSide(
            color: Colors.grey.shade300,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Đang tải lên $completedCount/$totalCount tệp',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                '$overallPercent%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final percent = (item.progress * 100).toInt().clamp(0, 100);
                final isDone = item.progress >= 1.0;
                final file = File(item.path);
                final ext = item.fileName.split('.').last.toLowerCase();
                final isImage = [
                  'jpg',
                  'jpeg',
                  'png',
                  'gif',
                  'webp',
                  'heic',
                  'bmp'
                ].contains(ext);

                return SizedBox(
                  width: 64,
                  height: 64,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: (isImage && file.existsSync())
                              ? Image.file(
                                  file,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.grey.shade300,
                                    child: const Icon(Icons.insert_drive_file,
                                        color: Colors.grey),
                                  ),
                                )
                              : Container(
                                  color: Colors.grey.shade300,
                                  child: Icon(
                                    isImage
                                        ? Icons.image
                                        : Icons.insert_drive_file,
                                    color: Colors.grey,
                                  ),
                                ),
                        ),
                        Positioned.fill(
                          child: Container(
                            color: isDone ? Colors.black26 : Colors.black54,
                          ),
                        ),
                        Center(
                          child: isDone
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.greenAccent,
                                  size: 28,
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        value: item.progress,
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                primary),
                                        backgroundColor: Colors.white38,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$percent%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
