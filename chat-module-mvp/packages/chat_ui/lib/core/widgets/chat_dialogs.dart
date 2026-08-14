import 'package:flutter/material.dart';

import '../chat_ui_config.dart';

Future<String?> showChatTextInputDialog({
  required BuildContext context,
  required ChatUiConfig config,
  required String title,
  required String hintText,
  String initialValue = '',
  String cancelLabel = 'Hủy',
  String confirmLabel = 'Lưu',
  int maxLines = 1,
  String? description,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ChatTextInputDialog(
      config: config,
      title: title,
      hintText: hintText,
      initialValue: initialValue,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      maxLines: maxLines,
      description: description,
    ),
  );
}

Future<bool> showChatConfirmDialog({
  required BuildContext context,
  required ChatUiConfig config,
  required String title,
  required String message,
  String cancelLabel = 'Hủy',
  String confirmLabel = 'Xác nhận',
  bool destructive = false,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: config.dialogBackgroundColor ?? Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(title),
          content: Text(message),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(cancelLabel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: destructive
                    ? config.dangerColor ?? Colors.red
                    : config.primaryActionColor,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

class ChatActionMenuTile extends StatelessWidget {
  const ChatActionMenuTile({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color)),
        ],
      );
}

Future<void> showChatFeatureComingSoon(
  BuildContext context, {
  required String feature,
  ChatUiConfig? config,
}) {
  final ui = config;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: ui?.dialogBackgroundColor ?? Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Tính năng đang phát triển'),
      content: Text(
        '$feature hiện chưa được phát triển. Tính năng sẽ được cập nhật ở phiên bản sau.',
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ui?.primaryActionColor,
          ),
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Đã hiểu'),
        ),
      ],
    ),
  );
}

void showChatToast(
  BuildContext context, {
  required String message,
  bool isError = false,
  ChatUiConfig? config,
  Duration duration = const Duration(seconds: 2),
}) {
  final ui = config;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      backgroundColor: isError
          ? (ui?.dangerColor ?? const Color(0xFFE53935))
          : const Color(0xFF2C2C2E).withValues(alpha: 0.92),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      duration: duration,
    ),
  );
}


class _ChatTextInputDialog extends StatefulWidget {
  const _ChatTextInputDialog({
    required this.config,
    required this.title,
    required this.hintText,
    required this.initialValue,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.maxLines,
    this.description,
  });

  final ChatUiConfig config;
  final String title;
  final String hintText;
  final String initialValue;
  final String cancelLabel;
  final String confirmLabel;
  final int maxLines;
  final String? description;

  @override
  State<_ChatTextInputDialog> createState() => _ChatTextInputDialogState();
}

class _ChatTextInputDialogState extends State<_ChatTextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: widget.config.dialogBackgroundColor ?? Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(widget.description!, textAlign: TextAlign.center),
              ),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: widget.maxLines,
              decoration: InputDecoration(
                hintText: widget.hintText,
                filled: true,
                fillColor: widget.config.formFieldFillColor,
                enabledBorder: _border,
                focusedBorder: _border.copyWith(
                  borderSide: BorderSide(
                    color: widget.config.primaryActionColor ??
                        Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.cancelLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.config.primaryActionColor,
            ),
            onPressed: () {
              final value = _controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: Text(widget.confirmLabel),
          ),
        ],
      );

  OutlineInputBorder get _border => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: widget.config.formFieldBorderColor ?? Colors.grey.shade300,
        ),
      );
}
