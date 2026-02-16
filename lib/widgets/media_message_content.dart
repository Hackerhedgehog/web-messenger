import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/message_model.dart';
import 'media_fullscreen_viewer.dart';

/// Displays media (image or video) inside a message bubble.
/// Videos show first-frame thumbnail with play icon. Tapping opens full-screen viewer.
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
  Uint8List? _videoThumbnailBytes;
  bool _thumbnailFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == MessageMediaType.video) {
      _loadVideoThumbnail();
    }
  }

  Future<void> _loadVideoThumbnail() async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.mediaUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480,
        quality: 75,
      );
      if (mounted) {
        setState(() {
          _videoThumbnailBytes = bytes;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _thumbnailFailed = true);
      }
    }
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
                    child: const Icon(
                      Icons.broken_image,
                      size: 48,
                      color: Colors.white54,
                    ),
                  ),
                )
              : _buildVideoThumbnail(),
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail() {
    if (_videoThumbnailBytes == null && !_thumbnailFailed) {
      return Container(
        color: Colors.grey[800],
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white54,
            strokeWidth: 2,
          ),
        ),
      );
    }
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        if (_videoThumbnailBytes != null)
          Image.memory(
            _videoThumbnailBytes!,
            fit: BoxFit.cover,
            width: widget.maxWidth,
            height: widget.maxHeight,
          )
        else
          Container(color: Colors.grey[800]),
        Container(
          decoration: const BoxDecoration(
            color: Colors.black38,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(12),
          child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
        ),
      ],
    );
  }
}
