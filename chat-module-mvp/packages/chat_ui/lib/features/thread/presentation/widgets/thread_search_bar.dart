import 'package:flutter/material.dart';

import '../../../../core/chat_ui_config.dart';

/// Embedded search bar header widget for thread message search.
class ThreadSearchBar extends StatelessWidget {
  const ThreadSearchBar({
    super.key,
    required this.controller,
    required this.config,
    required this.searchResultsCount,
    required this.currentSearchIndex,
    required this.isSearchingDeeper,
    required this.onChanged,
    required this.onNext,
    required this.onPrev,
    required this.onClose,
  });

  final TextEditingController controller;
  final ChatUiConfig config;
  final int searchResultsCount;
  final int currentSearchIndex;
  final bool isSearchingDeeper;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final primary = config.primaryActionColor ?? Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: config.surfaceColor ?? Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText: 'Tìm nội dung tin nhắn...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              controller.clear();
                              onChanged('');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (searchResultsCount > 0) ...[
                Text(
                  '${currentSearchIndex + 1}/$searchResultsCount',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  onPressed: currentSearchIndex > 0 ? onPrev : null,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: currentSearchIndex < searchResultsCount - 1
                      ? onNext
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
              ] else if (controller.text.trim().isNotEmpty) ...[
                Text(
                  isSearchingDeeper ? 'Đang tìm...' : '0 kết quả',
                  style: TextStyle(
                    fontSize: 12,
                    color: isSearchingDeeper ? primary : Colors.grey.shade600,
                  ),
                ),
              ],
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (isSearchingDeeper)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: primary,
                backgroundColor: primary.withValues(alpha: 0.1),
              ),
            ),
        ],
      ),
    );
  }
}
