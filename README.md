# Mobile Messenger

A cross-platform Flutter messaging app with real-time chat, media sharing, and group conversations, powered by Firebase.

## Project overview

**Mobile Messenger** is a Flutter application that runs on **Android**, **iOS**, **Web**, **macOS**, and **Windows**. It provides:

- **Authentication** — Email/password sign-in, account creation, password reset, and email verification
- **Real-time messaging** — One-to-one and group chats with instant updates via Cloud Firestore
- **Media** — Send and view images and videos (with thumbnails); files are stored in Firebase Storage
- **Chat management** — Start new chats, archive conversations, accept or decline chat invites
- **Profile & account** — Display name and avatar, logout, and account deletion (with re-authentication)

The app uses **Firebase** (Authentication, Firestore, Storage) and **Provider** for state. The UI is built with Material Design 3 and adapts to mobile (bottom tabs) and web (tab bar in the app bar).

## Prerequisites

- **Flutter** SDK (stable channel), with Dart 3.9+
- **Firebase** project (see setup below)
- For **Android**: Android Studio / SDK; for **iOS**: Xcode (macOS); for **Web**: Chrome (for local run)

## Setup instructions

Setup is not required. You can [download](https://drive.google.com/file/d/1zzlY_Ccfnu1Og9vSu3dlyaly_rBXqp4v/view?usp=sharing) and install the android APK to use the app.

### 1. Clone and install dependencies

```bash
git clone <repository-url>
cd mobile-messenger
flutter pub get
```

### 2. Create and configure Firebase

1. Go to [Firebase Console](https://console.firebase.google.com/) and create a new project (or use an existing one).

2. Enable these services:
    - **Authentication** → Sign-in method → **Email/Password** (enable)
    - **Firestore Database** → Create database (start in test mode for development; set rules for production)
    - **Storage** → Get started (use default or custom rules)

3. Register your apps in the project:
    - **Android**: Add an Android app, use package name from `android/app/build.gradle.kts` (e.g. `com.example.web_messenger`). Download `google-services.json` and place it in `android/app/`.
    - **iOS**: Add an iOS app, use the bundle ID from Xcode. Download `GoogleService-Info.plist` and add it to the `ios/Runner` target in Xcode.
    - **Web**: Add a Web app, copy the `firebaseConfig` object. You will use it with FlutterFire CLI in the next step.

4. Install FlutterFire CLI and generate config:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

This creates/updates `lib/firebase_options.dart` and links your Flutter app to the Firebase project. If you already have `google-services.json` and `GoogleService-Info.plist` in place, keep them; FlutterFire will use them.

5. **Firestore rules** (minimal example for development; tighten for production):

- Allow read/write for authenticated users on the collections your app uses (e.g. `users`, `connections`, `messages`, `invites`, etc.), or use the rules that match your `FirestoreService` paths.

6. **Storage rules** (example):

- Allow read/write for authenticated users under your message-media path, or restrict by `request.auth != null` and path structure.

### 3. Run the app

```bash
# List devices
flutter devices

# Run on default device (phone, emulator, or Chrome)
flutter run

# Or specify target
flutter run -d chrome
flutter run -d android
flutter run -d ios
```

The first run may take a while while Gradle/Xcode build. If you see errors about missing Firebase config, run `flutterfire configure` again and ensure `lib/firebase_options.dart` exists and is committed (or documented for your team).

## Usage guide

### Sign in and account

- **Login**: Open the app → enter email and password → **Login**. If your email is not verified, you’ll see a reminder; use the link sent to your email to verify.
- **Create account**: On the login screen, tap **Create account** → enter email, password, and display name → **Create account**. Check your email for the verification link.
- **Forgot password**: On the login screen, tap **Forgot password?** → enter email → send reset link and check your inbox.

### Main tabs (after login)

- **Home** — Start a new chat (choose one or more participants for a group), see recent or suggested connections.
- **Chats** — List of active conversations (1:1 and groups). Tap a chat to open it; you can archive or remove connections from the list.
- **Archive** — Archived chats; you can restore or remove them.
- **Invites** — Incoming chat/group invites; accept or decline.
- **Account** — View or edit display name and avatar, **Logout**, or **Delete account** (you’ll be asked to re-enter your password).

### In a chat

- **Send text**: Type in the field at the bottom and send (e.g. Enter or send button).
- **Send image**: Use the image/photo button, pick from gallery (or camera on device), add optional caption and send.
- **Send video**: Use the attachment/file button, pick a video file; optional caption then send.
- **Search**: Use search in the chat to find messages; matching messages are highlighted briefly.
- **Profile**: Tap the other user’s (or group’s) avatar/name to open their profile popup.

### Tips

- Keep the app open or in background to receive real-time updates; Firestore listeners keep chats in sync.
- For production, configure Firestore and Storage security rules and, if needed, set up indexes for your queries (Firebase Console will suggest them when you hit limit errors).

## Project structure (high level)

- `lib/main.dart` — App entry, Firebase init, `MaterialApp`, auth wrapper (login vs home).
- `lib/screens/` — Login, create account, forgot password, home (tabs), chat, invites, account, etc.
- `lib/services/` — `AuthService`, `FirestoreService`, `StorageService`.
- `lib/providers/` — `UserProvider` (current user profile).
- `lib/models/` — User, message, connection, invite models.
- `lib/widgets/` — Reusable UI (e.g. avatars, media content, dialogs).
- `lib/firebase_options.dart` — Generated by `flutterfire configure`; do not edit by hand.

## License

Private project; see repository or author for terms.
