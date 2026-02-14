import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create user profile in Firestore
  Future<void> createUserProfile({
    required String userId,
    required String email,
    required String username,
    String? profilePictureUrl,
  }) async {
    try {
      final data = <String, dynamic>{
        'email': email,
        'username': username,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
        data['profilePictureUrl'] = profilePictureUrl;
      }
      await _firestore.collection('users').doc(userId).set(data);
    } catch (e) {
      throw 'Failed to create user profile: $e';
    }
  }

  // Get user profile
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      throw 'Failed to get user profile: $e';
    }
  }

  // Update user profile
  Future<void> updateUserProfile({
    required String userId,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        ...?data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw 'Failed to update user profile: $e';
    }
  }

  // Find user by username or email (exact match)
  Future<Map<String, dynamic>?> findUserByUsernameOrEmail(
    String usernameOrEmail,
  ) async {
    try {
      final query = await _firestore
          .collection('users')
          .where(
            Filter.or(
              Filter('username', isEqualTo: usernameOrEmail),
              Filter('email', isEqualTo: usernameOrEmail),
            ),
          )
          .limit(1)
          .get();
      if (query.docs.isEmpty) return null;
      final doc = query.docs.first;
      return {'userId': doc.id, ...doc.data()};
    } catch (e) {
      throw 'Failed to find user by username or email: $e';
    }
  }

  // Check if username is available
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      return query.docs.isEmpty;
    } catch (e) {
      throw 'Failed to check username availability: $e';
    }
  }

  // Delete user profile from Firestore
  Future<void> deleteUserProfile(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).delete();
    } catch (e) {
      throw 'Failed to delete user profile: $e';
    }
  }
}
