import 'package:package_info_plus/package_info_plus.dart';

/// Service to provide app version info dynamically from pubspec.yaml.
///
/// Versioning strategy:
/// - Display version uses the release date in YY.M.D format with no month/day zero-padding.
///   Example: 26.8.26 for Aug 26, 2026.
/// - Build numbers follow the date-based formula date_num * 100 + same_day_counter,
///   where date_num = YY * 10000 + MM * 100 + DD and same_day_counter starts at 01.
///   Example: 26.8.26+26082601 and then 26.8.26+26082602 on the same day.
/// - The runtime code remains format-agnostic: it reads the platform package metadata
///   and prints the version/build values without parsing semver or date math.
///
/// DEPLOYMENT IDENTIFIER (Web only):
/// On web builds, a commit SHA suffix is appended to help identify the exact
/// deployment. This is injected via --dart-define at build time and is the
/// source of truth for which code is running in the browser. Format:
///   "Version YY.M.D (Build N) • abc123"
/// where abc123 is the first 6 chars of the Git commit SHA.
class AppVersionService {
  static PackageInfo? _packageInfo;

  /// Commit SHA injected at build time via --dart-define=COMMIT_SHA=...
  /// This is only populated for web builds via Vercel. Local/native builds
  /// will have an empty string.
  static const String _commitSha = String.fromEnvironment('COMMIT_SHA');

  /// Initialize the service (call once at app startup)
  static Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  /// Get the formatted version string for display
  /// Returns "Version 1.0.2 (Build 4)" for native builds
  /// Returns "Version 1.0.2 (Build 4) • abc123" for web builds with commit SHA
  static String get displayVersion {
    if (_packageInfo == null) {
      return 'Version --';
    }
    final base =
        'Version ${_packageInfo!.version} (Build ${_packageInfo!.buildNumber})';

    // Append commit SHA suffix for web deployments (first 6 chars)
    if (_commitSha.isNotEmpty) {
      final shortSha = _commitSha.length >= 6
          ? _commitSha.substring(0, 6)
          : _commitSha;
      return '$base • $shortSha';
    }

    return base;
  }

  /// Get just the version number (e.g., "1.0.2")
  static String get version => _packageInfo?.version ?? '--';

  /// Get just the build number (e.g., "4")
  static String get buildNumber => _packageInfo?.buildNumber ?? '--';

  /// Get the full version with build (e.g., "1.0.2+4")
  static String get fullVersion {
    if (_packageInfo == null) return '--';
    return '${_packageInfo!.version}+${_packageInfo!.buildNumber}';
  }

  /// Get the commit SHA (empty string if not available)
  static String get commitSha => _commitSha;

  /// Get the short commit SHA (first 6 chars) or empty string
  static String get shortCommitSha {
    if (_commitSha.isEmpty) return '';
    return _commitSha.length >= 6 ? _commitSha.substring(0, 6) : _commitSha;
  }
}
