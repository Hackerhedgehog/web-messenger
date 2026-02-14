import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Service for uploading files to Firebase Storage.
/// Supports Android (File) and Web (bytes from XFile).
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads a profile picture and returns the download URL.
  /// [image] - The picked image from image_picker.
  /// [userId] - The user's ID, used as part of the storage path.
  /// Supports PNG and JPEG formats.
  Future<String> uploadProfilePicture({
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

    return ref.getDownloadURL();
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
}
