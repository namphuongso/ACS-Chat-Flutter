import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/widgets/chat_dialogs.dart';

class MessageInput extends ConsumerStatefulWidget {
  const MessageInput({
    super.key,
    required this.onSend,
    this.onSendImages,
    this.onSendFiles,
  });

  final void Function(String content) onSend;
  final void Function(List<({String path, String fileName})> images)? onSendImages;
  final void Function(List<({String path, String fileName})> files)? onSendFiles;

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _showAttachmentPanel = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onTextChanged() => setState(() {});

  void _onFocusChanged() {
    if (_focusNode.hasFocus && _showAttachmentPanel) {
      setState(() => _showAttachmentPanel = false);
    }
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  void _toggleAttachmentPanel() {
    _focusNode.unfocus();
    setState(() => _showAttachmentPanel = !_showAttachmentPanel);
  }

  Future<void> _pickImages() async {
    _focusNode.unfocus();
    setState(() => _showAttachmentPanel = false);
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final validFiles = result.files
        .where((f) => f.path != null)
        .map((f) => (path: f.path!, fileName: f.name))
        .toList();
    if (validFiles.isNotEmpty) {
      widget.onSendImages?.call(validFiles);
    }
  }

  Future<void> _pickFiles() async {
    _focusNode.unfocus();
    setState(() => _showAttachmentPanel = false);
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final validFiles = result.files
        .where((f) => f.path != null)
        .map((f) => (path: f.path!, fileName: f.name))
        .toList();
    if (validFiles.isNotEmpty) {
      widget.onSendFiles?.call(validFiles);
    }
  }

  void _showComingSoon(String feature) {
    _focusNode.unfocus();
    showChatFeatureComingSoon(
      context,
      feature: feature,
      config: ref.read(chatUiConfigProvider),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(chatUiConfigProvider);
    final iconColor = config.inputActionIconColor ??
        config.iconColor ??
        theme.colorScheme.primary;
    final hasText = _controller.text.trim().isNotEmpty;

    return Material(
      color: config.inputBarBackgroundColor ?? Colors.white,
      elevation: 8,
      shadowColor: Colors.black12,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _InputIcon(
                    icon: _showAttachmentPanel ? Icons.close : Icons.add,
                    color: iconColor,
                    onPressed: _toggleAttachmentPanel,
                  ),
                  _InputIcon(
                    icon: Icons.camera_alt_outlined,
                    color: iconColor,
                    onPressed: () => _showComingSoon('Chụp ảnh'),
                  ),
                  _InputIcon(
                    icon: Icons.photo_library_outlined,
                    color: iconColor,
                    onPressed: _pickImages,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: config.inputFieldFillColor ??
                            const Color(0xFFF5F6FA),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: config.inputFieldBorderColor ??
                              theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.newline,
                              style: config.inputTextColor == null
                                  ? null
                                  : TextStyle(color: config.inputTextColor),
                              decoration: InputDecoration(
                                hintText: 'Nhập tin nhắn...',
                                hintStyle: config.inputHintColor == null
                                    ? null
                                    : TextStyle(color: config.inputHintColor),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.fromLTRB(14, 11, 4, 11),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Biểu tượng cảm xúc',
                            icon: Icon(Icons.sentiment_satisfied_alt_outlined,
                                color: iconColor),
                            onPressed: () =>
                                _showComingSoon('Biểu tượng cảm xúc'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: IconButton(
                        key: ValueKey(hasText),
                        tooltip: hasText ? 'Gửi' : 'Ghi âm',
                        icon: Icon(
                          hasText ? Icons.send : Icons.mic_none,
                          color: iconColor,
                        ),
                        onPressed: hasText
                            ? _handleSend
                            : () => _showComingSoon('Ghi âm'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: _showAttachmentPanel
                  ? SizedBox(
                      height: 112,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        children: [
                          _AttachmentAction(
                            icon: Icons.photo_library_outlined,
                            label: 'Thư viện',
                            color: Colors.purple,
                            onTap: _pickImages,
                          ),
                          _AttachmentAction(
                            icon: Icons.camera_alt_outlined,
                            label: 'Máy ảnh',
                            color: Colors.pink,
                            onTap: () => _showComingSoon('Chụp ảnh'),
                          ),
                          _AttachmentAction(
                            icon: Icons.location_on_outlined,
                            label: 'Vị trí',
                            color: Colors.green,
                            onTap: () => _showComingSoon('Chia sẻ vị trí'),
                          ),
                          _AttachmentAction(
                            icon: Icons.insert_drive_file_outlined,
                            label: 'Tệp',
                            color: Colors.blue,
                            onTap: _pickFiles,
                          ),
                          _AttachmentAction(
                            icon: Icons.person_outline,
                            label: 'Liên hệ',
                            color: Colors.orange,
                            onTap: () => _showComingSoon('Chia sẻ liên hệ'),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputIcon extends StatelessWidget {
  const _InputIcon({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        constraints: const BoxConstraints.tightFor(width: 40, height: 44),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      );
}

class _AttachmentAction extends StatelessWidget {
  const _AttachmentAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 76,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );
}
