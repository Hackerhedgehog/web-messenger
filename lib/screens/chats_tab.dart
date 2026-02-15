import 'package:flutter/material.dart';

import '../models/connection_info.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../widgets/profile_avatar.dart';
import 'chat_screen.dart';
import 'choose_participants_screen.dart';

class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key, required this.user});

  final User user;

  Future<void> _showRemoveConnectionDialog(
    BuildContext context,
    FirestoreService firestoreService,
    String currentUserId,
    String otherUserId,
  ) async {
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
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                  onRemoveConnection: conn.isGroup
                      ? null
                      : () => _showRemoveConnectionDialog(
                            context,
                            firestoreService,
                            user.userId,
                            conn.otherUserId,
                          ),
                );
              },
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                onPressed: () {
                  Navigator.of(context).push(
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
    required this.onRemoveConnection,
  });

  final User currentUser;
  final ConnectionInfo connectionInfo;
  final VoidCallback? onRemoveConnection;

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

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
            onLongPress: onRemoveConnection,
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
      onLongPress: onRemoveConnection,
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
