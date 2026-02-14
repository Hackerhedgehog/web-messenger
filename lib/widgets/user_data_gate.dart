import 'package:flutter/material.dart';

import '../models/user_model.dart';

/// Shows loading, error, or "no user" state; otherwise builds [child] with the user.
class UserDataGate extends StatelessWidget {
  const UserDataGate({
    super.key,
    required this.isLoading,
    this.error,
    this.user,
    required this.child,
  });

  final bool isLoading;
  final String? error;
  final User? user;
  final Widget Function(User user) child;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Error loading user data',
              style: TextStyle(fontSize: 18, color: Colors.red[300]),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                error!,
                style: TextStyle(color: Colors.red[300]),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    if (user == null) {
      return const Center(
        child: Text('No user data available', style: TextStyle(fontSize: 18)),
      );
    }

    return child(user!);
  }
}
