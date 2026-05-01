import 'package:flutter/material.dart';

import '../models/user_model.dart';
import 'firebase_storage_image.dart';

/// Displays a user's profile picture with fallback when the image fails to load
/// (e.g. due to CORS on web). Use this instead of CircleAvatar +
/// getProfileImageProvider for reliable display across web and mobile.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.user,
    this.radius = 24,
    this.child,
  });

  final User user;
  final double radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final hasUrl = user.profilePictureUrl != null &&
        user.profilePictureUrl!.isNotEmpty;

    if (!hasUrl) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: const AssetImage('assets/default.png'),
        child: child,
      );
    }

    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipOval(
            child: FirebaseStorageImage(
              imageUrl: user.profilePictureUrl!,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              errorBuilder: (_) => Image(
                image: const AssetImage('assets/default.png'),
                fit: BoxFit.cover,
                width: radius * 2,
                height: radius * 2,
              ),
            ),
          ),
          if (child != null) Center(child: child!),
        ],
      ),
    );
  }
}
