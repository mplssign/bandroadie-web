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

/// Provider for the user's calendar subscription URL
final calendarSubscriptionUrlProvider = FutureProvider<String?>((ref) async {
  final service = ref.watch(calendarSubscriptionServiceProvider);
  return service.getSubscriptionUrl();
});

class CalendarSubscriptionService {
  final SupabaseClient _client;

  // Base URL for the calendar feed Edge Function
  static const String _feedBaseUrl =
      'https://nekwjxvgbveheooyorjo.supabase.co/functions/v1/calendar-feed';

  CalendarSubscriptionService(this._client);

  /// Get the user's calendar subscription URL
  /// Returns null if user is not authenticated
  Future<String?> getSubscriptionUrl() async {
    try {
      final token = await _getOrCreateToken();
      if (token == null) return null;

      return '$_feedBaseUrl?token=$token';
    } catch (e) {
      debugPrint('[CalendarSubscriptionService] Error getting subscription URL: $e');
      return null;
    }
  }

  /// Get or create the user's calendar token
  Future<String?> _getOrCreateToken() async {
    try {
      final response = await _client.rpc('get_my_calendar_token');
      return response as String?;
    } catch (e) {
      debugPrint('[CalendarSubscriptionService] Error getting calendar token: $e');
      return null;
    }
  }

  /// Regenerate the calendar token (invalidates old subscription URLs)
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
