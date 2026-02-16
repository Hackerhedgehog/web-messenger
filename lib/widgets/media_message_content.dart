import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/message_model.dart';
import 'media_fullscreen_viewer.dart';

/// Displays media (image or video) inside a message bubble.
/// Tapping opens full-screen viewer.
class MediaMessageContent extends StatefulWidget {
  const MediaMessageContent({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
    this.maxWidth = 240,
    this.maxHeight = 200,
  });

  final String mediaUrl;
  final MessageMediaType mediaType;
  final double maxWidth;
  final double maxHeight;

  @override
  State<MediaMessageContent> createState() => _MediaMessageContentState();
}

class _MediaMessageContentState extends State<MediaMessageContent> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == MessageMediaType.video) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrl))
        ..initialize().then((_) {
          if (mounted) setState(() {});
        }).catchError((_) {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _openFullScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MediaFullscreenViewer(
          mediaUrl: widget.mediaUrl,
          mediaType: widget.mediaType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openFullScreen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: widget.maxWidth,
          height: widget.maxHeight,
          child: widget.mediaType == MessageMediaType.image
              ? Image.network(
                  widget.mediaUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[800],
                    child: const Icon(Icons.broken_image, size: 48, color: Colors.white54),
                  ),
                )
              : _buildVideoThumbnail(),
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container(
        color: Colors.grey[800],
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
        ),
      );
    }
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.black26,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(12),
          child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
        ),
      ],
    );
  }
}
