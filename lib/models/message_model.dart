import 'package:cloud_firestore/cloud_firestore.dart';

/// Type of media attached to a message.
enum MessageMediaType {
  image,
  video,
}

MessageMediaType? mediaTypeFromFilename(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif')) {
    return MessageMediaType.image;
  }
  if (lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mkv')) {
    return MessageMediaType.video;
  }
  return null;
}

class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.mediaUrl,
    this.mediaPath,
    this.mediaType,
  });

  final String id;
  final String senderId;
  final String text;
  final DateTime createdAt;
  /// Download URL for media (image or video) in Firebase Storage.
  final String? mediaUrl;
  /// Storage path for media, used when deleting unreferenced files.
  final String? mediaPath;
  final MessageMediaType? mediaType;

  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;

  Message copyWith({
    String? id,
    String? senderId,
    String? text,
    DateTime? createdAt,
    String? mediaUrl,
    String? mediaPath,
    MessageMediaType? mediaType,
    bool clearMedia = false,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      mediaUrl: clearMedia ? null : (mediaUrl ?? this.mediaUrl),
      mediaPath: clearMedia ? null : (mediaPath ?? this.mediaPath),
      mediaType: clearMedia ? null : (mediaType ?? this.mediaType),
    );
  }

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final createdAt = data['createdAt'];
    final mediaTypeStr = data['mediaType'] as String?;
    MessageMediaType? mediaType;
    if (mediaTypeStr == 'image') {
      mediaType = MessageMediaType.image;
    } else if (mediaTypeStr == 'video') {
      mediaType = MessageMediaType.video;
    }
    return Message(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.now(),
      mediaUrl: data['mediaUrl'] as String?,
      mediaPath: data['mediaPath'] as String?,
      mediaType: mediaType,
    );
  }
}
