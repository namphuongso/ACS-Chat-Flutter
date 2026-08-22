import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ChatVideoPlayerDialog extends StatefulWidget {
  const ChatVideoPlayerDialog({
    super.key,
    required this.url,
    this.title,
  });

  final String url;
  final String? title;

  static Future<void> show(BuildContext context,
      {required String url, String? title}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ChatVideoPlayerDialog(url: url, title: title),
    );
  }

  @override
  State<ChatVideoPlayerDialog> createState() => _ChatVideoPlayerDialogState();
}

class _ChatVideoPlayerDialogState extends State<ChatVideoPlayerDialog> {
  VideoPlayerController? _controller;
  bool _isInitializing = true;
  String? _errorMessage;
  bool _isPlaying = false;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Uri? _resolveUrl() {
    final raw = widget.url.trim();
    if (raw.isEmpty) return null;
    return Uri.tryParse(raw) ?? Uri.tryParse(Uri.encodeFull(raw));
  }

  Future<void> _initVideo() async {
    final uri = _resolveUrl();
    if (uri == null) {
      if (mounted) {
        setState(() {
          _errorMessage = 'URL video không hợp lệ';
          _isInitializing = false;
        });
      }
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_videoListener);
      setState(() {
        _isInitializing = false;
      });
      await controller.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Không thể tải video: $e';
          _isInitializing = false;
        });
      }
    }
  }

  void _videoListener() {
    if (!mounted || _controller == null) return;
    final isPlaying = _controller!.value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() {
        _isPlaying = isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
  }

  void _toggleMute() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0 : 1);
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final maxDialogWidth = screenSize.width * 0.94;
    final maxDialogHeight = screenSize.height * 0.82;

    final controller = _controller;
    double videoRatio = 16 / 9;
    if (controller != null && controller.value.isInitialized) {
      final raw = controller.value.aspectRatio;
      if (raw > 0 && !raw.isNaN && !raw.isInfinite) {
        videoRatio = raw;
      }
    }

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxDialogWidth,
          maxHeight: maxDialogHeight,
        ),
        child: AspectRatio(
          aspectRatio: videoRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_isInitializing)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              else if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 40),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else if (controller != null && controller.value.isInitialized)
                GestureDetector(
                  onTap: _togglePlay,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: controller.value.size.width,
                            height: controller.value.size.height,
                            child: VideoPlayer(controller),
                          ),
                        ),
                      ),
                      if (!_isPlaying)
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(12),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                    ],
                  ),
                ),

              // Top Bar Overlay
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black87, Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title ?? 'Video',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 22),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Controls Bar Overlay
              if (controller != null && controller.value.isInitialized)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black87],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: _togglePlay,
                        ),
                        Text(
                          _formatDuration(controller.value.position),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                        Expanded(
                          child: VideoProgressIndicator(
                            controller,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            colors: const VideoProgressColors(
                              playedColor: Color(0xFF0787E8),
                              bufferedColor: Colors.white30,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ),
                        Text(
                          _formatDuration(controller.value.duration),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                        IconButton(
                          icon: Icon(
                            _isMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: _toggleMute,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
