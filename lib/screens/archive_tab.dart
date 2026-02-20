import 'package:flutter/material.dart';

import '../models/connection_info.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_popup.dart';
import 'chat_screen.dart';

class ArchiveTab extends StatelessWidget {
  const ArchiveTab({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return StreamBuilder<List<ConnectionInfo>>(
      stream: firestoreService.archivedConnectionsForUserStream(user.userId),
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
              'No archived chats',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          itemCount: connections.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final conn = connections[index];
            return _ArchivedConnectionTile(
              currentUser: user,
              connectionInfo: conn,
              firestoreService: firestoreService,
            );
          },
        );
      },
    );
  }
}

class _ArchivedConnectionTile extends StatelessWidget {
  const _ArchivedConnectionTile({
    required this.currentUser,
    required this.connectionInfo,
    required this.firestoreService,
  });

  final User currentUser;
  final ConnectionInfo connectionInfo;
  final FirestoreService firestoreService;

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.unarchive),
              title: const Text('Unarchive'),
              onTap: () {
                Navigator.pop(context);
                _unarchive(context);
              },
            ),
            if (!connectionInfo.isGroup)
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('View profile'),
                onTap: () {
                  Navigator.pop(context);
                  _showOtherUserProfile(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _unarchive(BuildContext context) async {
    try {
      if (connectionInfo.isGroup) {
        await firestoreService.unarchiveGroupConnection(
          userId: currentUser.userId,
          groupId: connectionInfo.connectionId,
        );
      } else {
        await firestoreService.unarchiveConnection(
          userId: currentUser.userId,
          otherUserId: connectionInfo.otherUserId,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat unarchived'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unarchive: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showOtherUserProfile(BuildContext context) async {
    final data = await firestoreService.getUserProfile(connectionInfo.otherUserId);
    if (!context.mounted) return;
    final user = data != null
        ? User.fromFirestore(data, connectionInfo.otherUserId)
        : User(
            userId: connectionInfo.otherUserId,
            email: '',
            username: connectionInfo.name,
          );
    showProfilePopup(context: context, user: user);
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

    return StreamBuilder<Map<String, dynamic>?>(
      stream: firestoreService.userProfileStream(connectionInfo.otherUserId),
      builder: (context, snapshot) {
        final otherUser = snapshot.hasData && snapshot.data != null
            ? User.fromFirestore(
                snapshot.data!,
                connectionInfo.otherUserId,
              )
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
              leading: ProfileAvatar(user: otherUser, radius: 24),
              title: Text(connectionInfo.name),
            ),
          ),
        );
      },
    );
  }
}
