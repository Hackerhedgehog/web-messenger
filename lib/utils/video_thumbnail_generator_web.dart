import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'dart:js_interop';

Future<Uint8List?> captureVideoFirstFrame({
  String? localPath,
  Uint8List? bytes,
  String filename = '',
}) async {
  if (bytes == null || bytes.isEmpty) return null;

  final mime = _mimeFromFilename(filename);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final blobUrl = web.URL.createObjectURL(blob);

  final video = web.HTMLVideoElement();
  video.muted = true;
  video.preload = 'auto';
  video.style.cssText = 'display:none;position:absolute;top:-9999px;';
  web.document.body?.appendChild(video);

  try {
    final loadCompleter = Completer<void>();

    video.onloadeddata = ((JSAny? _) {
      if (!loadCompleter.isCompleted) loadCompleter.complete();
    }).toJS;
    video.onerror = ((JSAny? _) {
      if (!loadCompleter.isCompleted) {
        loadCompleter.completeError('Video load error');
      }
    }).toJS;

    video.src = blobUrl;

    await loadCompleter.future.timeout(const Duration(seconds: 15));

    final w = video.videoWidth;
    final h = video.videoHeight;
    if (w == 0 || h == 0) return null;

    final canvas = web.HTMLCanvasElement()
      ..width = w
      ..height = h;

    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) return null;

    ctx.drawImage(video, 0, 0);

    final dataUrl = canvas.toDataURL('image/jpeg', 0.75.toJS);
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;

    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  } finally {
    video.onloadeddata = null;
    video.onerror = null;
    video.remove();
    web.URL.revokeObjectURL(blobUrl);
  }
}

String _mimeFromFilename(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.webm')) return 'video/webm';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.mkv')) return 'video/x-matroska';
  return 'video/mp4';
}
