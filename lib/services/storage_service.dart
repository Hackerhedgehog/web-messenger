import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Max size per message media: 10MB.
const int kMaxMessageMediaBytes = 10 * 1024 * 1024;

/// Service for uploading files to Firebase Storage.
/// Supports Android (File) and Web (bytes from XFile).
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads a profile picture and returns the download URL and storage path.
  /// [image] - The picked image from image_picker.
  /// [userId] - The user's ID, used as part of the storage path.
  /// Supports PNG and JPEG formats.
  Future<({String url, String path})> uploadProfilePicture({
    required XFile image,
    required String userId,
  }) async {
    final bytes = await image.readAsBytes();
    final name = image.name;
    final extension = _getExtension(name);
    if (extension == null || !_isSupportedImageFormat(extension)) {
      throw 'Unsupported image format. Please use PNG or JPEG.';
    }

    final path = 'profile_pictures/$userId$extension';
    final ref = _storage.ref().child(path);

    await ref.putData(
      bytes,
      SettableMetadata(contentType: _getContentType(extension)),
    );

    final url = await ref.getDownloadURL();
    return (url: url, path: path);
  }

  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      default:
        return 'image/jpeg';
    }
  }

  String? _getExtension(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot == -1) return null;
    return filename.substring(lastDot);
  }

  bool _isSupportedImageFormat(String extension) {
    final ext = extension.toLowerCase();
    return ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.gif';
  }

  bool _isSupportedVideoFormat(String extension) {
    final ext = extension.toLowerCase();
    return ext == '.mp4' || ext == '.mov' || ext == '.webm' || ext == '.mkv';
  }

  bool _isSupportedMediaFormat(String extension) {
    return _isSupportedImageFormat(extension) ||
        _isSupportedVideoFormat(extension);
  }

  String _getMediaContentType(String extension) {
    switch (extension.toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
      case '.mkv':
        return 'video/x-matroska';
      default:
        return 'application/octet-stream';
    }
  }

  /// Uploads message media from raw bytes (e.g. from file_picker).
  /// Path: connections/{connectionId}/messages/{messageId}/media{extension}
  Future<({String url, String path})> uploadMessageMediaFromBytes({
    required List<int> bytes,
    required String filename,
    required String connectionId,
    required String messageId,
  }) async {
    if (bytes.length > kMaxMessageMediaBytes) {
      throw 'File exceeds 10MB limit. Please choose a smaller file.';
    }
    final extension = _getExtension(filename);
    if (extension == null || !_isSupportedMediaFormat(extension)) {
      throw 'Unsupported format. Use images (PNG, JPEG) or videos (MP4, MOV, WebM, MKV).';
    }
    final path =
        'connections/$connectionId/messages/$messageId/media$extension';
    final ref = _storage.ref().child(path);
    await ref.putData(
      Uint8List.fromList(bytes),
      SettableMetadata(contentType: _getMediaContentType(extension)),
    );
    final url = await ref.getDownloadURL();
    return (url: url, path: path);
  }

  /// Uploads message media (image or video) to Firebase Storage.
  /// Path: connections/{connectionId}/messages/{messageId}/media{extension}
  /// Throws if file exceeds [kMaxMessageMediaBytes] (10MB).
  Future<({String url, String path})> uploadMessageMedia({
    required XFile file,
    required String connectionId,
    required String messageId,
  }) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > kMaxMessageMediaBytes) {
      throw 'File exceeds 10MB limit. Please choose a smaller file.';
    }

    final name = file.name;
    final extension = _getExtension(name);
    if (extension == null || !_isSupportedMediaFormat(extension)) {
      throw 'Unsupported format. Use images (PNG, JPEG) or videos (MP4, MOV, WebM, MKV).';
    }

    final path =
        'connections/$connectionId/messages/$messageId/media$extension';
    final ref = _storage.ref().child(path);

    await ref.putData(
      bytes,
      SettableMetadata(contentType: _getMediaContentType(extension)),
    );

    final url = await ref.getDownloadURL();
    return (url: url, path: path);
  }

  /// Deletes message media from Storage by its path.
  /// Silently ignores errors (e.g. file not found).
  Future<void> deleteMessageMediaByPath(String? path) async {
    if (path == null || path.isEmpty) return;

    try {
      final ref = _storage.ref().child(path);
      await ref.delete();
    } catch (_) {
      // Ignore - file may not exist
    }
  }

  /// Deletes a profile picture from Storage by its download URL, but only if
  /// it is at a different path than [currentPath]. Use this when replacing a
  /// profile picture: same path means we overwrote the file, so we must not
  /// delete. Different path (e.g. .png vs .jpg) means the old file is orphaned.
  Future<void> deleteProfilePictureByUrlIfPathDifferent(
    String? url,
    String currentPath,
  ) async {
    if (url == null || url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;

    try {
      final ref = _storage.refFromURL(url);
      if (ref.fullPath != currentPath) {
        await ref.delete();
      }
    } catch (_) {
      // Ignore - file may not exist or URL may be invalid
    }
  }

  /// Deletes a profile picture from Storage by its download URL.
  /// Silently ignores errors (e.g. file not found, invalid URL).
  Future<void> deleteProfilePictureByUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;

    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (_) {
      // Ignore - file may not exist or URL may be invalid
    }
  }
}
