import 'dart:typed_data';

import 'package:video_thumbnail/video_thumbnail.dart';

Future<Uint8List?> captureVideoFirstFrame({
  String? localPath,
  Uint8List? bytes,
  String filename = '',
}) async {
  if (localPath == null) return null;
  try {
    return await VideoThumbnail.thumbnailData(
      video: localPath,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 480,
      quality: 75,
    );
  } catch (_) {
    return null;
  }
}
