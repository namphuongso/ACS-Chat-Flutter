import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';

class MessageInput extends ConsumerStatefulWidget {
  const MessageInput({super.key, required this.onSend});

  final void Function(String content) onSend;

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    FocusManager.instance.primaryFocus?.unfocus();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(chatUiConfigProvider);
    final fieldFill = config.inputFieldFillColor;
    final borderColor = config.inputFieldBorderColor;
    final border = OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      borderSide: borderColor != null
          ? BorderSide(color: borderColor)
          : const BorderSide(),
    );

    return SafeArea(
      child: Container(
        color: config.inputBarBackgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                style: config.inputTextColor != null
                    ? TextStyle(color: config.inputTextColor)
                    : null,
                decoration: InputDecoration(
                  hintText: 'Nhập tin nhắn...',
                  hintStyle: config.inputHintColor != null
                      ? TextStyle(color: config.inputHintColor)
                      : null,
                  filled: fieldFill != null,
                  fillColor: fieldFill,
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Chỉ hiện nút gửi khi ô input có nội dung (không phải khoảng trắng).
            if (_controller.text.trim().isNotEmpty)
              IconButton(
                icon: Icon(
                  Icons.send,
                  color: config.iconColor ?? theme.colorScheme.primary,
                ),
                onPressed: _handleSend,
              ),
          ],
        ),
      ),
    );
  }
}
