import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream (cached so StreamBuilder doesn't re-subscribe on rebuilds and get stuck in ConnectionState.waiting)
  Stream<User?>? _authStateChanges;
  Stream<User?> get authStateChanges =>
      _authStateChanges ??= _auth.authStateChanges();

  // Sign in with email and password. Rejects if the user's email is not verified.
  Future<UserCredential?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user != null && !user.emailVerified) {
        await _auth.signOut();
        throw 'Please verify your email before signing in. Check your inbox for the verification link.';
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      if (e.toString().startsWith('Please verify your email')) rethrow;
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  // Create account with email and password; sends a verification email to the user.
  Future<UserCredential?> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Re-authenticate user with password
  Future<void> reauthenticateWithPassword(String password) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'No user is currently signed in.';
      }

      if (user.email == null) {
        throw 'User email is not available.';
      }

      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );

      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw e.toString();
    }
  }

  // Delete user account
  Future<void> deleteUser() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.delete();
      } else {
        throw 'No user is currently signed in.';
      }
    } on FirebaseAuthException catch (e) {
      // Check if re-authentication is required
      if (e.code == 'requires-recent-login') {
        throw 'requires-recent-login';
      }
      throw _handleAuthException(e);
    } catch (e) {
      // Re-throw requires-recent-login as-is
      if (e.toString() == 'requires-recent-login') {
        rethrow;
      }
      throw e.toString();
    }
  }

  // Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'user-not-found':
        return 'No user found for that email.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'too-many-requests':
        return 'Too many requests. Please try again later.';
      case 'operation-not-allowed':
        return 'This operation is not allowed.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'requires-recent-login':
        return 'This operation requires recent authentication. Please log in again.';
      default:
        return e.message ?? 'An error occurred during authentication.';
    }
  }
}
