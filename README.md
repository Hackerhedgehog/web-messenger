# web_messenger

A new Flutter project.

## Firebase Storage CORS (for web)

Profile pictures from Firebase Storage may not load on web due to CORS. To fix:

1. Create or use the `storage_cors.json` in this project.
2. Apply it to your Storage bucket:
   ```bash
   gcloud storage buckets update gs://YOUR_PROJECT_ID.appspot.com --cors-file=storage_cors.json
   ```
   Replace `YOUR_PROJECT_ID` with your Firebase project ID (e.g. `web-messenger-10d20`).

For production, restrict `origin` in `storage_cors.json` to your domain instead of `["*"]`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
