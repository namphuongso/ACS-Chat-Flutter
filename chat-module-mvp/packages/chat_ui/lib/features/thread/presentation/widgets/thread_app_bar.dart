import 'package:flutter/material.dart';

import '../../../../core/chat_ui_config.dart';

/// App bar widget for the thread view.
class ThreadAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ThreadAppBar({
    super.key,
    required this.roomName,
    required this.avatarUrl,
    required this.config,
    required this.isSearching,
    required this.onSearchTap,
    required this.onSettingsTap,
    required this.onBackTap,
  });

  final String roomName;
  final String? avatarUrl;
  final ChatUiConfig config;
  final bool isSearching;
  final VoidCallback onSearchTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onBackTap;

  @override
  Widget build(BuildContext context) {
    final primary = config.primaryActionColor ?? Theme.of(context).colorScheme.primary;

    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: onBackTap,
      ),
      title: InkWell(
        onTap: onSettingsTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                roomName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            isSearching ? Icons.search_off_rounded : Icons.search_rounded,
            color: isSearching ? primary : Colors.black87,
          ),
          tooltip: 'Tìm kiếm tin nhắn',
          onPressed: onSearchTap,
        ),
        IconButton(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: 'Cài đặt phòng',
          onPressed: onSettingsTap,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
