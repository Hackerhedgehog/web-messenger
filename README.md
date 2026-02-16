# web_messenger

A new Flutter project.

## Firebase Storage CORS (for web)

Profile pictures and **video messages** require CORS configuration. Without it, browsers block cross-origin requests and videos will show a loading spinner indefinitely. To fix:

1. **Install Google Cloud CLI** if needed: https://cloud.google.com/sdk/docs/install

2. **Log in and set project**:
   ```bash
   gcloud auth login
   gcloud config set project web-messenger-10d20
   ```

3. **Find your Storage bucket name** in Firebase Console → Storage → bucket URL (e.g. `web-messenger-10d20.firebasestorage.app` or `web-messenger-10d20.appspot.com`).

4. **Apply CORS** (use your actual bucket name):
   ```bash
   gcloud storage buckets update gs://web-messenger-10d20.appspot.com --cors-file=storage_cors.json
   ```
   If your bucket is `web-messenger-10d20.firebasestorage.app`, use that instead.

5. **Verify** (optional):
   ```bash
   gcloud storage buckets describe gs://web-messenger-10d20.appspot.com --format="default(cors_config)"
   ```

6. **Hard refresh** the web app (Ctrl+Shift+R) after applying CORS.

For production, restrict `origin` in `storage_cors.json` to your domain instead of `["*"]`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
