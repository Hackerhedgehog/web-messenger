import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../widgets/profile_avatar.dart';

class InvitesTab extends StatelessWidget {
  const InvitesTab({super.key, required this.user});

  final User user;

  Future<void> _acceptInvite(
    BuildContext context,
    FirestoreService firestoreService,
    String receiverUserId,
    String senderUserId,
  ) async {
    try {
      await firestoreService.acceptInvite(
        receiverUserId: receiverUserId,
        senderUserId: senderUserId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite accepted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept invite: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _declineInvite(
    BuildContext context,
    FirestoreService firestoreService,
    String receiverUserId,
    String senderUserId,
  ) async {
    try {
      await firestoreService.declineInvite(
        receiverUserId: receiverUserId,
        senderUserId: senderUserId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite declined'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline invite: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return StreamBuilder<List<String>>(
      stream: firestoreService.inviteSendersStream(user.userId),
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

        final senderIds = snapshot.data ?? [];

        if (senderIds.isEmpty) {
          return const Center(
            child: Text(
              'No invite requests',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(24.0),
          itemCount: senderIds.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return _InviteTile(
              senderUserId: senderIds[index],
              onAccept: () => _acceptInvite(
                context,
                firestoreService,
                user.userId,
                senderIds[index],
              ),
              onDecline: () => _declineInvite(
                context,
                firestoreService,
                user.userId,
                senderIds[index],
              ),
            );
          },
        );
      },
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({
    required this.senderUserId,
    required this.onAccept,
    required this.onDecline,
  });

  final String senderUserId;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return FutureBuilder<Map<String, dynamic>?>(
      future: firestoreService.getUserProfile(senderUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: ListTile(
              leading: CircleAvatar(child: CircularProgressIndicator()),
              title: Text('Loading...'),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: const Text('Unknown user'),
              subtitle: Text(senderUserId),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: onAccept,
                    child: const Text('Accept'),
                  ),
                  TextButton(
                    onPressed: onDecline,
                    child: const Text('Decline'),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data!;
        final user = User.fromFirestore(data, senderUserId);

        return Card(
          child: ListTile(
            leading: ProfileAvatar(
              user: user,
              radius: 24,
            ),
            title: Text(user.username),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onDecline,
                  child: const Text('Decline'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
