import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:bandroadie/app/constants/app_constants.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/services/band_service.dart';
import 'package:bandroadie/app/services/user_profile_service.dart';

// ============================================================================
// BUG REPORT EMAIL SERVICE
// Sends bug reports via Supabase Edge Function (Resend).
// No email client needed - sends directly from server.
// ============================================================================

/// Result of attempting to send a bug report email.
sealed class BugReportResult {}

/// Email sent successfully.
class BugReportSuccess extends BugReportResult {}

/// Failed to send - provides the report text for clipboard fallback.
class BugReportEmailAppNotFound extends BugReportResult {
  final String message;
  final String reportText;
  BugReportEmailAppNotFound(this.message, this.reportText);
}

/// Failed to send - provides the report text for clipboard fallback.
class BugReportLaunchFailed extends BugReportResult {
  final String message;
  final String reportText;
  BugReportLaunchFailed(this.message, this.reportText);
}

/// Service for sending bug reports via edge function.
class BugReportEmailService {
  /// Email recipient for all bug reports and feature requests.
  /// Uses centralized constant from app_constants.dart.
  /// NOTE: The edge function (send-bug-report) must use the same address.
  static const String recipientEmail = kSupportEmail;

  /// Send a bug report via edge function.
  ///
  /// [type] - 'bug' or 'feature'
  /// [description] - User-entered description
  /// [screenName] - Current screen/route name (optional)
  /// [bandId] - Active band ID (optional)
  ///
  /// Returns [BugReportResult] indicating success or failure.
  static Future<BugReportResult> send({
    required String type,
    required String description,
    String? screenName,
    String? bandId,
  }) async {
    try {
      debugPrint('[BugReport] ========================================');
      debugPrint(
        '[BugReport] Initiating ${type == 'bug' ? 'bug report' : 'feature request'} submission',
      );
      debugPrint('[BugReport] Target email: $recipientEmail');
      debugPrint('[BugReport] Sending via edge function...');

      // Get app info
      String appVersion = 'unknown';
      String buildNumber = 'unknown';
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        appVersion = packageInfo.version;
        buildNumber = packageInfo.buildNumber;
      } catch (e) {
        debugPrint('[BugReport] Failed to get package info: $e');
      }

      // Get user info
      String? userId;
      try {
        userId = supabase.auth.currentUser?.id;
      } catch (e) {
        debugPrint('[BugReport] Failed to get user: $e');
      }

      // Get platform info
      final platform = _getPlatformName();
      final osVersion = _getOsVersion();

      // Format local timestamp as "2:20 PM, Jan 1, 2026"
      final localTimestamp = _formatLocalTimestamp(DateTime.now());

      // Call edge function
      final response = await supabase.functions.invoke(
        'send-bug-report',
        body: {
          'type': type,
          'description': description,
          'screenName': screenName ?? 'Report Bugs',
          'bandId': bandId,
          'userId': userId,
          'platform': platform,
          'osVersion': osVersion,
          'appVersion': appVersion,
          'buildNumber': buildNumber,
          'localTimestamp': localTimestamp,
        },
      );

      if (response.status == 200) {
        debugPrint('[BugReport] ✓ Sent successfully to $recipientEmail');
        debugPrint('[BugReport] ========================================');
        return BugReportSuccess();
      } else {
        debugPrint(
          '[BugReport] ✗ Edge function returned status: ${response.status}',
        );
        debugPrint('[BugReport] ✗ Response data: ${response.data}');
        debugPrint('[BugReport] ========================================');
        final fallbackText = await buildReportText(
          type: type,
          description: description,
          screenName: screenName,
          bandId: bandId,
        );
        return BugReportLaunchFailed(
          'Failed to send report. Please try again or copy the report below.',
          fallbackText,
        );
      }
    } catch (e, stack) {
      debugPrint('[BugReport] ✗ Exception during send: $e');
      debugPrint('[BugReport] ✗ This could be:');
      debugPrint('[BugReport]   - Network connectivity issue');
      debugPrint('[BugReport]   - Edge function not deployed');
      debugPrint('[BugReport]   - RESEND_API_KEY not configured');
      debugPrint('[BugReport] Stack: $stack');
      debugPrint('[BugReport] ========================================');

      // Build report text for clipboard fallback
      String fallbackText;
      try {
        fallbackText = await buildReportText(
          type: type,
          description: description,
          screenName: screenName,
          bandId: bandId,
        );
      } catch (_) {
        fallbackText = 'Type: $type\n\n$description';
      }

      return BugReportLaunchFailed(
        'Error sending report: ${e.toString()}',
        fallbackText,
      );
    }
  }

  /// Build the full report text (for email body or clipboard).
  /// This is public so it can be used for clipboard fallback.
  static Future<String> buildReportText({
    required String type,
    required String description,
    String? screenName,
    String? bandId,
  }) async {
    // Get app info
    String appVersion = 'unknown';
    String buildNumber = 'unknown';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version;
      buildNumber = packageInfo.buildNumber;
    } catch (e) {
      debugPrint('[BugReportEmail] Failed to get package info: $e');
    }

    // Get user info
    String userId = 'not signed in';
    String userName = 'Unknown User';
    try {
      final user = supabase.auth.currentUser;
      userId = user?.id ?? 'not signed in';
      if (userId != 'not signed in') {
        final profile = await fetchUserProfileById(userId);
        if (profile != null) {
          userName = profile.fullName.isNotEmpty
              ? profile.fullName
              : profile.email;
        }
      }
    } catch (e) {
      debugPrint('[BugReportEmail] Failed to get user: $e');
    }

    // Get band info
    String bandName = 'none';
    if (bandId != null && bandId.isNotEmpty) {
      try {
        final band = await fetchBandById(bandId);
        if (band != null) {
          bandName = band.name;
        }
      } catch (e) {
        debugPrint('[BugReportEmail] Failed to get band: $e');
      }
    }

    // Get platform info
    final platform = _getPlatformName();
    final osVersion = _getOsVersion();

    // Get timestamp (local time, human readable)
    final now = DateTime.now();
    final timestamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    // Build the email body with user description first
    final buffer = StringBuffer();

    // User's description at the top
    buffer.writeln(description);
    buffer.writeln();
    buffer.writeln();

    // Diagnostic context appended at the bottom
    buffer.writeln('--- Diagnostic Info (auto-generated) ---');
    buffer.writeln('Type: ${type == 'bug' ? 'Bug Report' : 'Feature Request'}');
    buffer.writeln('Screen: ${screenName ?? 'Report Bugs'}');
    buffer.writeln('Band: $bandName');
    buffer.writeln('User: $userName');
    buffer.writeln('Platform: $platform');
    buffer.writeln('OS Version: $osVersion');
    buffer.writeln('App Version: $appVersion ($buildNumber)');
    buffer.writeln('Timestamp: $timestamp');

    return buffer.toString();
  }

  /// Get human-readable platform name.
  static String _getPlatformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// Get OS version string.
  static String _getOsVersion() {
    if (kIsWeb) return 'N/A';
    try {
      return Platform.operatingSystemVersion;
    } catch (e) {
      return 'unknown';
    }
  }

  /// Format local timestamp as "2:20 PM, Jan 1, 2026"
  static String _formatLocalTimestamp(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    int hours = date.hour;
    final minutes = date.minute;
    final ampm = hours >= 12 ? 'PM' : 'AM';
    hours = hours % 12;
    if (hours == 0) hours = 12; // 0 should be 12

    final minuteStr = minutes < 10 ? '0$minutes' : '$minutes';
    final month = months[date.month - 1]; // DateTime.month is 1-indexed
    final day = date.day;
    final year = date.year;

    return '$hours:$minuteStr $ampm, $month $day, $year';
  }
}
