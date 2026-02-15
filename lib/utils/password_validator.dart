/// Shared password validation used for create account and change password.
/// Returns an error message if invalid, or null if valid.
String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter a password';
  }
  if (value.length < 8) {
    return 'Password must be at least 8 characters';
  }
  if (!value.contains(RegExp(r'[a-z]'))) {
    return 'Password must contain at least 1 lowercase letter';
  }
  if (!value.contains(RegExp(r'[A-Z]'))) {
    return 'Password must contain at least 1 uppercase letter';
  }
  if (!value.contains(RegExp(r'[0-9]'))) {
    return 'Password must contain at least 1 digit';
  }
  if (!value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
    return 'Password must contain at least 1 special character';
  }
  return null;
}
