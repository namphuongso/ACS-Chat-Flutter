import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class AssetThumbTile extends StatefulWidget {
  const AssetThumbTile({
    super.key,
    required this.asset,
    required this.isSelected,
    required this.isVideo,
    required this.duration,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool isSelected;
  final bool isVideo;
  final Duration duration;
  final VoidCallback onTap;

  @override
  State<AssetThumbTile> createState() => _AssetThumbTileState();
}

class _AssetThumbTileState extends State<AssetThumbTile> {
  Uint8List? _thumb;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    try {
      final data = await widget.asset
          .thumbnailDataWithSize(const ThumbnailSize(200, 200));
      if (!mounted) return;
      setState(() => _thumb = data);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _thumb != null
                ? Image.memory(_thumb!, fit: BoxFit.cover)
                : Container(
                    color: Colors.grey.shade300,
                    child: _failed
                        ? const Icon(Icons.broken_image, color: Colors.grey)
                        : const SizedBox.shrink(),
                  ),
          ),
          if (widget.isVideo)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, size: 12, color: Colors.white),
                    const SizedBox(width: 2),
                    Text(
                      formatMediaDuration(widget.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.isSelected)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: const Color(0xFF0787E8).withValues(alpha: 0.25),
                  padding: const EdgeInsets.all(4),
                  alignment: Alignment.topRight,
                  child: const CircleAvatar(
                    radius: 10,
                    backgroundColor: Color(0xFF0787E8),
                    child: Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String formatMediaDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    return '${duration.inHours}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
