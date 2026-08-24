import 'package:flutter/material.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';

/// App bar widget for the thread view (restored to original exact design).
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
    final theme = Theme.of(context);
    final hasAvatar = isNetworkAvatar(avatarUrl);
    final initial = roomName.isNotEmpty ? roomName[0].toUpperCase() : '?';

    return AppBar(
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: config.appBarBackgroundColor,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios,
          color: config.iconColor ?? theme.iconTheme.color,
        ),
        onPressed: onBackTap,
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFF0F2F5),
            backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
            child: !hasAvatar
                ? Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              roomName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: config.appBarIconColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            isSearching ? Icons.close : Icons.search,
            color: config.iconColor ?? theme.iconTheme.color,
          ),
          onPressed: onSearchTap,
        ),
        IconButton(
          icon: Icon(
            Icons.info_outline,
            color: config.iconColor ?? theme.iconTheme.color,
          ),
          onPressed: onSettingsTap,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
