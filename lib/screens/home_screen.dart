import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/reauthenticate_dialog.dart';
import '../widgets/user_data_gate.dart';
import 'account_tab.dart';
import 'home_tab.dart';
import 'invites_tab.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.index == 2) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final userId = _authService.currentUser?.uid;
      if (userId != null) {
        userProvider.loadUserData(userId);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    try {
      await _authService.signOut();
      if (mounted) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        userProvider.clearUser();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone. All your data will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final userId = userProvider.currentUser?.userId;

      if (userId == null) {
        throw 'No user data available';
      }

      // Delete from Firebase Auth FIRST
      try {
        await _authService.deleteUser();
      } catch (e) {
        // Check if re-authentication is required
        final errorString = e.toString();
        if (errorString == 'requires-recent-login' ||
            errorString.contains('requires-recent-login')) {
          // Close loading dialog
          if (mounted) {
            Navigator.of(context).pop();
          }

          // Show password dialog for re-authentication (guard context after async)
          if (!mounted) return;
          final password = await showReauthenticateDialog(context);

          if (password == null || !mounted) {
            // User cancelled password dialog
            return;
          }

          // Show loading dialog again
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) =>
                  const Center(child: CircularProgressIndicator()),
            );
          }

          try {
            // Re-authenticate user
            await _authService.reauthenticateWithPassword(password);

            // Retry Auth deletion after re-authentication
            await _authService.deleteUser();
          } catch (reauthError) {
            // Close loading dialog
            if (mounted) {
              Navigator.of(context).pop();
            }

            throw 'Re-authentication failed: $reauthError';
          }
        } else {
          // Some other error occurred
          rethrow;
        }
      }

      // Only delete from Firestore AFTER successful Auth deletion
      await _firestoreService.deleteUserProfile(userId);

      // Clear user data
      userProvider.clearUser();

      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();

        // Navigate to login screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Close loading dialog if still open
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JoinTheFun'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          return UserDataGate(
            isLoading: userProvider.isLoading,
            error: userProvider.error,
            user: userProvider.currentUser,
            child: (user) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'Home', icon: Icon(Icons.home)),
                      Tab(text: 'Invites', icon: Icon(Icons.mail)),
                      Tab(text: 'Account', icon: Icon(Icons.person)),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        HomeTab(user: user),
                        const InvitesTab(),
                        AccountTab(
                          user: user,
                          onLogout: _handleLogout,
                          onDeleteAccount: _handleDeleteAccount,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
