import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/message_model.dart';

/// Full-screen overlay for viewing media (image or video).
class MediaFullscreenViewer extends StatefulWidget {
  const MediaFullscreenViewer({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
  });

  final String mediaUrl;
  final MessageMediaType mediaType;

  @override
  State<MediaFullscreenViewer> createState() => _MediaFullscreenViewerState();
}

class _MediaFullscreenViewerState extends State<MediaFullscreenViewer> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == MessageMediaType.video) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrl))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _videoController!.play();
          }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: widget.mediaType == MessageMediaType.image
                ? InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.network(
                      widget.mediaUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        size: 64,
                        color: Colors.white54,
                      ),
                    ),
                  )
                : _buildVideoPlayer(),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (!_videoController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          _videoController!.value.isPlaying
              ? _videoController!.pause()
              : _videoController!.play();
        });
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      ),
    );
  }
}
