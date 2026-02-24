import 'package:flutter/material.dart';

import '../models/connection_info.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_popup.dart';
import 'chat_screen.dart';
import 'choose_participants_screen.dart';

class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key, required this.user});

  final User user;

  static Future<void> _archiveChat(
    BuildContext context,
    FirestoreService firestoreService,
    String currentUserId,
    ConnectionInfo conn,
  ) async {
    try {
      if (conn.isGroup) {
        await firestoreService.archiveGroupConnection(
          userId: currentUserId,
          groupId: conn.connectionId,
        );
      } else {
        await firestoreService.archiveConnection(
          userId: currentUserId,
          otherUserId: conn.otherUserId,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat archived'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to archive: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showRemoveConnectionDialog(
    BuildContext context,
    FirestoreService firestoreService,
    String currentUserId,
    String otherUserId,
  ) async {
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove connection'),
        content: const Text(
          'Remove this connection? You will no longer be able to chat with this user.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove connection'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await firestoreService.removeConnection(
        currentUserId: currentUserId,
        otherUserId: otherUserId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection removed'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove connection: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return StreamBuilder<List<ConnectionInfo>>(
      stream: firestoreService.connectionsForUserStream(user.userId),
      builder: (scaffoldContext, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: TextStyle(color: Theme.of(scaffoldContext).colorScheme.error),
            ),
          );
        }

        final connections = snapshot.data ?? [];

        if (connections.isEmpty) {
          return const Center(
            child: Text(
              'No connections yet',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return Stack(
          children: [
            ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
              itemCount: connections.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final conn = connections[index];
                return _ConnectionTile(
                  currentUser: user,
                  connectionInfo: conn,
                  firestoreService: firestoreService,
                  onRemoveConnection: conn.isGroup
                      ? null
                      : () => _showRemoveConnectionDialog(
                            scaffoldContext,
                            firestoreService,
                            user.userId,
                            conn.otherUserId,
                          ),
                  onArchive: () => _archiveChat(
                    scaffoldContext,
                    firestoreService,
                    user.userId,
                    conn,
                  ),
                );
              },
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                onPressed: () {
                  Navigator.of(scaffoldContext).push(
                    MaterialPageRoute(
                      builder: (context) => ChooseParticipantsScreen(
                        currentUser: user,
                      ),
                    ),
                  );
                },
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.currentUser,
    required this.connectionInfo,
    required this.firestoreService,
    required this.onRemoveConnection,
    required this.onArchive,
  });

  final User currentUser;
  final ConnectionInfo connectionInfo;
  final FirestoreService firestoreService;
  final VoidCallback? onRemoveConnection;
  final VoidCallback? onArchive;

  void _showContextMenu(BuildContext context) {
    if (connectionInfo.isGroup) {
      showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('View participants'),
                onTap: () {
                  Navigator.pop(context);
                  _showGroupParticipants(context);
                },
              ),
              if (onArchive != null)
                ListTile(
                  leading: const Icon(Icons.archive),
                  title: const Text('Archive'),
                  onTap: () {
                    Navigator.pop(context);
                    onArchive!();
                  },
                ),
            ],
          ),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('View profile'),
              onTap: () {
                Navigator.pop(context);
                _showOtherUserProfile(context);
              },
            ),
            if (onArchive != null)
              ListTile(
                leading: const Icon(Icons.archive),
                title: const Text('Archive'),
                onTap: () {
                  Navigator.pop(context);
                  onArchive!();
                },
              ),
            if (onRemoveConnection != null)
              ListTile(
                leading: const Icon(Icons.link_off, color: Colors.red),
                title: const Text('Remove connection', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  onRemoveConnection!();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showOtherUserProfile(BuildContext context) async {
    final data = await firestoreService.getUserProfile(connectionInfo.otherUserId);
    if (!context.mounted) return;
    final user = data != null
        ? User.fromFirestore(data, connectionInfo.otherUserId)
        : User(userId: connectionInfo.otherUserId, email: '', username: connectionInfo.name);
    showProfilePopup(context: context, user: user);
  }

  void _showGroupParticipants(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${connectionInfo.name} - Participants',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView.builder(
                controller: scrollController,
                shrinkWrap: true,
                itemCount: connectionInfo.participantIds.length,
                itemBuilder: (context, index) {
                  final userId = connectionInfo.participantIds[index];
                  return _ParticipantProfileTile(
                    userId: userId,
                    firestoreService: firestoreService,
                    isCurrentUser: userId == currentUser.userId,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (connectionInfo.isGroup) {
      return GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                currentUser: currentUser,
                connectionInfo: connectionInfo,
              ),
            ),
          );
        },
        onLongPress: () => _showContextMenu(context),
        child: Card(
          child: ListTile(
            leading: const CircleAvatar(
              radius: 24,
              backgroundImage: AssetImage('assets/default.png'),
            ),
            title: Text(connectionInfo.name),
          ),
        ),
      );
    }

    if (connectionInfo.otherParticipantStillConnected) {
      return StreamBuilder<Map<String, dynamic>?>(
        stream: firestoreService.userProfileStream(connectionInfo.otherUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Card(
              child: ListTile(
                leading: CircleAvatar(child: CircularProgressIndicator()),
                title: Text('Loading...'),
              ),
            );
          }

          final otherUser = snapshot.hasData && snapshot.data != null
              ? User.fromFirestore(
                  snapshot.data!, connectionInfo.otherUserId)
              : User(
                  userId: connectionInfo.otherUserId,
                  email: '',
                  username: connectionInfo.name,
                );

          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    currentUser: currentUser,
                    connectionInfo: connectionInfo,
                  ),
                ),
              );
            },
            onLongPress: () => _showContextMenu(context),
            child: Card(
              child: ListTile(
                leading: ProfileAvatar(
                  user: otherUser,
                  radius: 24,
                ),
                title: Text(connectionInfo.name),
              ),
            ),
          );
        },
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              currentUser: currentUser,
              connectionInfo: connectionInfo,
            ),
          ),
        );
      },
      onLongPress: () => _showContextMenu(context),
      child: Card(
        child: ListTile(
          leading: const CircleAvatar(
            radius: 24,
            backgroundImage: AssetImage('assets/default.png'),
          ),
          title: Text(connectionInfo.name),
        ),
      ),
    );
  }
}

class _ParticipantProfileTile extends StatelessWidget {
  const _ParticipantProfileTile({
    required this.userId,
    required this.firestoreService,
    required this.isCurrentUser,
  });

  final String userId;
  final FirestoreService firestoreService;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: firestoreService.getUserProfile(userId),
      builder: (context, snapshot) {
        final user = snapshot.hasData && snapshot.data != null
            ? User.fromFirestore(snapshot.data!, userId)
            : User(userId: userId, email: '', username: userId);

        return ListTile(
          leading: ProfileAvatar(user: user, radius: 24),
          title: Row(
            children: [
              Text(user.username),
              if (isCurrentUser)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '(you)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ),
            ],
          ),
          trailing: isCurrentUser
              ? null
              : IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: () {
                    Navigator.pop(context);
                    showProfilePopup(context: context, user: user);
                  },
                  tooltip: 'View profile',
                ),
        );
      },
    );
  }
}
