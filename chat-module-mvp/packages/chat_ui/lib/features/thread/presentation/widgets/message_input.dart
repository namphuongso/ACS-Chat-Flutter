import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/widgets/chat_dialogs.dart';
import 'attachment_panel.dart';
import 'gallery_panel.dart';

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

class _MessageInputState extends ConsumerState<MessageInput>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _showAttachmentPanel = false;

  // Trạng thái gallery ảnh inline (hiện ngay dưới khung nhập liệu).
  bool _showGallery = false;
  bool _galleryLoading = false;
  bool _galleryPermissionDenied = false;
  List<AssetEntity> _galleryAssets = [];
  final Set<String> _selectedAssetIds = {};
  bool _resolvingSelection = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Người dùng có thể vừa cấp quyền trong Settings rồi quay lại —
    // tự kiểm tra lại để gallery hiện ảnh luôn, không cần bấm "Thử lại".
    if (state == AppLifecycleState.resumed &&
        _galleryPermissionDenied &&
        _showGallery) {
      setState(() => _galleryLoading = true);
      _loadGalleryAssets();
    }
  }

  void _onTextChanged() => setState(() {});

  void _onFocusChanged() {
    setState(() {
      if (_focusNode.hasFocus && (_showAttachmentPanel || _showGallery)) {
        _showAttachmentPanel = false;
        _showGallery = false;
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
      _showGallery = false;
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

  Future<void> _takePhoto() async {
    _focusNode.unfocus();
    setState(() {
      _showAttachmentPanel = false;
      _showGallery = false;
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
        widget.onSendImages?.call(validFiles);
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
      _showGallery = false;
    });
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'heic', 'heif'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final validFiles = await _resolvePickedFiles(result.files);
    if (!mounted) return;
    if (validFiles.isNotEmpty) {
      widget.onSendImages?.call(validFiles);
    }
  }

  Future<void> _pickFiles() async {
    _focusNode.unfocus();
    setState(() {
      _showAttachmentPanel = false;
      _showGallery = false;
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

  // ===== Gallery ảnh inline =====

  Future<void> _openGallery() async {
    _focusNode.unfocus();
    if (_showGallery) {
      setState(() => _showGallery = false);
      return;
    }
    setState(() {
      _showAttachmentPanel = false;
      _showGallery = true;
      _galleryLoading = true;
      _galleryPermissionDenied = false;
    });
    await _loadGalleryAssets();
  }

  Future<void> _loadGalleryAssets() async {
    try {
      final permissionState = await PhotoManager.requestPermissionExtend();
      if (!mounted) return;
      final hasAccess = permissionState == PermissionState.authorized ||
          permissionState == PermissionState.limited;
      if (!hasAccess) {
        setState(() {
          _galleryLoading = false;
          _galleryPermissionDenied = true;
        });
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      final album = albums.firstOrNull;
      final assets = album == null
          ? <AssetEntity>[]
          : await album.getAssetListRange(start: 0, end: 100);
      if (!mounted) return;
      setState(() {
        _galleryAssets = assets
            .where(
                (a) => a.type == AssetType.image || a.type == AssetType.video)
            .toList();
        _galleryLoading = false;
        _galleryPermissionDenied = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _galleryLoading = false;
        _galleryPermissionDenied = true;
      });
    }
  }

  void _toggleAssetSelection(AssetEntity asset) {
    setState(() {
      if (_selectedAssetIds.contains(asset.id)) {
        _selectedAssetIds.remove(asset.id);
      } else {
        _selectedAssetIds.add(asset.id);
      }
    });
  }

  Future<void> _sendSelectedAssets() async {
    if (_selectedAssetIds.isEmpty || _resolvingSelection) return;
    setState(() => _resolvingSelection = true);
    final selected =
        _galleryAssets.where((a) => _selectedAssetIds.contains(a.id)).toList();

    final picked = <({String path, String fileName})>[];
    var failedCount = 0;
    for (final asset in selected) {
      try {
        final isVideo = asset.type == AssetType.video;
        var fileName = asset.title;
        if (fileName == null || fileName.isEmpty || !fileName.contains('.')) {
          try {
            final asyncTitle = await asset.titleAsync;
            if (asyncTitle.isNotEmpty && asyncTitle.contains('.')) {
              fileName = asyncTitle;
            }
          } catch (_) {
            // Giữ fallback bên dưới.
          }
        }
        fileName ??=
            'media_${DateTime.now().millisecondsSinceEpoch}_${picked.length}${isVideo ? '.mp4' : '.jpg'}';

        final lowerName = fileName.toLowerCase();
        final isHeic = !isVideo &&
            (lowerName.endsWith('.heic') || lowerName.endsWith('.heif'));

        File? file;
        if (isHeic) {
          // BE không nhận HEIC ("File extension is not supported") —
          // chuyển sang JPEG đúng độ phân giải gốc bằng engine thumbnail
          // của platform (iOS PhotoKit / Android) rồi mới upload.
          file = await _convertHeicToJpeg(asset, fileName);
          if (file != null) {
            fileName =
                fileName.substring(0, fileName.lastIndexOf('.')) + '.jpg';
          } else {
            developer.log(
              '[ChatModule] HEIC convert failed for $fileName — gửi file gốc (BE có thể từ chối)',
            );
          }
        }
        file ??= await asset.file;

        if (file == null) {
          failedCount++;
          continue;
        }
        picked.add((path: file.path, fileName: fileName));
      } catch (_) {
        failedCount++;
      }
    }

    if (!mounted) return;
    const videoExts = {'mp4', 'mov', 'm4v', 'avi', 'mkv', '3gp', 'webm'};
    final pickedVideos = picked
        .where(
            (f) => videoExts.contains(f.fileName.split('.').last.toLowerCase()))
        .toList();
    final videoPaths = pickedVideos.map((f) => f.path).toSet();
    final pickedImages =
        picked.where((f) => !videoPaths.contains(f.path)).toList();

    setState(() {
      _resolvingSelection = false;
      _selectedAssetIds.clear();
      if (picked.isNotEmpty) _showGallery = false;
    });
    if (pickedImages.isNotEmpty) {
      widget.onSendImages?.call(pickedImages);
    }
    if (pickedVideos.isNotEmpty) {
      widget.onSendVideos?.call(pickedVideos);
    }
    if (failedCount > 0) {
      showChatToast(
        context,
        message: failedCount == selected.length
            ? 'Không thể đọc $failedCount ảnh/video đã chọn'
            : '$failedCount/${selected.length} ảnh/video không đọc được',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
    }
  }

  Widget _buildGalleryPanel(ChatUiConfig config) {
    final primary =
        config.primaryActionColor ?? Theme.of(context).colorScheme.primary;
    return Container(
      height: 320,
      color: config.surfaceColor ?? Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _galleryPermissionDenied
                        ? 'Cần quyền truy cập thư viện ảnh'
                        : 'Ảnh & video trên thiết bị',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_resolvingSelection)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (_selectedAssetIds.isNotEmpty && !_resolvingSelection)
                  TextButton(
                    onPressed: _sendSelectedAssets,
                    child: Text(
                      'Gửi (${_selectedAssetIds.length})',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => setState(() {
                    _showGallery = false;
                    _selectedAssetIds.clear();
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: _galleryLoading
                ? const Center(child: CircularProgressIndicator())
                : _galleryPermissionDenied
                    ? _buildGalleryDeniedView(primary)
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                        itemCount: _galleryAssets.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _galleryAssets.length) {
                            return _buildPickMoreTile(primary);
                          }
                          final asset = _galleryAssets[index];
                          return AssetThumbTile(
                            asset: asset,
                            isSelected: _selectedAssetIds.contains(asset.id),
                            isVideo: asset.type == AssetType.video,
                            duration: asset.videoDuration,
                            onTap: () => _toggleAssetSelection(asset),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  /// Chuyển ảnh HEIC/HEIF sang JPEG bằng engine thumbnail của platform.
  /// Thử theo thứ tự: độ phân giải gốc → nửa phân giải → null (caller tự
  /// fallback về file gốc).
  Future<File?> _convertHeicToJpeg(AssetEntity asset, String fileName) async {
    final width = asset.width > 0 ? asset.width : 4096;
    final height = asset.height > 0 ? asset.height : 3024;
    final attempts = <ThumbnailSize>[
      ThumbnailSize(width, height),
      ThumbnailSize(
          width ~/ 2 == 0 ? 1 : width ~/ 2, height ~/ 2 == 0 ? 1 : height ~/ 2),
    ];
    for (final size in attempts) {
      try {
        developer.log(
          '[ChatModule] HEIC convert $fileName — requesting ${size.width}x${size.height}',
        );
        final jpegData = await asset.thumbnailDataWithSize(
          size,
          format: ThumbnailFormat.jpeg,
          quality: 100,
        );
        if (jpegData != null && jpegData.isNotEmpty) {
          final convFile = File(
            '${Directory.systemTemp.path}/chat_heic_${DateTime.now().millisecondsSinceEpoch}_${asset.id.hashCode}.jpg',
          );
          await convFile.writeAsBytes(jpegData, flush: true);
          developer.log(
            '[ChatModule] HEIC convert OK: ${jpegData.length} bytes',
          );
          return convFile;
        }
        developer.log('[ChatModule] HEIC convert returned empty data');
      } catch (e, st) {
        developer.log('[ChatModule] HEIC convert error',
            error: e, stackTrace: st);
      }
    }
    return null;
  }

  Widget _buildGalleryDeniedView(Color primary) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_library_outlined,
                size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            const Text(
              'Ứng dụng cần quyền truy cập thư viện ảnh để hiển thị ảnh tại đây.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    try {
                      await PhotoManager.openSetting();
                    } catch (_) {
                      // Plugin native chưa đăng ký (thiếu full rebuild) hoặc
                      // nền tảng không hỗ trợ — không văng exception.
                    }
                  },
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Mở cài đặt'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _galleryLoading = true);
                    _loadGalleryAssets();
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Thử lại'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Chọn từ hệ thống'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickMoreTile(Color primary) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _pickImages,
      child: Container(
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: primary.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, color: primary, size: 24),
            const SizedBox(height: 4),
            Text(
              'Chọn thêm',
              style: TextStyle(fontSize: 11, color: primary),
            ),
          ],
        ),
      ),
    );
  }

  // void _showComingSoon(String feature) {
  //   _focusNode.unfocus();
  //   showChatFeatureComingSoon(
  //     context,
  //     feature: feature,
  //     config: ref.read(chatUiConfigProvider),
  //   );
  // }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                    child: _focusNode.hasFocus
                        ? Padding(
                            key: const ValueKey('back_arrow'),
                            padding: const EdgeInsets.only(right: 2),
                            child: _InputIcon(
                              icon: Icons.arrow_back_ios_new_rounded,
                              color: iconColor,
                              onPressed: () {
                                _focusNode.unfocus();
                              },
                            ),
                          )
                        : Row(
                            key: const ValueKey('left_items'),
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
                                onPressed: _openGallery,
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
                          // IconButton(
                          //   tooltip: 'Biểu tượng cảm xúc',
                          //   icon: Icon(Icons.sentiment_satisfied_alt_outlined,
                          //       color: iconColor),
                          //   onPressed: () =>
                          //       _showComingSoon('Biểu tượng cảm xúc'),
                          // ),
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
                        tooltip: hasText ? 'Gửi' : 'Thích',
                        icon: Icon(
                          hasText ? Icons.send : Icons.thumb_up_alt_rounded,
                          color: hasText
                              ? iconColor
                              : (config.primaryActionColor ??
                                  const Color(0xFF0787E8)),
                        ),
                        onPressed: hasText ? _handleSend : _handleSendLike,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: _showGallery
                  ? _buildGalleryPanel(config)
                  : _showAttachmentPanel
                      ? SizedBox(
                          height: 104,
                          child: Row(
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.only(left: 16, top: 8),
                                child: Row(
                                  children: [
                                    // _AttachmentAction(
                                    //   icon: Icons.camera_alt_outlined,
                                    //   label: 'Máy ảnh',
                                    //   color: iconColor,
                                    //   onTap: _takePhoto,
                                    // ),
                                    // const SizedBox(width: 16),
                                    // _AttachmentAction(
                                    //   icon: Icons.photo_library_outlined,
                                    //   label: 'Thư viện',
                                    //   color: iconColor,
                                    //   onTap: _openGallery,
                                    // ),
                                    const SizedBox(width: 16),
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
