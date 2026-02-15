import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class UserProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  User? _currentUser;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<Map<String, dynamic>?>? _profileSubscription;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  String? get error => _error;

  void _safeNotifyListeners() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_profileSubscription != null) {
        notifyListeners();
      }
    });
  }

  /// Listens to user profile changes in Firestore. Updates [currentUser]
  /// whenever the profile document changes.
  void listenToUserProfile(String userId) {
    _profileSubscription?.cancel();
    _isLoading = true;
    _error = null;
    _currentUser = null;
    _safeNotifyListeners();

    _profileSubscription = _firestoreService
        .userProfileStream(userId)
        .listen(
          (userData) async {
            if (userData != null) {
              _currentUser = User.fromFirestore(userData, userId);
              _error = null;
              // Sync Auth email to Firestore if user verified a new email
              final authEmail = _authService.currentUser?.email;
              final firestoreEmail = userData['email'] as String?;
              if (authEmail != null &&
                  firestoreEmail != null &&
                  authEmail != firestoreEmail) {
                try {
                  await _firestoreService.updateUserProfile(
                    userId: userId,
                    data: {'email': authEmail},
                  );
                } catch (_) {
                  // Ignore sync errors
                }
              }
            } else {
              _error = 'User profile not found';
              _currentUser = null;
            }
            _isLoading = false;
            _safeNotifyListeners();
          },
          onError: (e) {
            _error = e.toString();
            _currentUser = null;
            _isLoading = false;
            _safeNotifyListeners();
          },
        );
  }

  /// Clear user data and stop listening. Call on logout.
  void clearUser() {
    _profileSubscription?.cancel();
    _profileSubscription = null;
    _currentUser = null;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }
}
