import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../widgets/profile_avatar.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.user});

  final User user;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final TextEditingController _searchController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();

  User? _foundUser;
  bool _isSearching = false;
  String? _searchError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _sendInvite(User receiver) async {
    try {
      final result = await _firestoreService.sendInvite(
        senderUserId: widget.user.userId,
        receiverUserId: receiver.userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result == 'connected'
                  ? 'You\'re now connected with ${receiver.username}!'
                  : 'Invite sent to ${receiver.username}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send invite: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _searchUser() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _foundUser = null;
        _searchError = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
      _foundUser = null;
    });

    try {
      final data = await _firestoreService.findUserByUsernameOrEmail(query);
      if (!mounted) return;

      if (data == null) {
        setState(() {
          _foundUser = null;
          _searchError = 'No user found';
        });
        return;
      }

      final userId = data['userId'] as String? ?? '';
      final user = User.fromFirestore(data, userId);

      if (user.userId == widget.user.userId) {
        setState(() {
          _foundUser = null;
          _searchError = 'That\'s you!';
        });
        return;
      }

      setState(() {
        _foundUser = user;
        _searchError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _foundUser = null;
          _searchError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Welcome!',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search by username or email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchUser(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _isSearching ? null : _searchUser,
                icon: _isSearching
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                tooltip: 'Search',
              ),
            ],
          ),
          if (_searchError != null) ...[
            const SizedBox(height: 16),
            Text(
              _searchError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 14,
              ),
            ),
          ],
          if (_foundUser != null) ...[
            const SizedBox(height: 24),
            const Text(
              'Search result',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _UserSearchResultTile(
              user: _foundUser!,
              onInvite: () => _sendInvite(_foundUser!),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserSearchResultTile extends StatelessWidget {
  const _UserSearchResultTile({
    required this.user,
    required this.onInvite,
  });

  final User user;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: ProfileAvatar(
          user: user,
          radius: 24,
        ),
        title: Text(user.username),
        trailing: FilledButton.icon(
          onPressed: onInvite,
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text('Invite'),
        ),
      ),
    );
  }
}
