import 'package:flutter/material.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/widgets/skeleton.dart';

/// Search bar widget for message searching in thread view (restored to original exact design).
class ThreadSearchBar extends StatelessWidget implements PreferredSizeWidget {
  const ThreadSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.config,
    required this.searchResultsCount,
    required this.currentSearchIndex,
    required this.isSearchingDeeper,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onNext,
    required this.onPrev,
    required this.onClose,
    required this.onSearchResultsTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ChatUiConfig config;
  final int searchResultsCount;
  final int currentSearchIndex;
  final bool isSearchingDeeper;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onClose;
  final VoidCallback onSearchResultsTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: config.appBarBackgroundColor,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios,
          color: config.iconColor ?? theme.iconTheme.color,
        ),
        onPressed: onClose,
      ),
      titleSpacing: 0,
      title: TextField(
        controller: controller,
        focusNode: focusNode,
        cursorColor: Colors.black,
        style: TextStyle(
          fontSize: 15,
          color: config.appBarIconColor ?? Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: 'Tìm tin nhắn...',
          hintStyle: TextStyle(
            fontSize: 15,
            color: (config.appBarIconColor ?? Colors.black87)
                .withValues(alpha: 0.5),
          ),
          border: InputBorder.none,
        ),
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
      actions: [
        if (controller.text.isNotEmpty) ...[
          IconButton(
            icon: Icon(
              Icons.clear,
              size: 20,
              color: config.iconColor ?? theme.iconTheme.color,
            ),
            onPressed: onClear,
          ),
          if (isSearchingDeeper)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: SkeletonBox(width: 36, height: 16, radius: 8),
              ),
            ),
          if (searchResultsCount > 0) ...[
            GestureDetector(
              onTap: onSearchResultsTap,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (config.iconColor ??
                            theme.iconTheme.color ??
                            Colors.black87)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${currentSearchIndex + 1}/$searchResultsCount',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: config.iconColor ?? theme.iconTheme.color,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                Icons.keyboard_arrow_up,
                color: config.iconColor ?? theme.iconTheme.color,
              ),
              tooltip: 'Tin mới hơn',
              onPressed: onNext,
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                Icons.keyboard_arrow_down,
                color: config.iconColor ?? theme.iconTheme.color,
              ),
              tooltip: 'Tin cũ hơn',
              onPressed: onPrev,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
