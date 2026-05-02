import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../models/connection_info.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../widgets/reauthenticate_dialog.dart';
import '../widgets/user_data_gate.dart';
import 'account_tab.dart';
import 'archive_tab.dart';
import 'chats_tab.dart';
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

  int _inviteCount = 0;
  int _connectionCount = 0;
  int _lastSeenInviteCount = 0;
  int _lastSeenConnectionCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showEmailVerificationSnackBarIfNeeded(),
    );
  }

  void _showEmailVerificationSnackBarIfNeeded() {
    if (!mounted) return;
    bool? verified = ModalRoute.of(context)?.settings.arguments as bool?;
    verified ??= Provider.of<UserProvider>(
      context,
      listen: false,
    ).takePendingEmailVerificationSnackBar();
    if (verified == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          verified
              ? 'Email verified.'
              : 'Email not verified. Check your inbox for the verification link.',
        ),
        backgroundColor: verified ? Colors.green : Colors.orange,
      ),
    );
  }

  void _onTabChanged() {
    if (!mounted) return;
    if (_tabController.index == 1) {
      _lastSeenConnectionCount = _connectionCount;
    } else if (_tabController.index == 3) {
      _lastSeenInviteCount = _inviteCount;
    }
    setState(() {});
  }

  void _onInviteCountChanged(int count) {
    if (_inviteCount != count) {
      _inviteCount = count;
      if (mounted) setState(() {});
    }
  }

  void _onConnectionCountChanged(int count) {
    if (_connectionCount != count) {
      _connectionCount = count;
      if (mounted) setState(() {});
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
      final profilePictureUrl = userProvider.currentUser?.profilePictureUrl;

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
          final password = await showReauthenticateDialog(
            context,
            message:
                'For security, please enter your password to confirm account deletion.',
          );

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
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Re-authentication failed: $reauthError'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        } else {
          // Some other error occurred
          rethrow;
        }
      }

      // Delete profile picture from Storage and clean up Firestore (connections,
      // invites, user profile) AFTER successful Auth deletion
      final storageService = StorageService();
      try {
        await storageService.deleteProfilePictureByUrl(profilePictureUrl);
      } catch (_) {
        // Best-effort cleanup only.
      }
      try {
        await _firestoreService.deleteUserWithConnectionsCleanup(userId);
      } catch (_) {
        // Best-effort cleanup only.
      }

      // Clear user data
      userProvider.clearUser();

      if (mounted) {
        await Navigator.of(context).maybePop();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await Navigator.of(context).maybePop();
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        userProvider.clearUser();
        try {
          await _authService.signOut();
        } catch (_) {}
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  Widget _buildTabBar(bool showChatBadge, bool showInviteBadge) {
    return TabBar(
      controller: _tabController,
      tabs: [
        const Tab(text: 'Home', icon: Icon(Icons.home)),
        Tab(
          text: 'Chats',
          icon: Badge(
            isLabelVisible: showChatBadge,
            child: const Icon(Icons.chat),
          ),
        ),
        const Tab(text: 'Archive', icon: Icon(Icons.archive)),
        Tab(
          text: 'Invites',
          icon: Badge(
            isLabelVisible: showInviteBadge,
            child: const Icon(Icons.mail),
          ),
        ),
        const Tab(text: 'Account', icon: Icon(Icons.person)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        return UserDataGate(
          isLoading: userProvider.isLoading,
          error: userProvider.error,
          user: userProvider.currentUser,
          child: (user) {
            return StreamBuilder<int>(
              stream: _firestoreService.totalInviteCountStream(user.userId),
              builder: (context, inviteSnapshot) {
                final inviteCount = inviteSnapshot.data ?? 0;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _onInviteCountChanged(inviteCount);
                });
                return StreamBuilder<List<ConnectionInfo>>(
                  stream: _firestoreService.connectionsForUserStream(
                    user.userId,
                  ),
                  builder: (context, connectionSnapshot) {
                    final connectionCount =
                        connectionSnapshot.data?.length ?? 0;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _onConnectionCountChanged(connectionCount);
                    });
                    final isOnInvitesTab = _tabController.index == 3;
                    final isOnChatsTab = _tabController.index == 1;
                    final showInviteBadge =
                        _inviteCount > _lastSeenInviteCount && !isOnInvitesTab;
                    final showChatBadge =
                        _connectionCount > _lastSeenConnectionCount &&
                        !isOnChatsTab;

                    final tabBar = _buildTabBar(showChatBadge, showInviteBadge);
                    final tabBarView = TabBarView(
                      controller: _tabController,
                      children: [
                        HomeTab(user: user),
                        ChatsTab(user: user),
                        ArchiveTab(user: user),
                        InvitesTab(user: user),
                        AccountTab(
                          user: user,
                          onLogout: _handleLogout,
                          onDeleteAccount: _handleDeleteAccount,
                        ),
                      ],
                    );

                    return Scaffold(
                      appBar: AppBar(
                        title: const Text('Mobile Messenger'),
                        automaticallyImplyLeading: false,
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.logout),
                            onPressed: _handleLogout,
                            tooltip: 'Logout',
                          ),
                        ],
                      ),
                      body: kIsWeb
                          ? tabBarView
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                tabBar,
                                Expanded(child: tabBarView),
                              ],
                            ),
                      bottomNavigationBar: kIsWeb ? tabBar : null,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
