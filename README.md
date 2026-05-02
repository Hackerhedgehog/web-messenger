# Mobile Messenger

A cross-platform messaging app built with Flutter and Firebase. Chat one-on-one or in groups, send text and media (images, video, files), and manage connections and invites—all backed by Firebase Auth, Firestore, and Storage.

## Firebase status (read this first)

The **original Firebase project for this repository has been deleted.** What you see in the repo is **placeholder configuration only** so the project still **builds**; it will not connect to any live backend until you replace it.

To get a working app, you need your **own** Firebase project and you must set up:

- **Authentication** — at minimum **Email/Password** (the app uses sign up, login, verification, and password reset).
- **Cloud Firestore** — for users, chats, messages, invites, and related data.
- **Firebase Storage** — for profile images and message attachments (images, video, files).

After creating the project in the [Firebase Console](https://console.firebase.google.com), enable those products, configure security rules appropriate for your environment, then run **`flutterfire configure`** so Flutter generates real `lib/firebase_options.dart` and platform files (for example `android/app/google-services.json`). Replace every placeholder in `.firebaserc` and `firebase.json` with your project details if you use Firebase CLI hosting or other Firebase tooling.

## Project overview

- **Platforms:** Android, iOS, web, macOS, Windows (Flutter)
- **Backend:** Firebase (Authentication, Firestore, Storage)
- **Features:**
    - Email/password sign up and login, email verification, forgot password
    - **Home:** Search users by username or email; send 1:1 or group chat invites
    - **Chats:** List of active conversations (1:1 and groups). Long-press for options: view profile/participants, archive, remove connection (1:1), or leave group. FAB to create a new group from your connections
    - **Archive:** View and unarchive archived chats
    - **Invites:** Accept or decline incoming 1:1 and group invites
    - **Account:** Profile (username, avatar), logout, delete account
    - **Messaging:** Text plus images, video, and file attachments; profile avatars and popups

## Setup instructions

### Prerequisites

- **Flutter SDK** (3.9.2 or compatible). Install from [flutter.dev](https://flutter.dev) and ensure `flutter doctor` passes for your target platform(s).
- **Firebase project.** Create one at [Firebase Console](https://console.firebase.google.com).
- **FlutterFire CLI** (for linking the app to Firebase and generating config):

    ```bash
    dart pub global activate flutterfire_cli
    ```

    Ensure your `PATH` includes the Dart global cache (e.g. `~/.pub-cache/bin` or `$HOME/.pub-cache/bin`).

### 1. Clone and install dependencies

```bash
git clone <repository-url>
cd web-messenger
flutter pub get
```

### 2. Configure Firebase

This repository contains **placeholder** Firebase files until you run the steps below (see [Firebase status](#firebase-status-read-this-first)).

1. Log in to Firebase (if needed):

    ```bash
    firebase login
    ```

2. Link the project and generate Flutter/Firebase config:

    ```bash
    flutterfire configure
    ```

    This will:
    - Create or select a Firebase project
    - Register app(s) for the platforms you choose (e.g. Android, iOS, web)
    - Write `lib/firebase_options.dart` and platform files (e.g. `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`) so the app can connect to your Firebase project.

3. In Firebase Console, enable:
    - **Authentication** → Sign-in method → **Email/Password**
    - **Firestore Database** → Create database (start in test mode for local dev; then add proper security rules)
    - **Storage** → Get started (use default or custom rules)

4. (Optional) Deploy Firestore and Storage security rules from this repo if they are provided; otherwise configure rules in the Console.

### 3. Run the app

- **Chrome (web):**
    ```bash
    flutter run -d chrome
    ```
- **Android:**
    ```bash
    flutter run -d android
    ```
- **iOS (macOS only):**
    ```bash
    flutter run -d ios
    ```
- **Other devices:** Use `flutter devices` to see IDs, then `flutter run -d <device-id>`.

For release builds (e.g. web deploy):

```bash
flutter build web
```

Output is under `build/web`. The project’s `firebase.json` is set up to host the web app with Firebase Hosting (e.g. `firebase deploy --only hosting`).

---

## Usage guide

### Sign up and login

- Open the app → use **Create account** to register with email and password, or **Log in** if you already have an account.
- You can request a **Forgot password** link from the login screen.
- After sign up, check your email for verification; the app will show a notice until your email is verified.

### Finding people and sending invites

1. Go to the **Home** tab.
2. Type a **username or email** in the search box and run the search.
3. From the result you can:
    - **Send invite** to start a 1:1 connection (they’ll see it under Invites).
    - Open their **profile** (avatar/name) if needed.

### Managing invites

- Open the **Invites** tab to see pending 1:1 and group invites.
- For each invite you can **Accept** or **Decline**.
- Accepting a 1:1 invite creates a direct chat; accepting a group invite adds you to that group.

### Chats (1:1 and groups)

- **Chats** tab lists all active conversations (1:1 and groups).
- **Tap** a chat to open it and send messages.
- **Long-press** a chat for options:
    - **1:1:** View profile, Archive, Remove connection.
    - **Group:** View participants, Archive, Leave group.
- Use the **+** FAB to create a **new group**: pick a name, select contacts from your connections, then create. They receive a group invite they can accept or decline.

### Sending messages

- In a chat, type in the field at the bottom and send.
- Use the attachment/actions in the input area to send **images**, **video**, or **files** (behavior depends on the buttons in the chat screen).
- Tap a media message to open it (e.g. full-screen image/video) where supported.

### Archive and unarchive

- **Archive:** Long-press a chat in Chats → **Archive**. The chat moves to the Archive tab.
- **Unarchive:** In the **Archive** tab, long-press a chat and choose **Unarchive** to move it back to Chats.

### Account

- **Account** tab: view and edit profile (e.g. username, profile picture), **Logout**, or **Delete account**.
- Delete account will ask for confirmation and may ask for your password again; it removes your auth user and cleans up your data (connections, invites, profile).

### Leaving a group

- In **Chats**, long-press the **group chat** → **Leave group** → confirm. You are removed from the group and it disappears from your Chats list. Other members stay in the group.

---

## Project structure (high level)

- `lib/main.dart` – App entry, Firebase init, auth wrapper, routing to login/home.
- `lib/screens/` – Login, sign up, forgot password, home (tabs), chats, archive, invites, account, chat, group creation, search.
- `lib/services/` – Auth, Firestore (connections, messages, invites, groups), Storage (e.g. profile and media).
- `lib/providers/` – User state (e.g. `UserProvider`).
- `lib/models/` – User, connection, message, group invite.
- `lib/widgets/` – Avatars, profile popup, media viewer, dialogs.
- `lib/firebase_options.dart` – Normally generated by FlutterFire; this repo ships placeholders until you run `flutterfire configure`.

For new contributors: run `flutter analyze` and fix any reported issues. Configure your own Firebase project (Auth, Firestore, Storage) and regenerate options as described above.
