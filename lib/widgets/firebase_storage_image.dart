import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// Renders an image URL, with Firebase Storage SDK fallback for storage links.
///
/// This avoids failures when direct network image loading is blocked by
/// environment constraints (e.g. strict CORS setups on web).
class FirebaseStorageImage extends StatefulWidget {
  const FirebaseStorageImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.maxDownloadBytes = 20 * 1024 * 1024,
    this.errorBuilder,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int maxDownloadBytes;
  final Widget Function(BuildContext context)? errorBuilder;

  @override
  State<FirebaseStorageImage> createState() => _FirebaseStorageImageState();
}

class _FirebaseStorageImageState extends State<FirebaseStorageImage> {
  Future<Uint8List?>? _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytesIfFirebaseStorage(widget.imageUrl);
  }

  @override
  void didUpdateWidget(covariant FirebaseStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _bytesFuture = _loadBytesIfFirebaseStorage(widget.imageUrl);
    }
  }

  Future<Uint8List?> _loadBytesIfFirebaseStorage(String url) async {
    if (!_looksLikeFirebaseStorageUrl(url)) return null;
    final ref = FirebaseStorage.instance.refFromURL(url);
    return ref.getData(widget.maxDownloadBytes);
  }

  bool _looksLikeFirebaseStorageUrl(String url) {
    return url.contains('firebasestorage.googleapis.com') ||
        url.contains('storage.googleapis.com') ||
        url.startsWith('gs://');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: (_, __, ___) =>
                widget.errorBuilder?.call(context) ?? const SizedBox.shrink(),
          );
        }

        return Image.network(
          widget.imageUrl,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, __, ___) =>
              widget.errorBuilder?.call(context) ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
