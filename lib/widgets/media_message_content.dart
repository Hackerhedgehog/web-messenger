import 'package:flutter/material.dart';

import '../models/message_model.dart';
import 'firebase_storage_image.dart';
import 'media_fullscreen_viewer.dart';

/// Displays media (image or video) inside a message bubble.
/// Videos show a pre-generated thumbnail with a play icon. Tapping opens the full-screen viewer.
class MediaMessageContent extends StatelessWidget {
  const MediaMessageContent({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
    this.thumbnailUrl,
    this.maxWidth = 240,
    this.maxHeight = 200,
  });

  final String mediaUrl;
  final MessageMediaType mediaType;
  final String? thumbnailUrl;
  final double maxWidth;
  final double maxHeight;

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MediaFullscreenViewer(
          mediaUrl: mediaUrl,
          mediaType: mediaType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: maxWidth,
          height: maxHeight,
          child: mediaType == MessageMediaType.image
              ? FirebaseStorageImage(
                  imageUrl: mediaUrl,
                  width: maxWidth,
                  height: maxHeight,
                  fit: BoxFit.cover,
                  errorBuilder: (_) => Container(
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
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        if (thumbnailUrl != null)
          FirebaseStorageImage(
            imageUrl: thumbnailUrl!,
            width: maxWidth,
            height: maxHeight,
            fit: BoxFit.cover,
            errorBuilder: (_) => Container(color: Colors.grey[800]),
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
