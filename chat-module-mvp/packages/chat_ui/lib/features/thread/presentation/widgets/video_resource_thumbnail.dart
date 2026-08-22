import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Component tự động tạo thumbnail (khung hình đầu tiên) cho video
/// khi server trả về `thumbUrl` trùng với URL file video (`.mov`, `.mp4`).
class VideoResourceThumbnail extends StatefulWidget {
  const VideoResourceThumbnail({
    super.key,
    required this.videoUrl,
    this.fit = BoxFit.cover,
  });

  final String videoUrl;
  final BoxFit fit;

  @override
  State<VideoResourceThumbnail> createState() => _VideoResourceThumbnailState();
}

class _VideoResourceThumbnailState extends State<VideoResourceThumbnail> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initThumbnail();
  }

  @override
  void didUpdateWidget(VideoResourceThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _disposeController();
      _initThumbnail();
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
    _hasError = false;
  }

  Uri? _resolveUrl() {
    final raw = widget.videoUrl.trim();
    if (raw.isEmpty) return null;
    return Uri.tryParse(raw) ?? Uri.tryParse(Uri.encodeFull(raw));
  }

  Future<void> _initThumbnail() async {
    final uri = _resolveUrl();
    if (uri == null) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;

    try {
      await controller.initialize().timeout(const Duration(seconds: 10));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final duration = controller.value.duration;
      await controller.seekTo(
        duration > const Duration(milliseconds: 200)
            ? const Duration(milliseconds: 100)
            : Duration.zero,
      );
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialized && _controller != null) {
      final size = _controller!.value.size;
      final width = size.width > 0 ? size.width : 100.0;
      final height = size.height > 0 ? size.height : 100.0;

      return FittedBox(
        fit: widget.fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: width,
          height: height,
          child: VideoPlayer(_controller!),
        ),
      );
    }

    return Container(
      color: const Color(0xFF1D2939),
      child: Center(
        child: _hasError
            ? const Icon(Icons.videocam_off_rounded,
                color: Colors.white54, size: 24)
            : const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
      ),
    );
  }
}
