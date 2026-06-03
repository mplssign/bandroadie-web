// ============================================================================
// DEMO CREDENTIALS
// Compile-time constants for Play Store review access.
//
// The email is public — it appears in the Play Store App Access declaration.
// The password is injected at build time via --dart-define=DEMO_PASSWORD.
// It must NOT be a string literal in source code.
//
// Demo band: The Banana Stand (band_id: 9187f897-1731-4337-bbd3-4f80afbe88ec)
// ============================================================================

/// Email address for the Play Store demo account.
const String kDemoEmail = 'bandroadie2026@gmail.com';

/// Password for the Play Store demo account.
/// Injected at compile time via --dart-define=DEMO_PASSWORD.
/// An empty defaultValue causes demo login to fail safely if the define is absent.
const String kDemoPassword = String.fromEnvironment(
  'DEMO_PASSWORD',
  defaultValue: '',
);
