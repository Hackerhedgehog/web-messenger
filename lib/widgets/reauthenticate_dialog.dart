import 'package:flutter/material.dart';

/// Dialog that prompts for password for re-authentication (e.g. before account deletion, email/password change).
/// Returns the entered password, or null if cancelled.
Future<String?> showReauthenticateDialog(
  BuildContext context, {
  String message = 'For security, please enter your password to continue.',
}) async {
  final passwordController = TextEditingController();
  bool obscurePassword = true;
  String? errorMessage;

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Re-authentication Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setDialogState(() {
                      obscurePassword = !obscurePassword;
                    });
                  },
                ),
                errorText: errorMessage,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (passwordController.text.isNotEmpty) {
                  Navigator.of(context).pop(passwordController.text);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (passwordController.text.isEmpty) {
                setDialogState(() {
                  errorMessage = 'Please enter your password';
                });
              } else {
                Navigator.of(context).pop(passwordController.text);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ),
  );
}
