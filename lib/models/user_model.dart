import 'package:cloud_firestore/cloud_firestore.dart';

class User {
  final String userId;
  final String email;
  final String username;
  final String? profilePictureUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic>? additionalData;

  User({
    required this.userId,
    required this.email,
    required this.username,
    this.profilePictureUrl,
    this.createdAt,
    this.updatedAt,
    this.additionalData,
  });

  // Factory constructor to create User from Firestore document data
  factory User.fromFirestore(Map<String, dynamic> data, String userId) {
    return User(
      userId: userId,
      email: data['email'] as String? ?? '',
      username: data['username'] as String? ?? '',
      profilePictureUrl: data['profilePictureUrl'] as String?,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      additionalData: _extractAdditionalData(data),
    );
  }

  // Helper method to extract additional fields not in the base model
  static Map<String, dynamic>? _extractAdditionalData(
    Map<String, dynamic> data,
  ) {
    final baseFields = {
      'email',
      'username',
      'profilePictureUrl',
      'createdAt',
      'updatedAt',
    };
    final additional = <String, dynamic>{};

    for (final entry in data.entries) {
      if (!baseFields.contains(entry.key)) {
        additional[entry.key] = entry.value;
      }
    }

    return additional.isEmpty ? null : additional;
  }

  // Convert User to Map for easy serialization
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'email': email,
      'username': username,
      'profilePictureUrl': profilePictureUrl,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      if (additionalData != null) ...additionalData!,
    };
  }
}
