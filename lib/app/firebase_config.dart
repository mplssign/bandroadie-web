import 'package:firebase_core/firebase_core.dart';

// ========================================
// FIREBASE CONFIGURATION (Web Only)
//
// All values injected at compile time via --dart-define.
// iOS/Android use native config files (GoogleService-Info.plist / google-services.json).
// ========================================

const FirebaseOptions firebaseWebOptions = FirebaseOptions(
  apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
  authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
  projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
  storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
  messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
  appId: String.fromEnvironment('FIREBASE_APP_ID'),
  measurementId: String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
);
