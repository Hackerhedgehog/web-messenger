import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../widgets/profile_avatar.dart';

class ChooseParticipantsScreen extends StatefulWidget {
  const ChooseParticipantsScreen({
    super.key,
    required this.currentUser,
  });

  final User currentUser;

  @override
  State<ChooseParticipantsScreen> createState() =>
      _ChooseParticipantsScreenState();
}

class _ChooseParticipantsScreenState extends State<ChooseParticipantsScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  List<String> _connectedUserIds = [];
  final Set<String> _selectedIds = {};
  final _nameController = TextEditingController();
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadConnectedUsers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadConnectedUsers() async {
    final ids = await _firestoreService.getConnectedUserIds(widget.currentUser.userId);
    if (mounted) {
      setState(() {
        _connectedUserIds = ids;
        _isLoading = false;
      });
    }
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a group name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one participant'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      await _firestoreService.createGroupConnection(
        creatorUserId: widget.currentUser.userId,
        selectedUserIds: _selectedIds.toList(),
        name: name,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group created'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create group: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Group name',
                      hintText: 'Enter group name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select participants',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _connectedUserIds.isEmpty
                      ? const Center(
                          child: Text(
                            'No connections yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _connectedUserIds.length,
                          itemBuilder: (context, index) {
                            final userId = _connectedUserIds[index];
                            return _ParticipantTile(
                              userId: userId,
                              isSelected: _selectedIds.contains(userId),
                              onTap: () {
                                setState(() {
                                  if (_selectedIds.contains(userId)) {
                                    _selectedIds.remove(userId);
                                  } else {
                                    _selectedIds.add(userId);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isCreating ? null : _createGroup,
                      child: _isCreating
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Create group'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.userId,
    required this.isSelected,
    required this.onTap,
  });

  final String userId;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return StreamBuilder<Map<String, dynamic>?>(
      stream: firestoreService.userProfileStream(userId),
      builder: (context, snapshot) {
        final user = snapshot.hasData && snapshot.data != null
            ? User.fromFirestore(snapshot.data!, userId)
            : User(userId: userId, email: '', username: userId);

        return CheckboxListTile(
          value: isSelected,
          onChanged: (_) => onTap(),
          secondary: ProfileAvatar(user: user, radius: 24),
          title: Text(user.username),
          subtitle: user.email.isNotEmpty ? Text(user.email) : null,
        );
      },
    );
  }
}
