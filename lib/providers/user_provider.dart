import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

class UserProvider extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  String? get error => _error;

  /// Load user data from Firestore
  Future<void> loadUserData(String userId) async {
    _isLoading = true;
    _error = null;
    //notifyListeners();

    try {
      final userData = await _firestoreService.getUserProfile(userId);

      if (userData != null) {
        _currentUser = User.fromFirestore(userData, userId);
        _error = null;
      } else {
        _error = 'User profile not found';
        _currentUser = null;
      }
    } catch (e) {
      _error = e.toString();
      _currentUser = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear user data on logout
  void clearUser() {
    _currentUser = null;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }
}
