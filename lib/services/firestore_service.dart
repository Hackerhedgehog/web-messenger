import 'dart:math';

import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/connection_info.dart';
import '../models/group_invite_info.dart';
import '../models/message_model.dart';
import 'storage_service.dart';

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
  final StorageService _storageService = StorageService();

  // Create user profile in Firestore
  Future<void> createUserProfile({
    required String userId,
    required String email,
    required String username,
    String? profilePictureUrl,
    String? bio,
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
      if (bio != null && bio.trim().isNotEmpty) {
        data['bio'] = bio.trim();
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

  /// Fetches usernames for the given user IDs. Returns userId -> username map.
  Future<Map<String, String>> getUsernamesForUsers(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    try {
      final results = await Future.wait(
        userIds.map((id) => _firestore.collection('users').doc(id).get()),
      );
      final map = <String, String>{};
      for (var i = 0; i < userIds.length; i++) {
        final data = results[i].data();
        map[userIds[i]] = data?['username'] as String? ?? userIds[i];
      }
      return map;
    } catch (e) {
      return {for (final id in userIds) id: id};
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

  /// Returns true if [username] can be used by [userId] (available or already theirs).
  Future<bool> isUsernameAvailableForUser(
    String username,
    String userId,
  ) async {
    final available = await isUsernameAvailable(username);
    if (available) return true;
    final existing = await _firestore
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    return existing.docs.isNotEmpty && existing.docs.first.id == userId;
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
        final senderDoc = await transaction.get(
          _firestore.collection('users').doc(senderUserId),
        );
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
          final connId = connectionIdFromUsers(senderUserId, receiverUserId);
          _createConnectionDocument(
            transaction: transaction,
            connectionId: connId,
            userId1: senderUserId,
            userId2: receiverUserId,
          );
          transaction.update(_firestore.collection('users').doc(senderUserId), {
            'invites.$receiverUserId': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return 'connected';
        } else {
          transaction
              .update(_firestore.collection('users').doc(receiverUserId), {
                'invites.$senderUserId': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
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
    transaction.update(_firestore.collection('users').doc(userId1), {
      'connections.$userId2': now,
      'updatedAt': now,
    });
    transaction.update(_firestore.collection('users').doc(userId2), {
      'connections.$userId1': now,
      'updatedAt': now,
    });
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
    final connectionRef = _firestore
        .collection('connections')
        .doc(connectionId);

    transaction.set(connectionRef, {'name': '', 'lastMessage': now});

    transaction.set(connectionRef.collection('participants').doc(userId1), {
      'lastSeen': now,
    });
    transaction.set(connectionRef.collection('participants').doc(userId2), {
      'lastSeen': now,
    });
  }

  /// Updates the participant's lastSeen timestamp. Call when user opens a chat
  /// or when they receive/send a message while the chat is open.
  Future<void> updateParticipantLastSeen({
    required String connectionId,
    required String userId,
  }) async {
    try {
      await _firestore
          .collection('connections')
          .doc(connectionId)
          .collection('participants')
          .doc(userId)
          .set({
            'lastSeen': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      // Silently ignore - participant may have left the connection
    }
  }

  /// Updates the participant's lastTyping timestamp. Call when user types in
  /// the chat input. Client should throttle to only call when last update was
  /// more than 5 seconds ago.
  Future<void> updateParticipantLastTyping({
    required String connectionId,
    required String userId,
  }) async {
    try {
      await _firestore
          .collection('connections')
          .doc(connectionId)
          .collection('participants')
          .doc(userId)
          .set({
            'lastTyping': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      // Silently ignore - participant may have left the connection
    }
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
        final connId = connectionIdFromUsers(receiverUserId, senderUserId);
        _createConnectionDocument(
          transaction: transaction,
          connectionId: connId,
          userId1: receiverUserId,
          userId2: senderUserId,
        );
        transaction.update(_firestore.collection('users').doc(receiverUserId), {
          'invites.$senderUserId': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
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

  /// Stream of all invites (1:1 and group) for the Invites tab.
  /// Uses single invites map: keys are senderId (1:1) or groupId (group).
  /// Group IDs start with "group_". Sorted by timestamp (newest first).
  Stream<({List<String> senderIds, List<GroupInviteInfo> groupInvites})>
  allInvitesStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().asyncMap((
      doc,
    ) async {
      if (!doc.exists) {
        return (senderIds: <String>[], groupInvites: <GroupInviteInfo>[]);
      }
      final data = doc.data() ?? {};
      final invites = data['invites'];
      if (invites is! Map) {
        return (senderIds: <String>[], groupInvites: <GroupInviteInfo>[]);
      }

      final inviteEntries = <_InviteEntry>[];
      final groupEntries = <MapEntry<String, Timestamp?>>[];

      for (final e in invites.entries) {
        final key = e.key.toString();
        final ts = e.value is Timestamp ? e.value as Timestamp : null;
        if (key.startsWith('group_')) {
          groupEntries.add(MapEntry(key, ts));
        } else {
          inviteEntries.add(_InviteEntry(key, ts));
        }
      }

      inviteEntries.sort((a, b) {
        if (a.timestamp == null && b.timestamp == null) return 0;
        if (a.timestamp == null) return 1;
        if (b.timestamp == null) return -1;
        return b.timestamp!.compareTo(a.timestamp!);
      });
      final senderIds = inviteEntries.map((e) => e.senderId).toList();

      final groupInvites = <GroupInviteInfo>[];
      for (final e in groupEntries) {
        final groupId = e.key;
        final ts = e.value;
        try {
          final connDoc = await _firestore
              .collection('connections')
              .doc(groupId)
              .get();
          if (connDoc.exists) {
            final connData = connDoc.data() ?? {};
            groupInvites.add(
              GroupInviteInfo.fromConnection(groupId, connData, ts),
            );
          }
        } catch (_) {
          // Skip if connection not found
        }
      }
      groupInvites.sort((a, b) {
        final ta = a.timestamp;
        final tb = b.timestamp;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

      return (senderIds: senderIds, groupInvites: groupInvites);
    });
  }

  /// Stream of total invite count (1:1 + group) for badge display.
  /// Both stored in invites map.
  Stream<int> totalInviteCountStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return 0;
      final data = doc.data() ?? {};
      final invites = data['invites'];
      return invites is Map ? invites.length : 0;
    });
  }

  /// Stream of invite sender user IDs for the given user, newest first.
  /// Excludes group invites (keys starting with "group_").
  Stream<List<String>> inviteSendersStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return <String>[];
      final data = doc.data() ?? {};
      final entries = <_InviteEntry>[];
      final invites = data['invites'];
      if (invites is Map) {
        for (final e in invites.entries) {
          final key = e.key.toString();
          if (key.startsWith('group_')) continue;
          final ts = e.value is Timestamp ? e.value as Timestamp : null;
          entries.add(_InviteEntry(key, ts));
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

  /// Stream of connections for the Chats tab, sorted by lastMessage (newest first).
  /// Includes both 1:1 connections and group connections. Excludes archived.
  Stream<List<ConnectionInfo>> connectionsForUserStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().asyncExpand((
      userDoc,
    ) {
      final data = userDoc.data();
      final connections = data?['connections'] as Map? ?? {};
      final groupConnections = data?['groupConnections'] as Map? ?? {};

      final connectionIds = <String>[];
      final groupConnectionIds = groupConnections.keys
          .map((e) => e.toString())
          .toList();

      final otherUserIds = connections.keys.map((e) => e.toString()).toList();
      for (final o in otherUserIds) {
        connectionIds.add(connectionIdFromUsers(userId, o));
      }
      connectionIds.addAll(groupConnectionIds);

      if (connectionIds.isEmpty) {
        return Stream.value(<ConnectionInfo>[]);
      }

      final connectionStreams = connectionIds
          .map((id) => _firestore.collection('connections').doc(id).snapshots())
          .toList();

      return StreamGroup.merge<Object?>([
        Stream.value(null),
        ...connectionStreams,
      ]).asyncMap(
        (_) => _fetchAllConnectionInfos(userId, connections, groupConnections),
      );
    });
  }

  /// Stream of archived connections for the Archive tab.
  /// Uses archived (1:1) and archivedGroups maps. Sorted by lastMessage (newest first).
  Stream<List<ConnectionInfo>> archivedConnectionsForUserStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().asyncExpand((
      userDoc,
    ) {
      final data = userDoc.data();
      final archived = data?['archived'] as Map? ?? {};
      final archivedGroups = data?['archivedGroups'] as Map? ?? {};

      final connectionIds = <String>[];
      final otherUserIds = archived.keys.map((e) => e.toString()).toList();
      for (final o in otherUserIds) {
        connectionIds.add(connectionIdFromUsers(userId, o));
      }
      connectionIds.addAll(
        archivedGroups.keys.map((e) => e.toString()).toList(),
      );

      if (connectionIds.isEmpty) {
        return Stream.value(<ConnectionInfo>[]);
      }

      final connectionStreams = connectionIds
          .map((id) => _firestore.collection('connections').doc(id).snapshots())
          .toList();

      return StreamGroup.merge<Object?>([
        Stream.value(null),
        ...connectionStreams,
      ]).asyncMap(
        (_) => _fetchAllConnectionInfos(userId, archived, archivedGroups),
      );
    });
  }

  /// Archives a 1:1 connection: moves from connections to archived.
  Future<void> archiveConnection({
    required String userId,
    required String otherUserId,
  }) async {
    try {
      final now = FieldValue.serverTimestamp();
      final userRef = _firestore.collection('users').doc(userId);
      await _firestore.runTransaction((transaction) async {
        transaction.update(userRef, {
          'connections.$otherUserId': FieldValue.delete(),
          'archived.$otherUserId': now,
          'updatedAt': now,
        });
      });
    } catch (e) {
      throw 'Failed to archive connection: $e';
    }
  }

  /// Unarchives a 1:1 connection: moves from archived to connections.
  Future<void> unarchiveConnection({
    required String userId,
    required String otherUserId,
  }) async {
    try {
      final now = FieldValue.serverTimestamp();
      final userRef = _firestore.collection('users').doc(userId);
      await _firestore.runTransaction((transaction) async {
        transaction.update(userRef, {
          'archived.$otherUserId': FieldValue.delete(),
          'connections.$otherUserId': now,
          'updatedAt': now,
        });
      });
    } catch (e) {
      throw 'Failed to unarchive connection: $e';
    }
  }

  /// Archives a group connection: moves from groupConnections to archivedGroups.
  Future<void> archiveGroupConnection({
    required String userId,
    required String groupId,
  }) async {
    try {
      final now = FieldValue.serverTimestamp();
      final userRef = _firestore.collection('users').doc(userId);
      await _firestore.runTransaction((transaction) async {
        transaction.update(userRef, {
          'groupConnections.$groupId': FieldValue.delete(),
          'archivedGroups.$groupId': now,
          'updatedAt': now,
        });
      });
    } catch (e) {
      throw 'Failed to archive group: $e';
    }
  }

  /// Unarchives a group connection: moves from archivedGroups to groupConnections.
  Future<void> unarchiveGroupConnection({
    required String userId,
    required String groupId,
  }) async {
    try {
      final now = FieldValue.serverTimestamp();
      final userRef = _firestore.collection('users').doc(userId);
      await _firestore.runTransaction((transaction) async {
        transaction.update(userRef, {
          'archivedGroups.$groupId': FieldValue.delete(),
          'groupConnections.$groupId': now,
          'updatedAt': now,
        });
      });
    } catch (e) {
      throw 'Failed to unarchive group: $e';
    }
  }

  Future<List<ConnectionInfo>> _fetchAllConnectionInfos(
    String userId,
    Map connections,
    Map groupConnections,
  ) async {
    final infos = <ConnectionInfo>[];

    for (final otherId in connections.keys) {
      final otherIdStr = otherId.toString();
      final connId = connectionIdFromUsers(userId, otherIdStr);
      final info = await _fetchSingleConnectionInfo(
        userId,
        connId,
        otherIdStr,
        null,
      );
      if (info != null) infos.add(info);
    }

    for (final groupId in groupConnections.keys) {
      final groupIdStr = groupId.toString();
      if (!groupIdStr.startsWith('group_')) continue;
      final info = await _fetchGroupConnectionInfo(userId, groupIdStr);
      if (info != null) infos.add(info);
    }

    infos.sort((a, b) {
      if (a.lastMessage == null && b.lastMessage == null) return 0;
      if (a.lastMessage == null) return 1;
      if (b.lastMessage == null) return -1;
      return b.lastMessage!.compareTo(a.lastMessage!);
    });
    return infos;
  }

  Future<ConnectionInfo?> _fetchSingleConnectionInfo(
    String userId,
    String connId,
    String otherId,
    Map<String, dynamic>? connData,
  ) async {
    final connDoc = await _firestore
        .collection('connections')
        .doc(connId)
        .get();
    if (!connDoc.exists) return null;

    final data = connData ?? connDoc.data() ?? {};
    final name = data['name'] as String? ?? '';
    final lastMessageTs = data['lastMessage'];
    final lastMessage = lastMessageTs is Timestamp
        ? lastMessageTs.toDate()
        : null;

    final participantsSnapshot = await connDoc.reference
        .collection('participants')
        .get();
    final otherStillConnected = participantsSnapshot.docs.any(
      (d) => d.id == otherId,
    );

    String displayName = name;
    if (displayName.isEmpty && otherStillConnected) {
      final userData = await getUserProfile(otherId);
      displayName = userData?['username'] as String? ?? otherId;
    } else if (displayName.isEmpty) {
      displayName = 'Unknown';
    }

    return ConnectionInfo(
      connectionId: connId,
      otherUserId: otherId,
      name: displayName,
      lastMessage: lastMessage,
      otherParticipantStillConnected: otherStillConnected,
    );
  }

  Future<ConnectionInfo?> _fetchGroupConnectionInfo(
    String userId,
    String groupConnectionId,
  ) async {
    final connDoc = await _firestore
        .collection('connections')
        .doc(groupConnectionId)
        .get();
    if (!connDoc.exists) return null;

    final data = connDoc.data() ?? {};
    final name = data['name'] as String? ?? 'Unnamed group';
    final lastMessageTs = data['lastMessage'];
    final lastMessage = lastMessageTs is Timestamp
        ? lastMessageTs.toDate()
        : null;

    final participantsSnapshot = await connDoc.reference
        .collection('participants')
        .get();
    final participantIds = participantsSnapshot.docs.map((d) => d.id).toList();

    return ConnectionInfo(
      connectionId: groupConnectionId,
      otherUserId: '',
      name: name,
      lastMessage: lastMessage,
      otherParticipantStillConnected: true,
      isGroup: true,
      participantIds: participantIds,
    );
  }

  /// Returns user IDs the current user is connected with (1:1 only).
  Future<List<String>> getConnectedUserIds(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) return [];
    final data = doc.data() ?? {};
    final connections = data['connections'];
    if (connections is! Map) return [];
    return connections.keys.map((e) => e.toString()).toList();
  }

  /// Sends group invites from [creatorUserId] to [selectedUserIds].
  /// Creates connection immediately with only creator as participant.
  /// Adds invites.$groupId = timestamp on receivers (same invites map as 1:1).
  /// Returns the generated groupId.
  Future<String> sendGroupInvites({
    required String creatorUserId,
    required List<String> selectedUserIds,
    required String name,
  }) async {
    if (name.trim().isEmpty) {
      throw 'Group name is required';
    }
    if (selectedUserIds.isEmpty) {
      throw 'Select at least one participant';
    }

    final connectedIds = await getConnectedUserIds(creatorUserId);
    for (final id in selectedUserIds) {
      if (!connectedIds.contains(id)) {
        throw 'All selected users must be connected with you';
      }
    }

    final groupId =
        'group_${DateTime.now().millisecondsSinceEpoch}_'
        '${Random().nextInt(999999)}';

    try {
      final now = FieldValue.serverTimestamp();
      final connectionRef = _firestore.collection('connections').doc(groupId);

      final creatorUserRef =
          _firestore.collection('users').doc(creatorUserId);

      await _firestore.runTransaction((transaction) async {
        transaction.set(connectionRef, {
          'name': name.trim(),
          'lastMessage': now,
          'type': 'group',
          'creatorId': creatorUserId,
        });
        transaction.set(
          connectionRef.collection('participants').doc(creatorUserId),
          {'lastSeen': now},
        );
        transaction.update(creatorUserRef, {
          'groupConnections.$groupId': now,
          'updatedAt': now,
        });
        for (final receiverId in selectedUserIds) {
          transaction.update(_firestore.collection('users').doc(receiverId), {
            'invites.$groupId': now,
            'updatedAt': now,
          });
        }
      });

      return groupId;
    } catch (e) {
      throw 'Failed to send group invites: $e';
    }
  }

  /// Stream of group invites for the given user.
  /// Reads from invites map (keys starting with "group_"). Fetches connection for each.
  Stream<List<GroupInviteInfo>> groupInvitesStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().asyncMap((
      doc,
    ) async {
      if (!doc.exists) return <GroupInviteInfo>[];
      final data = doc.data() ?? {};
      final invites = data['invites'];
      if (invites is! Map) return <GroupInviteInfo>[];
      final list = <GroupInviteInfo>[];
      for (final e in invites.entries) {
        final groupId = e.key.toString();
        if (!groupId.startsWith('group_')) continue;
        final ts = e.value is Timestamp ? e.value as Timestamp : null;
        try {
          final connDoc = await _firestore
              .collection('connections')
              .doc(groupId)
              .get();
          if (connDoc.exists) {
            list.add(
              GroupInviteInfo.fromConnection(groupId, connDoc.data() ?? {}, ts),
            );
          }
        } catch (_) {
          // Skip if connection not found
        }
      }
      list.sort((a, b) {
        final ta = a.timestamp;
        final tb = b.timestamp;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  /// Accepts a group invite. Connection already exists (created on send).
  /// Adds receiver to participants and removes invite from invites map.
  Future<void> acceptGroupInvite({
    required String receiverUserId,
    required String groupId,
  }) async {
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(receiverUserId)
          .get();
      if (!userDoc.exists) throw 'User not found';
      final data = userDoc.data() ?? {};
      final invites = data['invites'];
      if (invites is! Map || !invites.containsKey(groupId)) {
        throw 'Group invite not found';
      }

      final connRef = _firestore.collection('connections').doc(groupId);
      final connDoc = await connRef.get();
      if (!connDoc.exists) {
        throw 'Group no longer exists';
      }

      final now = FieldValue.serverTimestamp();

      await _firestore.runTransaction((transaction) async {
        transaction.set(
          connRef.collection('participants').doc(receiverUserId),
          {'lastSeen': now},
        );
        transaction.update(_firestore.collection('users').doc(receiverUserId), {
          'groupConnections.$groupId': now,
          'invites.$groupId': FieldValue.delete(),
          'updatedAt': now,
        });
      });
    } catch (e) {
      throw 'Failed to accept group invite: $e';
    }
  }

  /// Declines a group invite.
  Future<void> declineGroupInvite({
    required String receiverUserId,
    required String groupId,
  }) async {
    try {
      await _firestore.collection('users').doc(receiverUserId).update({
        'invites.$groupId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw 'Failed to decline group invite: $e';
    }
  }

  /// Stream of connected user IDs for the given user, newest first.
  /// Used for badge count.
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

  /// Removes a connection for [currentUserId]. Removes from participants and
  /// current user's connections map. Does NOT remove from the other user's map
  /// so they still see it. Sets connection name to removed user's name.
  /// Deletes connections/{connectionID} when the last participant leaves.
  Future<void> removeConnection({
    required String currentUserId,
    required String otherUserId,
  }) async {
    try {
      final connectionId = connectionIdFromUsers(currentUserId, otherUserId);
      final connectionRef = _firestore
          .collection('connections')
          .doc(connectionId);
      final userRef = _firestore.collection('users').doc(currentUserId);
      final participantRef =
          connectionRef.collection('participants').doc(currentUserId);

      await _firestore.runTransaction((transaction) async {
        // Read all documents we will modify (required by Firestore transactions).
        final userSnap = await transaction.get(userRef);
        final connectionSnap = await transaction.get(connectionRef);
        await transaction.get(participantRef);

        if (!userSnap.exists) return;
        if (!connectionSnap.exists) return;

        final removedUserName = userSnap.data()?['username'] as String? ??
            currentUserId;

        transaction.delete(participantRef);
        transaction.update(userRef, {
          'connections.$otherUserId': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(connectionRef, {
          'name': removedUserName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      final participantsSnapshot = await connectionRef
          .collection('participants')
          .get();
      if (participantsSnapshot.docs.isEmpty) {
        await _deleteCollection(connectionRef.collection('participants'));
        await _deleteCollection(connectionRef.collection('messages'));
        await connectionRef.delete();
      }
    } catch (e) {
      throw 'Failed to remove connection: $e';
    }
  }

  Future<void> _deleteCollection(CollectionReference collection) async {
    const batchSize = 100;
    QuerySnapshot snapshot = await collection
        .orderBy(FieldPath.documentId)
        .limit(batchSize)
        .get();

    while (snapshot.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      snapshot = await collection
          .orderBy(FieldPath.documentId)
          .limit(batchSize)
          .get();
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

  /// Removes [userId] from all their connections (1:1 and groups).
  /// Call before deleting the user profile. Requires the user doc to exist.
  Future<void> removeUserFromAllConnections(String userId) async {
    final userData = await getUserProfile(userId);
    if (userData == null) return;

    final connections = userData['connections'];
    if (connections is Map) {
      final otherUserIds = connections.keys.map((e) => e.toString()).toList();
      for (final otherId in otherUserIds) {
        await removeConnection(currentUserId: userId, otherUserId: otherId);
      }
    }

    final groupConnections = userData['groupConnections'];
    if (groupConnections is Map) {
      final groupIds = groupConnections.keys.map((e) => e.toString()).toList();
      for (final groupId in groupIds) {
        await removeUserFromGroup(userId: userId, groupConnectionId: groupId);
      }
    }
  }

  /// Removes a user from a group connection.
  Future<void> removeUserFromGroup({
    required String userId,
    required String groupConnectionId,
  }) async {
    try {
      final connectionRef = _firestore
          .collection('connections')
          .doc(groupConnectionId);
      final participantRef = connectionRef
          .collection('participants')
          .doc(userId);

      await _firestore.runTransaction((transaction) async {
        transaction.delete(participantRef);
        transaction.update(_firestore.collection('users').doc(userId), {
          'groupConnections.$groupConnectionId': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      final participantsSnapshot = await connectionRef
          .collection('participants')
          .get();
      if (participantsSnapshot.docs.isEmpty) {
        await _deleteCollection(connectionRef.collection('participants'));
        await _deleteCollection(connectionRef.collection('messages'));
        await connectionRef.delete();
      }
    } catch (e) {
      // Silently ignore - group may not exist
    }
  }

  /// Removes invites sent by [userId] from all other users' invite maps.
  /// Includes 1:1 invites and group invites where [userId] is the creator.
  /// Call before deleting the user profile.
  Future<void> removeInvitesSentByUser(String userId) async {
    final usersSnapshot = await _firestore.collection('users').get();
    final batch = _firestore.batch();
    var hasWrites = false;

    for (final doc in usersSnapshot.docs) {
      if (doc.id == userId) continue;
      final data = doc.data();
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final invites = data['invites'];
      if (invites is Map && invites.containsKey(userId)) {
        updates['invites.$userId'] = FieldValue.delete();
        hasWrites = true;
      }

      if (invites is Map) {
        for (final e in invites.entries) {
          final key = e.key.toString();
          if (!key.startsWith('group_')) continue;
          try {
            final connDoc = await _firestore
                .collection('connections')
                .doc(key)
                .get();
            if (connDoc.exists) {
              final connData = connDoc.data() ?? {};
              if (connData['creatorId'] == userId) {
                updates['invites.$key'] = FieldValue.delete();
                hasWrites = true;
              }
            }
          } catch (_) {
            // Skip if connection not found
          }
        }
      }

      if (updates.length > 1) {
        batch.update(doc.reference, updates);
      }
    }

    if (hasWrites) await batch.commit();
  }

  /// Full cleanup when a user deletes their account: removes from all
  /// connections, removes invites they sent, then deletes the user profile.
  /// Call after Firebase Auth user is deleted. Profile picture should be
  /// deleted separately via StorageService.
  Future<void> deleteUserWithConnectionsCleanup(String userId) async {
    await removeUserFromAllConnections(userId);
    await removeInvitesSentByUser(userId);
    await deleteUserProfile(userId);
  }

  /// Sends a message in a connection. Updates connection lastMessage.
  /// [mediaUrl], [mediaPath], [mediaType] are optional for media messages.
  /// When media is provided, pass [messageId] from [generateMessageId] so
  /// storage path matches.
  Future<void> sendMessage({
    required String connectionId,
    required String senderId,
    required String text,
    String? messageId,
    String? mediaUrl,
    String? mediaPath,
    MessageMediaType? mediaType,
  }) async {
    try {
      final connectionRef = _firestore
          .collection('connections')
          .doc(connectionId);
      final messagesRef = connectionRef.collection('messages');

      final now = FieldValue.serverTimestamp();
      final data = <String, dynamic>{
        'senderId': senderId,
        'text': text.trim(),
        'createdAt': now,
      };
      if (mediaUrl != null && mediaPath != null && mediaType != null) {
        data['mediaUrl'] = mediaUrl;
        data['mediaPath'] = mediaPath;
        data['mediaType'] = mediaType == MessageMediaType.image
            ? 'image'
            : 'video';
      }

      await _firestore.runTransaction((transaction) async {
        final messageRef = messageId != null
            ? messagesRef.doc(messageId)
            : messagesRef.doc();
        transaction.set(messageRef, data);
        transaction.update(connectionRef, {
          'lastMessage': now,
          'updatedAt': now,
        });
        transaction.set(
          connectionRef.collection('participants').doc(senderId),
          {'lastSeen': now},
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      throw 'Failed to send message: $e';
    }
  }

  /// Returns a new message document ID for use before creating the message.
  /// Use this to upload media before calling sendMessage.
  String generateMessageId(String connectionId) {
    return _firestore
        .collection('connections')
        .doc(connectionId)
        .collection('messages')
        .doc()
        .id;
  }

  /// Updates a message's text and optionally media. Does not change createdAt.
  /// Pass [oldMediaPath] to delete unreferenced media when replacing or removing.
  /// Pass [newMediaUrl], [newMediaPath], [newMediaType] to set new media.
  /// When only updating text, omit media params to preserve existing media.
  Future<void> updateMessage({
    required String connectionId,
    required String messageId,
    required String newText,
    String? oldMediaPath,
    String? newMediaUrl,
    String? newMediaPath,
    MessageMediaType? newMediaType,
  }) async {
    try {
      if (oldMediaPath != null && oldMediaPath.isNotEmpty) {
        await _storageService.deleteMessageMediaByPath(oldMediaPath);
      }

      final data = <String, dynamic>{'text': newText.trim()};
      if (newMediaUrl != null && newMediaPath != null && newMediaType != null) {
        data['mediaUrl'] = newMediaUrl;
        data['mediaPath'] = newMediaPath;
        data['mediaType'] = newMediaType == MessageMediaType.image
            ? 'image'
            : 'video';
      } else if (oldMediaPath != null) {
        data['mediaUrl'] = FieldValue.delete();
        data['mediaPath'] = FieldValue.delete();
        data['mediaType'] = FieldValue.delete();
      }

      await _firestore
          .collection('connections')
          .doc(connectionId)
          .collection('messages')
          .doc(messageId)
          .update(data);
    } catch (e) {
      throw 'Failed to update message: $e';
    }
  }

  /// Deletes a message. Deletes unreferenced media from storage. Updates
  /// connection lastMessage if deleting the most recent message.
  Future<void> deleteMessage({
    required String connectionId,
    required String messageId,
  }) async {
    try {
      final connectionRef = _firestore
          .collection('connections')
          .doc(connectionId);
      final messagesRef = connectionRef.collection('messages');
      final messageRef = messagesRef.doc(messageId);

      final messageDoc = await messageRef.get();
      final data = messageDoc.data();
      final mediaPath = data != null ? data['mediaPath'] as String? : null;
      if (mediaPath != null && mediaPath.isNotEmpty) {
        await _storageService.deleteMessageMediaByPath(mediaPath);
      }

      final topSnapshot = await messagesRef
          .orderBy('createdAt', descending: true)
          .limit(2)
          .get();

      Object? nextLastMessage;
      if (topSnapshot.docs.isNotEmpty &&
          topSnapshot.docs.first.id == messageId &&
          topSnapshot.docs.length > 1) {
        nextLastMessage = topSnapshot.docs[1].data()['createdAt'];
      }

      await _firestore.runTransaction((transaction) async {
        transaction.delete(messageRef);
        if (nextLastMessage != null) {
          transaction.update(connectionRef, {
            'lastMessage': nextLastMessage,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      throw 'Failed to delete message: $e';
    }
  }

  /// Fetches a page of messages, newest first. Returns messages and the
  /// oldest document snapshot for pagination. Pass [startAfterDoc] to load
  /// older messages.
  Future<({List<Message> messages, DocumentSnapshot? oldestDoc})>
  getMessagesPage({
    required String connectionId,
    int limit = 10,
    DocumentSnapshot? startAfterDoc,
  }) async {
    final messagesRef = _firestore
        .collection('connections')
        .doc(connectionId)
        .collection('messages');

    Query<Map<String, dynamic>> query = messagesRef
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfterDoc != null) {
      query = query.startAfterDocument(startAfterDoc);
    }

    final snapshot = await query.get();
    final messages = snapshot.docs
        .map((d) => Message.fromFirestore(d))
        .toList();
    final oldestDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
    return (messages: messages, oldestDoc: oldestDoc);
  }

  /// Stream of a participant's data (lastSeen, lastTyping) for a connection.
  Stream<Map<String, dynamic>?> participantStream({
    required String connectionId,
    required String userId,
  }) {
    return _firestore
        .collection('connections')
        .doc(connectionId)
        .collection('participants')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? doc.data() : null);
  }

  /// Stream of all participants' data for a connection. Use for real-time
  /// typing indicators in group chats.
  Stream<Map<String, Map<String, dynamic>>> participantsStream({
    required String connectionId,
  }) {
    return _firestore
        .collection('connections')
        .doc(connectionId)
        .collection('participants')
        .snapshots()
        .map((snapshot) {
          final map = <String, Map<String, dynamic>>{};
          for (final doc in snapshot.docs) {
            map[doc.id] = doc.data();
          }
          return map;
        });
  }

  /// Stream of new messages (createdAt > [after]). Use for real-time updates.
  /// Pass null for [after] to get all messages (for new chats).
  Stream<List<Message>> messagesStream({
    required String connectionId,
    DateTime? after,
  }) {
    var query = _firestore
        .collection('connections')
        .doc(connectionId)
        .collection('messages')
        .orderBy('createdAt', descending: false);

    if (after != null) {
      query = query.startAfter([Timestamp.fromDate(after)]);
    }

    return query.snapshots().map(
      (snapshot) => snapshot.docs.map((d) => Message.fromFirestore(d)).toList(),
    );
  }

  /// Stream of messages where createdAt >= [createdAtFloor]. Listens for
  /// changes including edits and deletes. Use for real-time updates while
  /// chat is open.
  Stream<List<Message>> messagesInRangeStream({
    required String connectionId,
    required DateTime createdAtFloor,
  }) {
    return _firestore
        .collection('connections')
        .doc(connectionId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .startAt([Timestamp.fromDate(createdAtFloor)])
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((d) => Message.fromFirestore(d)).toList(),
        );
  }
}
