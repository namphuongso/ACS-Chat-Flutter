import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/widgets/chat_dialogs.dart';
import 'attachment_action.dart';

class MessageInput extends ConsumerStatefulWidget {
  const MessageInput({
    super.key,
    required this.onSend,
    this.onSendImages,
    this.onSendFiles,
    this.onSendVideos,
  });

  final void Function(String content) onSend;
  final void Function(List<({String path, String fileName})> images)?
      onSendImages;
  final void Function(List<({String path, String fileName})> files)?
      onSendFiles;
  final void Function(List<({String path, String fileName})> videos)?
      onSendVideos;

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
    setState(() {
      if (_focusNode.hasFocus && _showAttachmentPanel) {
        _showAttachmentPanel = false;
      }
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  void _handleSendLike() {
    widget.onSend('👍');
  }

  void _toggleAttachmentPanel() {
    _focusNode.unfocus();
    setState(() {
      _showAttachmentPanel = !_showAttachmentPanel;
    });
  }

  static const _supportedExtensions = {
    'jpg',
    'jpeg',
    'png',
    'heic',
    'heif',
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'mp4',
    'mov',
  };

  /// Chuyển danh sách file vừa chọn sang dạng (path, fileName). Một số
  /// nguồn file (cloud, SAF trên Android, iCloud chưa tải về...) chỉ trả
  /// bytes mà không có path — ghi ra file tạm để luồng upload chạy được
  /// thay vì bị bỏ qua thầm lặng.
  Future<List<({String path, String fileName})>> _resolvePickedFiles(
    List<PlatformFile> files,
  ) async {
    final resolved = <({String path, String fileName})>[];
    var rejectedCount = 0;

    for (final f in files) {
      final ext = f.name.contains('.')
          ? f.name.split('.').last.toLowerCase()
          : (f.extension?.toLowerCase() ?? '');

      if (ext.isNotEmpty && !_supportedExtensions.contains(ext)) {
        rejectedCount++;
        continue;
      }

      if (f.path != null) {
        resolved.add((path: f.path!, fileName: f.name));
        continue;
      }
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      final tempFile = File(
        '${Directory.systemTemp.path}/chat_upload_${DateTime.now().millisecondsSinceEpoch}_${f.name}',
      );
      await tempFile.writeAsBytes(bytes, flush: true);
      resolved.add((path: tempFile.path, fileName: f.name));
    }

    if (rejectedCount > 0 && mounted) {
      showChatToast(
        context,
        message:
            'Có $rejectedCount tệp không được hỗ trợ. Chỉ hỗ trợ: jpg, jpeg, png, heic, heif, pdf, doc, docx, xls, xlsx, ppt, pptx, mp4, mov.',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
    }

    return resolved;
  }

  Future<void> _processAndSendImages(
    List<({String path, String fileName})> imageFiles,
  ) async {
    final imagesToSend = <({String path, String fileName})>[];

    for (final item in imageFiles) {
      final file = File(item.path);
      final size = file.existsSync() ? await file.length() : 0;
      if (size > 100 * 1024 * 1024) {
        if (!mounted) return;
        final confirm = await showSendAsFileDialog(
          context: context,
          fileName: item.fileName,
          sizeBytes: size,
          config: ref.read(chatUiConfigProvider),
        );
        if (confirm) {
          imagesToSend.add(item);
        }
      } else {
        imagesToSend.add(item);
      }
    }

    if (!mounted) return;
    if (imagesToSend.isNotEmpty) {
      widget.onSendImages?.call(imagesToSend);
    }
  }

  Future<void> _takePhoto() async {
    _focusNode.unfocus();
    setState(() {
      _showAttachmentPanel = false;
    });
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (photo == null || !mounted) return;
      final validFiles = await _resolvePickedFiles([
        PlatformFile(
          path: photo.path,
          name: photo.name.isNotEmpty
              ? photo.name
              : 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
          size: await photo.length(),
        ),
      ]);
      if (!mounted) return;
      if (validFiles.isNotEmpty) {
        await _processAndSendImages(validFiles);
      }
    } catch (e) {
      if (!mounted) return;
      showChatToast(
        context,
        message: 'Không thể mở máy ảnh hoặc chưa được cấp quyền.',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
    }
  }

  Future<void> _pickImages() async {
    _focusNode.unfocus();
    setState(() {
      _showAttachmentPanel = false;
    });
    try {
      final picker = ImagePicker();
      final photos = await picker.pickMultiImage(
        imageQuality: 85,
      );
      if (photos.isEmpty || !mounted) return;
      final platformFiles = <PlatformFile>[];
      for (final photo in photos) {
        platformFiles.add(
          PlatformFile(
            path: photo.path,
            name: photo.name.isNotEmpty
                ? photo.name
                : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
            size: await photo.length(),
          ),
        );
      }
      final validFiles = await _resolvePickedFiles(platformFiles);
      if (!mounted) return;
      if (validFiles.isNotEmpty) {
        await _processAndSendImages(validFiles);
      }
    } catch (e) {
      if (!mounted) return;
      showChatToast(
        context,
        message: 'Không thể mở thư viện hoặc chưa được cấp quyền.',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
    }
  }

  Future<void> _pickFiles() async {
    _focusNode.unfocus();
    setState(() {
      _showAttachmentPanel = false;
    });
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'heic',
        'heif',
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'mp4',
        'mov',
      ],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final validFiles = await _resolvePickedFiles(result.files);
    if (!mounted) return;
    if (validFiles.isNotEmpty) {
      widget.onSendFiles?.call(validFiles);
    }
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
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => SizeTransition(
                      sizeFactor: animation,
                      axis: Axis.horizontal,
                      alignment: Alignment.centerLeft,
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    ),
                    child: hasText
                        ? Padding(
                            key: const ValueKey('text_actions'),
                            padding: const EdgeInsets.only(right: 2),
                            child: IconButton(
                              constraints: const BoxConstraints.tightFor(
                                  width: 40, height: 44),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.standard,
                              icon: Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 20,
                                color: iconColor,
                              ),
                              onPressed: () => setState(() {}),
                            ),
                          )
                        : Row(
                            key: const ValueKey('full_actions'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _InputIcon(
                                icon: _showAttachmentPanel
                                    ? Icons.close
                                    : Icons.add,
                                color: iconColor,
                                onPressed: _toggleAttachmentPanel,
                              ),
                              _InputIcon(
                                icon: Icons.camera_alt_outlined,
                                color: iconColor,
                                onPressed: _takePhoto,
                              ),
                              _InputIcon(
                                icon: Icons.photo_library_outlined,
                                color: iconColor,
                                onPressed: _pickImages,
                              ),
                            ],
                          ),
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
                              cursorColor: Colors.black,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _handleSend(),
                              decoration: InputDecoration(
                                hintText: 'Nhập tin nhắn...',
                                hintStyle: TextStyle(
                                  color: config.inputHintColor ??
                                      Colors.grey.shade500,
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            constraints: const BoxConstraints.tightFor(
                                width: 36, height: 44),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.sentiment_satisfied_alt_outlined,
                              color: iconColor,
                            ),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  hasText
                      ? IconButton(
                          constraints: const BoxConstraints.tightFor(
                              width: 40, height: 44),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.send_rounded,
                            color: config.primaryActionColor ??
                                theme.colorScheme.primary,
                          ),
                          onPressed: _handleSend,
                        )
                      : IconButton(
                          constraints: const BoxConstraints.tightFor(
                              width: 40, height: 44),
                          padding: EdgeInsets.zero,
                          icon: const Text('👍', style: TextStyle(fontSize: 22)),
                          onPressed: _handleSendLike,
                        ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: _showAttachmentPanel
                  ? SizedBox(
                      height: 104,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 16, top: 8),
                            child: Row(
                              children: [
                                AttachmentAction(
                                  icon: Icons.insert_drive_file_outlined,
                                  label: 'Tệp',
                                  color: iconColor,
                                  onTap: _pickFiles,
                                ),
                              ],
                            ),
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
