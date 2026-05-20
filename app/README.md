# tripsync

A new Flutter project.

## Firebase setup

Firebase client config is **not** committed (see repo `.gitignore`). Each developer:

1. In [Firebase Console](https://console.firebase.google.com/), open the TripSync project and download platform config files, **or** from `app/` run `flutterfire configure`.
2. Place files locally (gitignored):
   - `lib/firebase_options.dart` — copy from `lib/firebase_options.dart.example` and fill in, or use FlutterFire output.
   - `android/app/google-services.json` — from `google-services.json.example` template or Console.
   - `ios/Runner/GoogleService-Info.plist` — from `GoogleService-Info.plist.example` template or Console.

If keys were ever pushed to git, rotate them in Firebase Console → Project settings → Your apps.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
