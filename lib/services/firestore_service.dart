import 'package:cloud_firestore/cloud_firestore.dart';

class _InviteEntry {
  _InviteEntry(this.senderId, this.timestamp);
  final String senderId;
  final Timestamp? timestamp;
}

/// Generates a deterministic connection ID from two user IDs.
String connectionIdFromUsers(String userId1, String userId2) {
  final sorted = [userId1, userId2]..sort();
  return '${sorted[0]}_${sorted[1]}';
}

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

  /// Stream of user profile data. Emits whenever the user document changes.
  Stream<Map<String, dynamic>?> userProfileStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? doc.data() : null);
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

  /// Sends an invite request from [senderUserId] to [receiverUserId].
  /// If receiver already has a pending invite from sender (mutual), creates
  /// connection instead and removes the invite.
  /// Returns 'connected' when mutual connection was created, null otherwise.
  Future<String?> sendInvite({
    required String senderUserId,
    required String receiverUserId,
  }) async {
    try {
      return await _firestore.runTransaction((transaction) async {
        final senderDoc =
            await transaction.get(_firestore.collection('users').doc(senderUserId));
        final senderData = senderDoc.data() ?? {};
        final connections = senderData['connections'];
        final invites = senderData['invites'];
        final alreadyConnected =
            connections is Map && connections.containsKey(receiverUserId);
        final receiverHasInvitedSender =
            invites is Map && invites.containsKey(receiverUserId);

        if (alreadyConnected) {
          throw 'Already connected with this user';
        }
        if (receiverHasInvitedSender) {
          _createConnection(
            transaction: transaction,
            userId1: senderUserId,
            userId2: receiverUserId,
          );
          final connId =
              connectionIdFromUsers(senderUserId, receiverUserId);
          _createConnectionDocument(
            transaction: transaction,
            connectionId: connId,
            userId1: senderUserId,
            userId2: receiverUserId,
          );
          transaction.update(
            _firestore.collection('users').doc(senderUserId),
            {
              'invites.$receiverUserId': FieldValue.delete(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
          return 'connected';
        } else {
          transaction.update(
            _firestore.collection('users').doc(receiverUserId),
            {
              'invites.$senderUserId': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
          return null;
        }
      });
    } catch (e) {
      throw 'Failed to send invite: $e';
    }
  }

  void _createConnection({
    required Transaction transaction,
    required String userId1,
    required String userId2,
  }) {
    final now = FieldValue.serverTimestamp();
    transaction.update(
      _firestore.collection('users').doc(userId1),
      {
        'connections.$userId2': now,
        'updatedAt': now,
      },
    );
    transaction.update(
      _firestore.collection('users').doc(userId2),
      {
        'connections.$userId1': now,
        'updatedAt': now,
      },
    );
  }

  /// Creates the connections/{connectionID} document and participants subcollection.
  /// Structure ready for messaging. Call when a connection is established.
  void _createConnectionDocument({
    required Transaction transaction,
    required String connectionId,
    required String userId1,
    required String userId2,
  }) {
    final now = FieldValue.serverTimestamp();
    final connectionRef =
        _firestore.collection('connections').doc(connectionId);

    transaction.set(connectionRef, {
      'name': '',
      'lastMessage': now,
      'typing': {userId1: false, userId2: false},
    });

    transaction.set(connectionRef.collection('participants').doc(userId1), {
      'isTyping': false,
    });
    transaction.set(connectionRef.collection('participants').doc(userId2), {
      'isTyping': false,
    });
  }

  /// Accepts an invite: removes it from receiver and adds both to connections.
  /// The receiver creates the connections/{connectionID} document for messaging.
  Future<void> acceptInvite({
    required String receiverUserId,
    required String senderUserId,
  }) async {
    try {
      await _firestore.runTransaction((transaction) async {
        _createConnection(
          transaction: transaction,
          userId1: receiverUserId,
          userId2: senderUserId,
        );
        final connId =
            connectionIdFromUsers(receiverUserId, senderUserId);
        _createConnectionDocument(
          transaction: transaction,
          connectionId: connId,
          userId1: receiverUserId,
          userId2: senderUserId,
        );
        transaction.update(
          _firestore.collection('users').doc(receiverUserId),
          {
            'invites.$senderUserId': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      });
    } catch (e) {
      throw 'Failed to accept invite: $e';
    }
  }

  /// Removes an invite when the receiver declines. Removes [senderUserId]
  /// from [receiverUserId]'s invites.
  Future<void> declineInvite({
    required String receiverUserId,
    required String senderUserId,
  }) async {
    try {
      await _firestore.collection('users').doc(receiverUserId).update({
        'invites.$senderUserId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw 'Failed to decline invite: $e';
    }
  }

  /// Stream of invite sender user IDs for the given user, newest first.
  /// Emits whenever invites change. Supports both 'invites' map (with timestamps)
  /// and legacy 'inviteSenders' array (treated as oldest).
  Stream<List<String>> inviteSendersStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return <String>[];
      final data = doc.data() ?? {};

      final entries = <_InviteEntry>[];

      // New format: invites map { senderId: timestamp }
      final invites = data['invites'];
      if (invites is Map) {
        for (final e in invites.entries) {
          final senderId = e.key.toString();
          final ts = e.value is Timestamp ? e.value as Timestamp : null;
          entries.add(_InviteEntry(senderId, ts));
        }
      }

      entries.sort((a, b) {
        if (a.timestamp == null && b.timestamp == null) return 0;
        if (a.timestamp == null) return 1;
        if (b.timestamp == null) return -1;
        return b.timestamp!.compareTo(a.timestamp!);
      });

      return entries.map((e) => e.senderId).toList();
    });
  }

  /// Stream of connected user IDs for the given user, newest first.
  Stream<List<String>> connectionsStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return <String>[];
      final data = doc.data() ?? {};
      final connections = data['connections'];
      if (connections is! Map) return <String>[];

      final entries = <_InviteEntry>[];
      for (final e in connections.entries) {
        final otherId = e.key.toString();
        final ts = e.value is Timestamp ? e.value as Timestamp : null;
        entries.add(_InviteEntry(otherId, ts));
      }
      entries.sort((a, b) {
        if (a.timestamp == null && b.timestamp == null) return 0;
        if (a.timestamp == null) return 1;
        if (b.timestamp == null) return -1;
        return b.timestamp!.compareTo(a.timestamp!);
      });
      return entries.map((e) => e.senderId).toList();
    });
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
