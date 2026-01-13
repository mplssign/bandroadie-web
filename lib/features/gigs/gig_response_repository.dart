import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import '../bands/active_band_controller.dart';
import 'gig_controller.dart';

// ============================================================================
// GIG RESPONSE REPOSITORY
// Handles all gig response (RSVP) data operations.
//
// BAND ISOLATION: All queries require bandId and enforce band-scoped access.
// ============================================================================

/// Error class for gig response operations with user-friendly messages
class GigResponseError implements Exception {
  final String message;
  final String userMessage;
  final bool isRetryable;

  const GigResponseError({
    required this.message,
    required this.userMessage,
    this.isRetryable = false,
  });

  factory GigResponseError.fromException(Exception e) {
    final message = e.toString().toLowerCase();

    // Check for specific error types
    if (message.contains('permission denied') ||
        message.contains('rls') ||
        message.contains('policy') ||
        message.contains('not authorized')) {
      return GigResponseError(
        message: e.toString(),
        userMessage:
            'You don\'t have permission to update this response. Try refreshing the app.',
        isRetryable: false,
      );
    }

    if (message.contains('network') ||
        message.contains('timeout') ||
        message.contains('connection')) {
      return GigResponseError(
        message: e.toString(),
        userMessage: 'Network issue — check your connection and try again.',
        isRetryable: true,
      );
    }

    // Generic error
    return GigResponseError(
      message: e.toString(),
      userMessage: 'Something went wrong — try again in a moment.',
      isRetryable: true,
    );
  }

  @override
  String toString() => 'GigResponseError: $message';
}

/// Summary of responses for a potential gig
class GigResponseSummary {
  final int yesCount;
  final int noCount;
  final int notRespondedCount;
  final int totalMembers;

  const GigResponseSummary({
    required this.yesCount,
    required this.noCount,
    required this.notRespondedCount,
    required this.totalMembers,
  });

  /// Create empty summary
  const GigResponseSummary.empty()
    : yesCount = 0,
      noCount = 0,
      notRespondedCount = 0,
      totalMembers = 0;

  @override
  String toString() =>
      'GigResponseSummary(yes: $yesCount, no: $noCount, notResponded: $notRespondedCount)';
}

/// A potential gig that needs the user's response
class PendingPotentialGig {
  final String gigId;
  final String bandId;
  final String name;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String location;

  const PendingPotentialGig({
    required this.gigId,
    required this.bandId,
    required this.name,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.location,
  });

  factory PendingPotentialGig.fromJson(Map<String, dynamic> json) {
    return PendingPotentialGig(
      gigId: json['id'] as String,
      bandId: json['band_id'] as String,
      name: json['name'] as String,
      date: DateTime.parse(json['date'] as String),
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      location: json['location'] as String? ?? '',
    );
  }
}

class GigResponseRepository {
  /// Fetch all potential gigs for a band where the current user has NOT responded yet.
  /// Ordered by date + start_time (earliest first).
  Future<List<PendingPotentialGig>> fetchPendingPotentialGigs({
    required String bandId,
    required String userId,
  }) async {
    debugPrint(
      '[GigResponseRepository] fetchPendingPotentialGigs: bandId=$bandId, userId=$userId',
    );

    // Get today's date for filtering (only future/today gigs)
    final today = DateTime.now().toIso8601String().split('T')[0];
    debugPrint('[GigResponseRepository] Filtering gigs >= $today');

    // Fetch all potential gigs for the band
    final gigsResponse = await supabase
        .from('gigs')
        .select('id, band_id, name, date, start_time, end_time, location')
        .eq('band_id', bandId)
        .eq('is_potential', true)
        .gte('date', today)
        .order('date', ascending: true)
        .order('start_time', ascending: true);

    debugPrint(
      '[GigResponseRepository] Found ${gigsResponse.length} potential gigs',
    );
    for (final gig in gigsResponse) {
      debugPrint(
        '[GigResponseRepository]   - ${gig['name']} on ${gig['date']}',
      );
    }

    if (gigsResponse.isEmpty) {
      debugPrint(
        '[GigResponseRepository] No potential gigs found, returning empty',
      );
      return [];
    }

    // Get all gig IDs
    final gigIds = gigsResponse.map((g) => g['id'] as String).toList();

    // Fetch user's responses for these gigs
    final responsesResponse = await supabase
        .from('gig_responses')
        .select('gig_id, response')
        .eq('user_id', userId)
        .inFilter('gig_id', gigIds);

    debugPrint(
      '[GigResponseRepository] User has ${responsesResponse.length} responses',
    );
    for (final r in responsesResponse) {
      debugPrint(
        '[GigResponseRepository]   - gig ${r['gig_id']}: ${r['response']}',
      );
    }

    // Build set of gigs user has responded to
    final respondedGigIds = <String>{};
    for (final r in responsesResponse) {
      final response = r['response'] as String?;
      // Only count as responded if they have a yes/no response
      if (response == 'yes' || response == 'no') {
        respondedGigIds.add(r['gig_id'] as String);
      }
    }

    // Filter out gigs user has already responded to
    final pendingGigs = <PendingPotentialGig>[];
    for (final gig in gigsResponse) {
      final gigId = gig['id'] as String;
      if (!respondedGigIds.contains(gigId)) {
        pendingGigs.add(PendingPotentialGig.fromJson(gig));
      }
    }

    debugPrint(
      '[GigResponseRepository] Returning ${pendingGigs.length} pending gigs',
    );

    return pendingGigs;
  }

  /// Get the current user's response for a specific gig.
  /// Returns 'yes', 'no', or null if not responded.
  Future<String?> fetchUserResponse({
    required String gigId,
    required String userId,
  }) async {
    final response = await supabase
        .from('gig_responses')
        .select('response')
        .eq('gig_id', gigId)
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return response['response'] as String?;
  }

  /// Submit or update the user's response for a gig.
  /// Uses upsert on (gig_id, user_id) constraint.
  /// Upserts a gig response with automatic retry on transient failures.
  /// Throws [GigResponseError] with user-friendly message on failure.
  Future<void> upsertResponse({
    required String gigId,
    required String bandId,
    required String userId,
    required String response, // 'yes' or 'no'
  }) async {
    debugPrint(
      '[GigResponseRepository] upsertResponse: gigId=$gigId, bandId=$bandId, userId=$userId, response=$response',
    );

    // Retry up to 3 times with exponential backoff for transient errors
    const maxRetries = 3;
    Exception? lastError;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _performUpsert(gigId: gigId, userId: userId, response: response);
        debugPrint(
          '[GigResponseRepository] upsertResponse succeeded on attempt $attempt',
        );
        return; // Success!
      } catch (e, stackTrace) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('[GigResponseRepository] Attempt $attempt failed: $e');
        debugPrint('[GigResponseRepository] Stack trace: $stackTrace');

        // Don't retry on non-transient errors (permission denied, etc.)
        if (_isNonRetryableError(e)) {
          debugPrint('[GigResponseRepository] Non-retryable error, stopping');
          break;
        }

        // Wait before retry (100ms, 200ms, 400ms)
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 100 * (1 << (attempt - 1)));
          debugPrint(
            '[GigResponseRepository] Retrying in ${delay.inMilliseconds}ms...',
          );
          await Future.delayed(delay);
        }
      }
    }

    // All retries failed
    throw GigResponseError.fromException(lastError!);
  }

  /// Internal method to perform the actual upsert
  Future<void> _performUpsert({
    required String gigId,
    required String userId,
    required String response,
  }) async {
    // Check if a response already exists
    final existing = await supabase
        .from('gig_responses')
        .select('id')
        .eq('gig_id', gigId)
        .eq('user_id', userId)
        .maybeSingle();

    final now = DateTime.now().toUtc().toIso8601String();

    if (existing != null) {
      // Update existing response
      debugPrint('[GigResponseRepository] Updating existing response');
      await supabase
          .from('gig_responses')
          .update({'response': response, 'updated_at': now})
          .eq('gig_id', gigId)
          .eq('user_id', userId);
      debugPrint('[GigResponseRepository] Update successful');
    } else {
      // Insert new response
      // Note: gig_responses table doesn't have band_id column -
      // band authorization is done via RLS joining to gigs table
      debugPrint('[GigResponseRepository] Inserting new response');
      await supabase.from('gig_responses').insert({
        'gig_id': gigId,
        'user_id': userId,
        'response': response,
      });
      debugPrint('[GigResponseRepository] Insert successful');
    }
  }

  /// Check if an error is non-retryable (permissions, RLS violation, etc.)
  bool _isNonRetryableError(dynamic error) {
    final message = error.toString().toLowerCase();
    return message.contains('permission denied') ||
        message.contains('rls') ||
        message.contains('policy') ||
        message.contains('row-level security') ||
        message.contains('violates') ||
        message.contains('not authorized');
  }

  /// Fetch response summary for a specific gig.
  /// Returns counts of yes, no, and not-responded members.
  Future<GigResponseSummary> fetchGigResponseSummary({
    required String gigId,
    required String bandId,
  }) async {
    // Get all active band members
    final membersResponse = await supabase
        .from('band_members')
        .select('user_id')
        .eq('band_id', bandId)
        .eq('status', 'active');

    final totalMembers = membersResponse.length;

    if (totalMembers == 0) {
      return const GigResponseSummary.empty();
    }

    // Get all responses for this gig
    final responsesResponse = await supabase
        .from('gig_responses')
        .select('user_id, response')
        .eq('gig_id', gigId);

    int yesCount = 0;
    int noCount = 0;

    for (final r in responsesResponse) {
      final response = r['response'] as String?;
      if (response == 'yes') {
        yesCount++;
      } else if (response == 'no') {
        noCount++;
      }
    }

    final notRespondedCount = totalMembers - yesCount - noCount;

    return GigResponseSummary(
      yesCount: yesCount,
      noCount: noCount,
      notRespondedCount: notRespondedCount < 0 ? 0 : notRespondedCount,
      totalMembers: totalMembers,
    );
  }

  /// Fetch all member responses for a specific gig.
  /// Returns a map of userId -> response ('yes', 'no', or null for not responded).
  Future<Map<String, String?>> fetchAllMemberResponses({
    required String gigId,
    required String bandId,
  }) async {
    debugPrint(
      '[GigResponseRepository] fetchAllMemberResponses: gigId=$gigId, bandId=$bandId',
    );

    // Get all active band members
    final membersResponse = await supabase
        .from('band_members')
        .select('user_id')
        .eq('band_id', bandId)
        .eq('status', 'active');

    // Initialize all members as not responded
    final responses = <String, String?>{};
    for (final m in membersResponse) {
      responses[m['user_id'] as String] = null;
    }

    // Get all responses for this gig (primary date only - no gig_date_id)
    final responsesResponse = await supabase
        .from('gig_responses')
        .select('user_id, response')
        .eq('gig_id', gigId)
        .isFilter('gig_date_id', null);

    // Populate responses
    for (final r in responsesResponse) {
      final userId = r['user_id'] as String;
      final response = r['response'] as String?;
      if (responses.containsKey(userId)) {
        responses[userId] = response;
      }
    }

    debugPrint(
      '[GigResponseRepository] Loaded ${responses.length} member responses',
    );
    return responses;
  }

  /// Fetch all member responses for a specific gig date (additional date).
  /// Returns a map of userId -> response ('yes', 'no', or null for not responded).
  Future<Map<String, String?>> fetchAllMemberResponsesForDate({
    required String gigId,
    required String gigDateId,
    required String bandId,
  }) async {
    debugPrint(
      '[GigResponseRepository] fetchAllMemberResponsesForDate: gigId=$gigId, gigDateId=$gigDateId',
    );

    // Get all active band members
    final membersResponse = await supabase
        .from('band_members')
        .select('user_id')
        .eq('band_id', bandId)
        .eq('status', 'active');

    // Initialize all members as not responded
    final responses = <String, String?>{};
    for (final m in membersResponse) {
      responses[m['user_id'] as String] = null;
    }

    // Get all responses for this specific date
    final responsesResponse = await supabase
        .from('gig_responses')
        .select('user_id, response')
        .eq('gig_id', gigId)
        .eq('gig_date_id', gigDateId);

    // Populate responses
    for (final r in responsesResponse) {
      final userId = r['user_id'] as String;
      final response = r['response'] as String?;
      if (responses.containsKey(userId)) {
        responses[userId] = response;
      }
    }

    debugPrint(
      '[GigResponseRepository] Loaded ${responses.length} member responses for date',
    );
    return responses;
  }

  /// Fetch all member responses for all dates of a multi-date gig.
  /// Returns a map of dateKey -> (userId -> response).
  /// dateKey is 'primary' for the main date, or the gigDateId for additional dates.
  Future<Map<String, Map<String, String?>>> fetchAllDateResponses({
    required String gigId,
    required String bandId,
    required List<String> gigDateIds,
  }) async {
    debugPrint(
      '[GigResponseRepository] fetchAllDateResponses: gigId=$gigId, dates=${gigDateIds.length}',
    );

    // Get all active band members
    final membersResponse = await supabase
        .from('band_members')
        .select('user_id')
        .eq('band_id', bandId)
        .eq('status', 'active');

    final memberIds = membersResponse
        .map((m) => m['user_id'] as String)
        .toList();

    // Initialize result map
    final result = <String, Map<String, String?>>{};

    // Initialize primary date with all members as not responded
    result['primary'] = {for (var id in memberIds) id: null};

    // Initialize each additional date
    for (final dateId in gigDateIds) {
      result[dateId] = {for (var id in memberIds) id: null};
    }

    // Get ALL responses for this gig (all dates)
    final responsesResponse = await supabase
        .from('gig_responses')
        .select('user_id, response, gig_date_id')
        .eq('gig_id', gigId);

    // Populate responses
    for (final r in responsesResponse) {
      final userId = r['user_id'] as String;
      final response = r['response'] as String?;
      final gigDateId = r['gig_date_id'] as String?;

      final dateKey = gigDateId ?? 'primary';
      if (result.containsKey(dateKey) && memberIds.contains(userId)) {
        result[dateKey]![userId] = response;
      }
    }

    debugPrint(
      '[GigResponseRepository] Loaded responses for ${result.length} dates',
    );
    return result;
  }

  /// Submit or update the user's response for a specific date of a gig.
  /// Has automatic retry logic for transient failures.
  Future<void> upsertResponseForDate({
    required String gigId,
    required String? gigDateId, // null for primary date
    required String userId,
    required String response, // 'yes' or 'no'
  }) async {
    debugPrint(
      '[GigResponseRepository] upsertResponseForDate: gigId=$gigId, gigDateId=$gigDateId, response=$response',
    );

    // Retry up to 3 times with exponential backoff for transient errors
    const maxRetries = 3;
    Exception? lastError;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _performUpsertForDate(
          gigId: gigId,
          gigDateId: gigDateId,
          userId: userId,
          response: response,
        );
        debugPrint(
          '[GigResponseRepository] upsertResponseForDate succeeded on attempt $attempt',
        );
        return; // Success!
      } catch (e, stackTrace) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint(
          '[GigResponseRepository] upsertResponseForDate attempt $attempt failed: $e',
        );
        debugPrint('[GigResponseRepository] Stack trace: $stackTrace');

        // Don't retry on non-transient errors
        if (_isNonRetryableError(e)) {
          debugPrint('[GigResponseRepository] Non-retryable error, stopping');
          break;
        }

        // Wait before retry
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 100 * (1 << (attempt - 1)));
          await Future.delayed(delay);
        }
      }
    }

    throw GigResponseError.fromException(lastError!);
  }

  /// Internal method to perform the actual upsert for date
  Future<void> _performUpsertForDate({
    required String gigId,
    required String? gigDateId,
    required String userId,
    required String response,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    // Build the query for finding existing response
    var query = supabase
        .from('gig_responses')
        .select('id')
        .eq('gig_id', gigId)
        .eq('user_id', userId);

    if (gigDateId != null) {
      query = query.eq('gig_date_id', gigDateId);
    } else {
      query = query.isFilter('gig_date_id', null);
    }

    final existing = await query.maybeSingle();

    if (existing != null) {
      // Update existing response
      var updateQuery = supabase
          .from('gig_responses')
          .update({'response': response, 'updated_at': now})
          .eq('gig_id', gigId)
          .eq('user_id', userId);

      if (gigDateId != null) {
        updateQuery = updateQuery.eq('gig_date_id', gigDateId);
      } else {
        updateQuery = updateQuery.isFilter('gig_date_id', null);
      }

      await updateQuery;
      debugPrint('[GigResponseRepository] Updated response for date');
    } else {
      // Insert new response
      await supabase.from('gig_responses').insert({
        'gig_id': gigId,
        'gig_date_id': gigDateId,
        'user_id': userId,
        'response': response,
      });
      debugPrint('[GigResponseRepository] Inserted response for date');
    }
  }

  /// Fetch response summaries for multiple gigs at once (for dashboard optimization).
  Future<Map<String, GigResponseSummary>> fetchMultipleGigResponseSummaries({
    required List<String> gigIds,
    required String bandId,
  }) async {
    if (gigIds.isEmpty) {
      return {};
    }

    // Get all active band members
    final membersResponse = await supabase
        .from('band_members')
        .select('user_id')
        .eq('band_id', bandId)
        .eq('status', 'active');

    final totalMembers = membersResponse.length;

    if (totalMembers == 0) {
      return {for (var id in gigIds) id: const GigResponseSummary.empty()};
    }

    // Get all responses for these gigs
    final responsesResponse = await supabase
        .from('gig_responses')
        .select('gig_id, user_id, response')
        .inFilter('gig_id', gigIds);

    // Group responses by gig_id
    final responsesByGig = <String, List<Map<String, dynamic>>>{};
    for (final r in responsesResponse) {
      final gigId = r['gig_id'] as String;
      responsesByGig.putIfAbsent(gigId, () => []).add(r);
    }

    // Calculate summary for each gig
    final summaries = <String, GigResponseSummary>{};
    for (final gigId in gigIds) {
      final responses = responsesByGig[gigId] ?? [];
      int yesCount = 0;
      int noCount = 0;

      for (final r in responses) {
        final response = r['response'] as String?;
        if (response == 'yes') {
          yesCount++;
        } else if (response == 'no') {
          noCount++;
        }
      }

      final notRespondedCount = totalMembers - yesCount - noCount;

      summaries[gigId] = GigResponseSummary(
        yesCount: yesCount,
        noCount: noCount,
        notRespondedCount: notRespondedCount < 0 ? 0 : notRespondedCount,
        totalMembers: totalMembers,
      );
    }

    return summaries;
  }
}

/// Provider for the repository
final gigResponseRepositoryProvider = Provider(
  (ref) => GigResponseRepository(),
);

// ============================================================================
// POTENTIAL GIG RESPONSE SUMMARIES PROVIDER
// Provides reactive availability summaries for all potential gigs.
//
// DATA FLOW:
// 1. Watches gigProvider.potentialGigs for the list of gigs to summarize
// 2. Watches activeBandIdProvider for band context
// 3. Fetches summaries from database when either changes
// 4. Invalidated by EventEditorDrawer after availability updates
//
// This ensures the dashboard card always shows fresh availability counts,
// synchronized with user selections in the Edit Gig drawer.
// ============================================================================

/// Async provider that fetches response summaries for all potential gigs.
/// Automatically refreshes when gig list or band changes.
final potentialGigResponseSummariesProvider =
    FutureProvider<Map<String, GigResponseSummary>>((ref) async {
      // Import dependencies
      final gigState = ref.watch(gigProvider);
      final bandId = ref.watch(activeBandIdProvider);

      // Return empty map if no band or no potential gigs
      if (bandId == null || gigState.potentialGigs.isEmpty) {
        return {};
      }

      // Avoid fetching while gigs are still loading to prevent stale data
      if (gigState.isLoading) {
        return {};
      }

      final repository = ref.read(gigResponseRepositoryProvider);
      final gigIds = gigState.potentialGigs.map((g) => g.id).toList();

      debugPrint(
        '[potentialGigResponseSummariesProvider] Fetching summaries for ${gigIds.length} potential gigs',
      );

      try {
        final summaries = await repository.fetchMultipleGigResponseSummaries(
          gigIds: gigIds,
          bandId: bandId,
        );
        debugPrint(
          '[potentialGigResponseSummariesProvider] Loaded ${summaries.length} summaries',
        );
        return summaries;
      } catch (e) {
        debugPrint('[potentialGigResponseSummariesProvider] Error: $e');
        rethrow;
      }
    });
