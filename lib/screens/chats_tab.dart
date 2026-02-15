import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/firestore_service.dart';
import 'account_tab.dart';

class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return StreamBuilder<List<String>>(
      stream: firestoreService.connectionsStream(user.userId),
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

        final connectionIds = snapshot.data ?? [];

        if (connectionIds.isEmpty) {
          return const Center(
            child: Text(
              'No connections yet',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(24.0),
          itemCount: connectionIds.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return _ConnectionTile(connectionUserId: connectionIds[index]);
          },
        );
      },
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.connectionUserId});

  final String connectionUserId;

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return StreamBuilder<Map<String, dynamic>?>(
      stream: firestoreService.userProfileStream(connectionUserId),
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
              subtitle: Text(connectionUserId),
            ),
          );
        }

        final data = snapshot.data!;
        final connectedUser = User.fromFirestore(data, connectionUserId);

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              radius: 24,
              backgroundImage: getProfileImageProvider(connectedUser),
            ),
            title: Text(connectedUser.username),
          ),
        );
      },
    );
  }
}
