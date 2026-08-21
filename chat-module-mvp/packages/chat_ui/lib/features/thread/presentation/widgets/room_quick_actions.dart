import 'package:flutter/material.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/widgets/chat_dialogs.dart';

class RoomQuickActions extends StatelessWidget {
  const RoomQuickActions({
    super.key,
    required this.config,
    required this.onSearchTap,
    required this.onAddMembersTap,
  });

  final ChatUiConfig config;
  final VoidCallback onSearchTap;
  final VoidCallback onAddMembersTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = config.actionIconColor ?? Colors.black87;
    final items = [
      (Icons.search, 'Tìm\ntin nhắn'),
      (Icons.group_add_outlined, 'Thêm\nthành viên'),
      (Icons.wallpaper_outlined, 'Đổi\nhình nền'),
    ];
    return Material(
      color: config.surfaceColor ?? Colors.white,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final item in items)
              Expanded(
                child: InkWell(
                  onTap: item.$1 == Icons.search
                      ? onSearchTap
                      : (item.$1 == Icons.group_add_outlined
                          ? onAddMembersTap
                          : () => showChatFeatureComingSoon(
                                context,
                                feature: item.$2.replaceAll('\n', ' '),
                                config: config,
                              )),
                  borderRadius: BorderRadius.circular(14),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: config.actionIconBackgroundColor ??
                            const Color(0xFFF5F6FA),
                        child: Icon(item.$1, color: iconColor, size: 29),
                      ),
                      const SizedBox(height: 8),
                      Text(item.$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, height: 1.15)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
