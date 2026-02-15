import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

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
    return ext == '.png' || ext == '.jpg' || ext == '.jpeg';
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
