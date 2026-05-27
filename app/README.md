# Orbit

A new Flutter project.

## Firebase setup

API keys are **not** in git. They live in **GitHub repository secrets** (for CI) and in each developer’s gitignored `app/.env` (same variable names as secrets — get values from a teammate or Firebase Console).

1. Copy `app/.env.example` → `app/.env` and fill in `FIREBASE_*` values.
2. Generate native config (gitignored): from `app/`, run `.\scripts\write_firebase_native_config.ps1` (Windows) or `bash scripts/write_firebase_native_config.sh` after exporting those env vars (e.g. from `.env`).
3. Run the app: `flutter run --dart-define-from-file=.env`

CI uses the same `FIREBASE_*` secret names; see `.github/workflows/ci.yml`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
