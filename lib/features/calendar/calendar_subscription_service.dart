import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// CALENDAR SUBSCRIPTION SERVICE
// Manages calendar subscription tokens, URLs, and feed preferences.
// ============================================================================

// ----------------------------------------------------------------------------
// Feed preferences model
// ----------------------------------------------------------------------------

class CalendarFeedPreferences {
  final bool includeGigs;
  final bool includeRehearsal;
  final bool includeBlockouts;
  final bool includePotentialGigs;
  final bool includePotentialRehearsal;

  const CalendarFeedPreferences({
    this.includeGigs = true,
    this.includeRehearsal = true,
    this.includeBlockouts = false,
    this.includePotentialGigs = false,
    this.includePotentialRehearsal = false,
  });

  CalendarFeedPreferences copyWith({
    bool? includeGigs,
    bool? includeRehearsal,
    bool? includeBlockouts,
    bool? includePotentialGigs,
    bool? includePotentialRehearsal,
  }) =>
      CalendarFeedPreferences(
        includeGigs: includeGigs ?? this.includeGigs,
        includeRehearsal: includeRehearsal ?? this.includeRehearsal,
        includeBlockouts: includeBlockouts ?? this.includeBlockouts,
        includePotentialGigs: includePotentialGigs ?? this.includePotentialGigs,
        includePotentialRehearsal:
            includePotentialRehearsal ?? this.includePotentialRehearsal,
      );

  factory CalendarFeedPreferences.fromJson(Map<String, dynamic> json) =>
      CalendarFeedPreferences(
        includeGigs: json['include_gigs'] as bool? ?? true,
        includeRehearsal: json['include_rehearsals'] as bool? ?? true,
        includeBlockouts: json['include_blockouts'] as bool? ?? false,
        includePotentialGigs: json['include_potential_gigs'] as bool? ?? false,
        includePotentialRehearsal:
            json['include_potential_rehearsals'] as bool? ?? false,
      );
}

// ----------------------------------------------------------------------------
// Providers
// ----------------------------------------------------------------------------

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

/// Band-scoped feed preferences provider (family by bandId)
final calendarBandPreferencesProvider =
    FutureProvider.family<CalendarFeedPreferences, String>((ref, bandId) async {
  final service = ref.watch(calendarSubscriptionServiceProvider);
  return service.getBandSubscriptionPreferences(bandId);
});

// ----------------------------------------------------------------------------
// Service
// ----------------------------------------------------------------------------

class CalendarSubscriptionService {
  final SupabaseClient _client;

  // Base URL for the calendar feed — proxied through Vercel for trusted SSL
  static const String _feedBaseUrl =
      'https://app.bandroadie.com/api/calendar-feed';

  CalendarSubscriptionService(this._client);

  // --------------------------------------------------------------------------
  // URL methods
  // --------------------------------------------------------------------------

  /// [DEPRECATED] Get the user's legacy calendar subscription URL
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

  // --------------------------------------------------------------------------
  // Feed preference methods
  // --------------------------------------------------------------------------

  /// Fetch the current feed preferences for a band subscription.
  /// The subscription row is auto-created on first URL fetch, so this should
  /// always find a row after [getBandSubscriptionUrl] has been called.
  Future<CalendarFeedPreferences> getBandSubscriptionPreferences(
      String bandId) async {
    final user = _client.auth.currentUser;
    if (user == null) return const CalendarFeedPreferences();

    try {
      final data = await _client
          .from('band_calendar_subscriptions')
          .select(
            'include_gigs, include_rehearsals, include_blockouts, '
            'include_potential_gigs, include_potential_rehearsals',
          )
          .eq('user_id', user.id)
          .eq('band_id', bandId)
          .maybeSingle();

      if (data == null) return const CalendarFeedPreferences();
      return CalendarFeedPreferences.fromJson(data);
    } catch (e) {
      debugPrint(
          '[CalendarSubscriptionService] Error getting preferences: $e');
      return const CalendarFeedPreferences();
    }
  }

  /// Persist feed preferences for a band subscription.
  /// Uses an RPC that auto-creates the row if it doesn't exist yet.
  Future<void> updateBandSubscriptionPreferences(
    String bandId,
    CalendarFeedPreferences prefs,
  ) async {
    try {
      await _client.rpc(
        'update_band_calendar_preferences',
        params: {
          'p_band_id': bandId,
          'p_include_gigs': prefs.includeGigs,
          'p_include_rehearsals': prefs.includeRehearsal,
          'p_include_blockouts': prefs.includeBlockouts,
          'p_include_potential_gigs': prefs.includePotentialGigs,
          'p_include_potential_rehearsals': prefs.includePotentialRehearsal,
        },
      );
    } catch (e) {
      debugPrint(
          '[CalendarSubscriptionService] Error updating preferences: $e');
      rethrow;
    }
  }

  // --------------------------------------------------------------------------
  // Legacy / private
  // --------------------------------------------------------------------------

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
