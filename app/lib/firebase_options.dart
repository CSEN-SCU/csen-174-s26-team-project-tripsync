// Firebase client config via --dart-define or bundled app/.env (see .env.example).
// Native Android/iOS files: bash scripts/write_firebase_native_config.sh
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'tripsync_groq_config.dart';

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static FirebaseOptions get android => FirebaseOptions(
        apiKey: appConfigValueRequired('FIREBASE_ANDROID_API_KEY'),
        appId: appConfigValueRequired('FIREBASE_ANDROID_APP_ID'),
        messagingSenderId: appConfigValueRequired('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: appConfigValueRequired('FIREBASE_PROJECT_ID'),
        storageBucket: appConfigValueRequired('FIREBASE_STORAGE_BUCKET'),
      );

  static FirebaseOptions get ios => FirebaseOptions(
        apiKey: appConfigValueRequired('FIREBASE_IOS_API_KEY'),
        appId: appConfigValueRequired('FIREBASE_IOS_APP_ID'),
        messagingSenderId: appConfigValueRequired('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: appConfigValueRequired('FIREBASE_PROJECT_ID'),
        storageBucket: appConfigValueRequired('FIREBASE_STORAGE_BUCKET'),
        iosClientId: appConfigValueRequired('FIREBASE_IOS_CLIENT_ID'),
        iosBundleId: appConfigValueRequired('FIREBASE_IOS_BUNDLE_ID'),
      );
}
