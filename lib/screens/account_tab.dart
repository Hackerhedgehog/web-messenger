import 'package:flutter/material.dart';

import '../models/user_model.dart';

/// Returns the appropriate image provider for the user's profile picture.
ImageProvider getProfileImageProvider(User user) {
  if (user.profilePictureUrl != null &&
      user.profilePictureUrl!.isNotEmpty) {
    return NetworkImage(user.profilePictureUrl!);
  }
  return const AssetImage('assets/default.png');
}

class AccountTab extends StatefulWidget {
  const AccountTab({
    super.key,
    required this.user,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final User user;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  static Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
      ],
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final onLogout = widget.onLogout;
    final onDeleteAccount = widget.onDeleteAccount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account Information',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundImage: getProfileImageProvider(user),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('Username', user.username),
                  const SizedBox(height: 12),
                  _buildInfoRow('Email', user.email),
                  const SizedBox(height: 12),
                  _buildInfoRow('User ID', user.userId),
                  if (user.createdAt != null) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      'Account Created',
                      _formatDate(user.createdAt!),
                    ),
                  ],
                  if (user.updatedAt != null) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow('Last Updated', _formatDate(user.updatedAt!)),
                  ],
                  if (user.additionalData != null &&
                      user.additionalData!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text(
                      'Additional Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...user.additionalData!.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildInfoRow(entry.key, entry.value.toString()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onDeleteAccount,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Delete Account'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
