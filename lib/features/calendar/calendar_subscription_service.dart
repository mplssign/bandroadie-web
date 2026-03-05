import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// CALENDAR SUBSCRIPTION SERVICE
// Manages calendar subscription tokens and URLs for ICS feed access
// ============================================================================

/// Provider for CalendarSubscriptionService
final calendarSubscriptionServiceProvider =
    Provider<CalendarSubscriptionService>((ref) {
  return CalendarSubscriptionService(Supabase.instance.client);
});

/// [DEPRECATED] Legacy user-scoped provider — kept for backward compatibility.
/// Use calendarBandSubscriptionUrlProvider instead.
final calendarSubscriptionUrlProvider = FutureProvider<String?>((ref) async {
  final service = ref.watch(calendarSubscriptionServiceProvider);
  return service.getSubscriptionUrl();
});

/// Band-scoped subscription URL provider (family by bandId)
final calendarBandSubscriptionUrlProvider =
    FutureProvider.family<String?, String>((ref, bandId) async {
  final service = ref.watch(calendarSubscriptionServiceProvider);
  return service.getBandSubscriptionUrl(bandId);
});

class CalendarSubscriptionService {
  final SupabaseClient _client;

  // Base URL for the calendar feed — proxied through Vercel for trusted SSL
  static const String _feedBaseUrl = 'https://bandroadie.com/api/calendar-feed';

  CalendarSubscriptionService(this._client);

  /// [DEPRECATED] Get the user's legacy calendar subscription URL
  /// Returns null if user is not authenticated
  Future<String?> getSubscriptionUrl() async {
    try {
      final token = await _getOrCreateToken();
      if (token == null) return null;

      return '$_feedBaseUrl?token=$token';
    } catch (e) {
      debugPrint(
          '[CalendarSubscriptionService] Error getting subscription URL: $e');
      return null;
    }
  }

  /// Get a band-scoped calendar subscription URL
  Future<String?> getBandSubscriptionUrl(String bandId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final token = await _client.rpc(
      'get_band_calendar_token',
      params: {'p_band_id': bandId},
    );
    if (token == null) return null;
    return '$_feedBaseUrl?token=$token';
  }

  /// Regenerate the band-scoped calendar token (invalidates old URL)
  /// Returns the new subscription URL
  Future<String?> regenerateBandToken(String bandId) async {
    try {
      final newToken = await _client.rpc(
        'regenerate_band_calendar_token',
        params: {'p_band_id': bandId},
      );
      if (newToken == null) return null;
      return '$_feedBaseUrl?token=$newToken';
    } catch (e) {
      debugPrint(
          '[CalendarSubscriptionService] Error regenerating band token: $e');
      return null;
    }
  }

  /// Get or create the user's legacy calendar token
  Future<String?> _getOrCreateToken() async {
    try {
      final response = await _client.rpc('get_my_calendar_token');
      return response as String?;
    } catch (e) {
      debugPrint(
          '[CalendarSubscriptionService] Error getting calendar token: $e');
      return null;
    }
  }

  /// [DEPRECATED] Regenerate the legacy calendar token
  /// Returns the new subscription URL
  Future<String?> regenerateToken() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;

      final newToken = await _client.rpc(
        'regenerate_calendar_token',
        params: {'p_user_id': userId},
      );

      if (newToken == null) return null;
      return '$_feedBaseUrl?token=$newToken';
    } catch (e) {
      debugPrint('[CalendarSubscriptionService] Error regenerating token: $e');
      return null;
    }
  }
}
