import 'package:flutter/material.dart';

import '../../../../core/chat_ui_config.dart';

class RoomDangerZone extends StatelessWidget {
  const RoomDangerZone({
    super.key,
    required this.config,
    required this.isGroup,
    required this.isAdmin,
    required this.onLeaveTap,
    required this.onDisbandTap,
  });

  final ChatUiConfig config;
  final bool isGroup;
  final bool isAdmin;
  final VoidCallback onLeaveTap;
  final VoidCallback onDisbandTap;

  @override
  Widget build(BuildContext context) {
    if (!isGroup) return const SizedBox.shrink();

    final danger = config.dangerColor ?? Colors.redAccent;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: config.surfaceColor ?? Colors.white,
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.exit_to_app, color: danger, size: 28),
              title: Text(
                'Rời khỏi phòng',
                style: TextStyle(
                  color: danger,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: onLeaveTap,
            ),
            if (isAdmin) ...[
              const Divider(height: 1, indent: 16, color: Color(0xFFF2F4F7)),
              ListTile(
                leading: Icon(Icons.delete_outline, color: danger, size: 28),
                title: Text(
                  'Giải tán nhóm',
                  style: TextStyle(
                    color: danger,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: onDisbandTap,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
