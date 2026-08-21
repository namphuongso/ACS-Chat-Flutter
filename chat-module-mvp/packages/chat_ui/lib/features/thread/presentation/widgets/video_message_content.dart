import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoMessageContent extends StatefulWidget {
  const VideoMessageContent({
    super.key,
    required this.url,
    required this.fileName,
    required this.textColor,
  });

  final String url;
  final String fileName;
  final Color textColor;

  @override
  State<VideoMessageContent> createState() => _VideoMessageContentState();
}

class _VideoMessageContentState extends State<VideoMessageContent> {
  static const double _width = 200;
  static final Map<String, VideoPlayerController> _controllerCache = {};
  static final Map<String, Future<void>> _initFuturesCache = {};

  VideoPlayerController? _controller;
  bool _initializing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.url.isNotEmpty) _initPlayer();
  }

  @override
  void didUpdateWidget(VideoMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && widget.url.isNotEmpty) {
      _initPlayer();
    }
  }

  Uri? _resolveVideoUrl() {
    final raw = widget.url.trim();
    if (raw.isEmpty) return null;
    return Uri.tryParse(raw) ?? Uri.tryParse(Uri.encodeFull(raw));
  }

  Future<void> _initPlayer() async {
    if (_initializing) return;
    final uri = _resolveVideoUrl();
    if (uri == null) {
      if (mounted) setState(() => _errorMessage = 'URL video không hợp lệ.');
      return;
    }

    final cacheKey = uri.toString();

    final cached = _controllerCache[cacheKey];
    if (cached != null && cached.value.isInitialized) {
      _controller?.removeListener(_onPlayerUpdate);
      _controller = cached;
      _controller!.addListener(_onPlayerUpdate);
      if (mounted) {
        setState(() {
          _initializing = false;
          _errorMessage = null;
        });
      }
      return;
    }

    if (_initFuturesCache.containsKey(cacheKey)) {
      if (mounted) setState(() => _initializing = true);
      await _initFuturesCache[cacheKey];
      final freshlyInit = _controllerCache[cacheKey];
      if (freshlyInit != null && freshlyInit.value.isInitialized) {
        _controller?.removeListener(_onPlayerUpdate);
        _controller = freshlyInit;
        _controller!.addListener(_onPlayerUpdate);
      }
      if (mounted) {
        setState(() {
          _initializing = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _initializing = true;
        _errorMessage = null;
      });
    }

    final controller = VideoPlayerController.networkUrl(uri);
    final initFuture = _initializeControllerInternal(controller, cacheKey);
    _initFuturesCache[cacheKey] = initFuture;
    await initFuture;
    _initFuturesCache.remove(cacheKey);

    if (mounted) {
      setState(() {
        _initializing = false;
      });
    }
  }

  Future<void> _initializeControllerInternal(
    VideoPlayerController controller,
    String cacheKey,
  ) async {
    try {
      await controller.initialize();
      controller.setLooping(false);
      _controllerCache[cacheKey] = controller;
      _controller?.removeListener(_onPlayerUpdate);
      _controller = controller;
      _controller!.addListener(_onPlayerUpdate);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Không thể phát video';
        });
      }
      await controller.dispose();
    }
  }

  void _onPlayerUpdate() {
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
    });
    _initPlayer();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return SizedBox(
        width: _width,
        height: 140,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _buildErrorBody(),
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return SizedBox(
        width: _width,
        height: 140,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: Colors.black12,
            child: Center(
              child: _initializing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.videocam, color: Colors.grey, size: 36),
            ),
          ),
        ),
      );
    }

    final isPlaying = controller.value.isPlaying;
    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : (16 / 9);

    return Container(
      width: _width,
      margin: const EdgeInsets.only(bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: _togglePlay,
          child: AspectRatio(
            aspectRatio: aspectRatio.clamp(0.6, 2.2),
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(controller),
                if (!isPlaying) Container(color: Colors.black26),
                Center(
                  child: Icon(
                    isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                    size: 56,
                    color: Colors.white.withValues(alpha: 0.92),
                    shadows: const [Shadow(color: Colors.black38, blurRadius: 8)],
                  ),
                ),
                if (isPlaying)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 8,
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBody([String? message]) {
    final detail = message ?? _errorMessage;
    return GestureDetector(
      onTap: widget.url.isEmpty ? null : _retry,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, color: Colors.white54, size: 26),
            const SizedBox(height: 4),
            Text(
              widget.fileName,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 4),
            const Text(
              'Chạm để thử lại',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
