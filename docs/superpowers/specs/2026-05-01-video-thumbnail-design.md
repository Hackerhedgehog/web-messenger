# Video Thumbnail in Message Bubbles

**Date:** 2026-05-01
**Status:** Approved

## Problem

Video messages show a dark grey box with a play icon in the message bubble. The `video_thumbnail` package used in `MediaMessageContent` to extract a first frame at render time does not support Flutter Web, so on web the extraction always fails silently and no thumbnail is shown.

## Goal

Show the first frame of a video as a thumbnail image inside the message bubble, with a play button overlay, on both Web and Android.

## Approach

Generate the thumbnail once at send time, upload it to Firebase Storage, and persist its URL in Firestore alongside the video URL. The display widget loads a static JPEG URL — identical behaviour on all platforms, no async video processing at render time.

## Architecture

### Thumbnail generation (upload time, platform-conditional)

Three files using Dart's conditional export pattern:

- `lib/utils/video_thumbnail_generator.dart` — re-exports the correct implementation:
  ```dart
  export 'video_thumbnail_generator_io.dart'
      if (dart.library.js_interop) 'video_thumbnail_generator_web.dart';
  ```
- `lib/utils/video_thumbnail_generator_io.dart` — Android: calls `VideoThumbnail.thumbnailData(video: localPath)` from the existing `video_thumbnail` dependency.
- `lib/utils/video_thumbnail_generator_web.dart` — Web: creates a hidden `<video>` element from a blob URL built from the file bytes, seeks to t=0, draws to `<canvas>`, returns JPEG bytes via `canvas.toDataURL()` decoded from base64. Uses `package:web`.

Shared function signature (both platform files export this):
```dart
Future<Uint8List?> captureVideoFirstFrame({
  String? localPath,   // Android: path from XFile
  Uint8List? bytes,    // Web: raw file bytes
  String filename = '', // Web: used to set blob MIME type
});
```

### Data model

`Message` (in `lib/models/message_model.dart`) gains two new optional fields:
- `thumbnailUrl: String?` — Firebase Storage download URL for the thumbnail JPEG
- `thumbnailPath: String?` — Storage path used for cleanup on message delete

`Message.fromFirestore()`, `copyWith()`, and the constructor all updated accordingly.

### Storage

`StorageService` gains `uploadVideoThumbnail({required Uint8List bytes, required String connectionId, required String messageId})` that:
- Uploads to `connections/{connectionId}/messages/{messageId}/thumbnail.jpg`
- Returns `({String url, String path})`

### Firestore

`FirestoreService.sendMessage()` gains two new optional params — `thumbnailUrl` and `thumbnailPath` — written into the Firestore document only when non-null (same pattern as existing `mediaUrl`/`mediaPath`).

### Upload flow (`chat_screen.dart`)

In `_pickAndSendMedia()`, after uploading the video and before calling `sendMessage()`:

1. Detect `mediaType == MessageMediaType.video`
2. Call `captureVideoFirstFrame()`:
   - Android: `localPath: xFile.path`
   - Web: `bytes: bytes, filename: filename`
3. If bytes returned are non-null, call `_storageService.uploadVideoThumbnail()`
4. Pass `thumbnailUrl` + `thumbnailPath` into `sendMessage()`

Thumbnail failure (generation or upload) is fully non-blocking — the message sends anyway without a thumbnail.

### Display widget (`MediaMessageContent`)

Gains an optional `thumbnailUrl: String?` parameter.

For video messages:
- **`thumbnailUrl != null`**: render `FirebaseStorageImage(thumbnailUrl)` with a play button overlay. No async state, no `video_thumbnail` call.
- **`thumbnailUrl == null`**: render the existing dark-box + play icon fallback (covers old messages).

`_loadVideoThumbnail()`, `_videoThumbnailBytes`, and `_thumbnailFailed` are removed.

Call site in `chat_screen.dart` passes `thumbnailUrl: msg.thumbnailUrl` to `MediaMessageContent`.

### Dependency

`package:web` added to `pubspec.yaml` for web DOM API access in the web thumbnail generator.

## Files Changed

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `package:web` |
| `lib/utils/video_thumbnail_generator.dart` | New — conditional export |
| `lib/utils/video_thumbnail_generator_io.dart` | New — Android impl |
| `lib/utils/video_thumbnail_generator_web.dart` | New — Web impl |
| `lib/models/message_model.dart` | Add `thumbnailUrl`, `thumbnailPath` |
| `lib/services/firestore_service.dart` | Add params to `sendMessage()` |
| `lib/services/storage_service.dart` | Add `uploadVideoThumbnail()` |
| `lib/screens/chat_screen.dart` | Generate + upload thumbnail in `_pickAndSendMedia()` |
| `lib/widgets/media_message_content.dart` | Use `thumbnailUrl`, remove runtime generation |

## Error Handling

- Thumbnail generation or upload failure: caught silently, message sends without thumbnail.
- `thumbnailUrl == null` on old messages: dark box + play icon (no migration needed).
- Canvas draw fails on web (e.g. codec unsupported): returns `null`, falls through to no-thumbnail path.

## Out of Scope

- Retroactively generating thumbnails for existing video messages.
- Deleting the thumbnail file when a message is deleted (the `thumbnailPath` field is stored so this can be added later).
