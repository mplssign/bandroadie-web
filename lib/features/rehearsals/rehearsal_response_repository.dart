import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import '../bands/active_band_controller.dart';
import 'rehearsal_controller.dart';

// ============================================================================
// REHEARSAL RESPONSE REPOSITORY
// Handles all rehearsal response (RSVP) data operations.
//
// BAND ISOLATION: All queries require bandId and enforce band-scoped access.
// ============================================================================

/// Error class for rehearsal response operations with user-friendly messages
class RehearsalResponseError implements Exception {
  final String message;
  final String userMessage;
  final bool isRetryable;

  const RehearsalResponseError({
    required this.message,
    required this.userMessage,
    this.isRetryable = false,
  });

  factory RehearsalResponseError.fromException(Exception e) {
    final message = e.toString().toLowerCase();

    // Check for specific error types
    if (message.contains('permission denied') ||
        message.contains('rls') ||
        message.contains('policy') ||
        message.contains('not authorized')) {
      return RehearsalResponseError(
        message: e.toString(),
        userMessage:
            'You don\'t have permission to update this response. Try refreshing the app.',
        isRetryable: false,
      );
    }

    if (message.contains('network') ||
        message.contains('timeout') ||
        message.contains('connection')) {
      return RehearsalResponseError(
        message: e.toString(),
        userMessage: 'Network issue — check your connection and try again.',
        isRetryable: true,
      );
    }

    // Generic error
    return RehearsalResponseError(
      message: e.toString(),
      userMessage: 'Something went wrong — try again in a moment.',
      isRetryable: true,
    );
  }

  @override
  String toString() => 'RehearsalResponseError: $message';
}

/// Summary of responses for a potential rehearsal
class RehearsalResponseSummary {
  final int yesCount;
  final int noCount;
  final int notRespondedCount;
  final int totalMembers;

  const RehearsalResponseSummary({
    required this.yesCount,
    required this.noCount,
    required this.notRespondedCount,
    required this.totalMembers,
  });

  /// Create empty summary
  const RehearsalResponseSummary.empty()
      : yesCount = 0,
        noCount = 0,
        notRespondedCount = 0,
        totalMembers = 0;

  @override
  String toString() =>
      'RehearsalResponseSummary(yes: $yesCount, no: $noCount, notResponded: $notRespondedCount)';
}

/// A potential rehearsal that needs the user's response
class PendingPotentialRehearsal {
  final String rehearsalId;
  final String bandId;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String? eventTimezone;
  final String location;

  const PendingPotentialRehearsal({
    required this.rehearsalId,
    required this.bandId,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.eventTimezone,
    required this.location,
  });

  factory PendingPotentialRehearsal.fromJson(Map<String, dynamic> json) {
    return PendingPotentialRehearsal(
      rehearsalId: json['id'] as String,
      bandId: json['band_id'] as String,
      date: DateTime.parse(json['date'] as String),
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      eventTimezone: json['event_timezone'] as String?,
      location: json['location'] as String? ?? '',
    );
  }
}

class RehearsalResponseRepository {
  /// Fetch all potential rehearsals for a band where the current user has NOT responded yet.
  /// Ordered by date + start_time (earliest first).
  Future<List<PendingPotentialRehearsal>> fetchPendingPotentialRehearsals({
    required String bandId,
    required String userId,
  }) async {
    debugPrint(
      '[RehearsalResponseRepository] fetchPendingPotentialRehearsals: bandId=$bandId, userId=$userId',
    );

    // Get today's date for filtering (only future/today rehearsals)
    final today = DateTime.now().toIso8601String().split('T')[0];
    debugPrint('[RehearsalResponseRepository] Filtering rehearsals >= $today');

    // Fetch all potential rehearsals for the band
    // Exclude child instances of recurring rehearsals (parent_rehearsal_id IS NULL)
    // so user only gets one prompt per recurring series
    final rehearsalsResponse = await supabase
        .from('rehearsals')
        .select(
            'id, band_id, date, start_time, end_time, event_timezone, location')
        .eq('band_id', bandId)
        .eq('is_potential', true)
        .gte('date', today)
        .isFilter('parent_rehearsal_id', null)
        .order('date', ascending: true)
        .order('start_time', ascending: true);

    debugPrint(
      '[RehearsalResponseRepository] Found ${rehearsalsResponse.length} potential rehearsals',
    );
    for (final rehearsal in rehearsalsResponse) {
      debugPrint(
        '[RehearsalResponseRepository]   - rehearsal on ${rehearsal['date']}',
      );
    }

    if (rehearsalsResponse.isEmpty) {
      debugPrint(
        '[RehearsalResponseRepository] No potential rehearsals found, returning empty',
      );
      return [];
    }

    // Get all rehearsal IDs
    final rehearsalIds =
        rehearsalsResponse.map((r) => r['id'] as String).toList();

    // Fetch user's responses for these rehearsals
    final responsesResponse = await supabase
        .from('rehearsal_responses')
        .select('rehearsal_id, response')
        .eq('user_id', userId)
        .inFilter('rehearsal_id', rehearsalIds);

    debugPrint(
      '[RehearsalResponseRepository] User has ${responsesResponse.length} responses',
    );
    for (final r in responsesResponse) {
      debugPrint(
        '[RehearsalResponseRepository]   - rehearsal ${r['rehearsal_id']}: ${r['response']}',
      );
    }

    // Build set of rehearsals user has responded to
    // If a response row exists, the user has responded (DB constraint ensures valid 'yes'/'no' values)
    final respondedRehearsalIds = <String>{
      for (final r in responsesResponse) r['rehearsal_id'] as String,
    };

    // Filter out rehearsals user has already responded to
    final pendingRehearsals = <PendingPotentialRehearsal>[];
    for (final rehearsal in rehearsalsResponse) {
      final rehearsalId = rehearsal['id'] as String;
      if (!respondedRehearsalIds.contains(rehearsalId)) {
        pendingRehearsals.add(PendingPotentialRehearsal.fromJson(rehearsal));
      }
    }

    debugPrint(
      '[RehearsalResponseRepository] Returning ${pendingRehearsals.length} pending rehearsals',
    );

    return pendingRehearsals;
  }

  /// Get the current user's response for a specific rehearsal.
  /// Returns 'yes', 'no', or null if not responded.
  Future<String?> fetchUserResponse({
    required String rehearsalId,
    required String userId,
  }) async {
    final response = await supabase
        .from('rehearsal_responses')
        .select('response')
        .eq('rehearsal_id', rehearsalId)
        .eq('user_id', userId)
        .isFilter('rehearsal_date_id', null)
        .maybeSingle();

    if (response == null) return null;
    return response['response'] as String?;
  }

  /// Submit or update the user's response for a rehearsal.
  /// Uses upsert on (rehearsal_id, user_id) constraint.
  /// Upserts a rehearsal response with automatic retry on transient failures.
  /// Throws [RehearsalResponseError] with user-friendly message on failure.
  Future<void> upsertResponse({
    required String rehearsalId,
    required String bandId,
    required String userId,
    required String response, // 'yes' or 'no'
  }) async {
    debugPrint(
      '[RehearsalResponseRepository] upsertResponse: rehearsalId=$rehearsalId, bandId=$bandId, userId=$userId, response=$response',
    );

    // Retry up to 3 times with exponential backoff for transient errors
    const maxRetries = 3;
    Exception? lastError;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _performUpsert(
          rehearsalId: rehearsalId,
          userId: userId,
          response: response,
        );
        debugPrint(
          '[RehearsalResponseRepository] upsertResponse succeeded on attempt $attempt',
        );
        return; // Success!
      } catch (e, stackTrace) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('[RehearsalResponseRepository] Attempt $attempt failed: $e');
        debugPrint('[RehearsalResponseRepository] Stack trace: $stackTrace');

        // Don't retry on non-transient errors (permission denied, etc.)
        if (_isNonRetryableError(e)) {
          debugPrint(
            '[RehearsalResponseRepository] Non-retryable error, stopping',
          );
          break;
        }

        // Wait before retry (100ms, 200ms, 400ms)
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 100 * (1 << (attempt - 1)));
          debugPrint(
            '[RehearsalResponseRepository] Retrying in ${delay.inMilliseconds}ms...',
          );
          await Future.delayed(delay);
        }
      }
    }

    // All retries failed
    throw RehearsalResponseError.fromException(lastError!);
  }

  /// Internal method to perform the actual upsert
  Future<void> _performUpsert({
    required String rehearsalId,
    required String userId,
    required String response,
  }) async {
    // Check if a response already exists
    final existing = await supabase
        .from('rehearsal_responses')
        .select('id')
        .eq('rehearsal_id', rehearsalId)
        .eq('user_id', userId)
        .isFilter('rehearsal_date_id', null)
        .maybeSingle();

    final now = DateTime.now().toUtc().toIso8601String();

    if (existing != null) {
      // Update existing response
      debugPrint('[RehearsalResponseRepository] Updating existing response');
      await supabase
          .from('rehearsal_responses')
          .update({'response': response, 'updated_at': now})
          .eq('rehearsal_id', rehearsalId)
          .eq('user_id', userId)
          .isFilter('rehearsal_date_id', null);
      debugPrint('[RehearsalResponseRepository] Update successful');
    } else {
      // Insert new response
      // Note: rehearsal_responses table doesn't have band_id column -
      // band authorization is done via RLS joining to rehearsals table
      debugPrint('[RehearsalResponseRepository] Inserting new response');
      await supabase.from('rehearsal_responses').insert({
        'rehearsal_id': rehearsalId,
        'rehearsal_date_id': null,
        'user_id': userId,
        'response': response,
      });
      debugPrint('[RehearsalResponseRepository] Insert successful');
    }
  }

  /// Delete the user's response for a rehearsal (unselect).
  /// Throws [RehearsalResponseError] with user-friendly message on failure.
  Future<void> deleteResponse({
    required String rehearsalId,
    required String userId,
  }) async {
    debugPrint(
      '[RehearsalResponseRepository] deleteResponse: rehearsalId=$rehearsalId, userId=$userId',
    );

    try {
      await supabase
          .from('rehearsal_responses')
          .delete()
          .eq('rehearsal_id', rehearsalId)
          .eq('user_id', userId);
      debugPrint('[RehearsalResponseRepository] Delete successful');
    } catch (e, stackTrace) {
      debugPrint('[RehearsalResponseRepository] Delete failed: $e');
      debugPrint('[RehearsalResponseRepository] Stack trace: $stackTrace');
      throw RehearsalResponseError.fromException(
        e is Exception ? e : Exception(e.toString()),
      );
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

  /// Fetch response summary for a specific rehearsal.
  /// Returns counts of yes, no, and not-responded members.
  Future<RehearsalResponseSummary> fetchRehearsalResponseSummary({
    required String rehearsalId,
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
      return const RehearsalResponseSummary.empty();
    }

    // Get all responses for this rehearsal
    final responsesResponse = await supabase
        .from('rehearsal_responses')
        .select('user_id, response')
        .eq('rehearsal_id', rehearsalId);

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

    return RehearsalResponseSummary(
      yesCount: yesCount,
      noCount: noCount,
      notRespondedCount: notRespondedCount < 0 ? 0 : notRespondedCount,
      totalMembers: totalMembers,
    );
  }

  /// Fetch all member responses for a specific rehearsal.
  /// Returns a map of userId -> response ('yes', 'no', or null for not responded).
  Future<Map<String, String?>> fetchAllMemberResponses({
    required String rehearsalId,
    required String bandId,
  }) async {
    debugPrint(
      '[RehearsalResponseRepository] fetchAllMemberResponses: rehearsalId=$rehearsalId, bandId=$bandId',
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

    // Get all responses for this rehearsal
    final responsesResponse = await supabase
        .from('rehearsal_responses')
        .select('user_id, response')
        .eq('rehearsal_id', rehearsalId)
        .isFilter('rehearsal_date_id', null);

    // Populate responses
    for (final r in responsesResponse) {
      final userId = r['user_id'] as String;
      final response = r['response'] as String?;
      if (responses.containsKey(userId)) {
        responses[userId] = response;
      }
    }

    debugPrint(
      '[RehearsalResponseRepository] Loaded ${responses.length} member responses',
    );
    return responses;
  }

  /// Fetch response summaries for multiple rehearsals at once (for dashboard optimization).
  Future<Map<String, RehearsalResponseSummary>>
      fetchMultipleRehearsalResponseSummaries({
    required List<String> rehearsalIds,
    required String bandId,
  }) async {
    if (rehearsalIds.isEmpty) {
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
      return {
        for (var id in rehearsalIds) id: const RehearsalResponseSummary.empty()
      };
    }

    // Get all responses for these rehearsals
    final responsesResponse = await supabase
        .from('rehearsal_responses')
        .select('rehearsal_id, user_id, response')
        .inFilter('rehearsal_id', rehearsalIds);

    // Group responses by rehearsal_id
    final responsesByRehearsal = <String, List<Map<String, dynamic>>>{};
    for (final r in responsesResponse) {
      final rehearsalId = r['rehearsal_id'] as String;
      responsesByRehearsal.putIfAbsent(rehearsalId, () => []).add(r);
    }

    // Calculate summary for each rehearsal
    final summaries = <String, RehearsalResponseSummary>{};
    for (final rehearsalId in rehearsalIds) {
      final responses = responsesByRehearsal[rehearsalId] ?? [];
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

      summaries[rehearsalId] = RehearsalResponseSummary(
        yesCount: yesCount,
        noCount: noCount,
        notRespondedCount: notRespondedCount < 0 ? 0 : notRespondedCount,
        totalMembers: totalMembers,
      );
    }

    return summaries;
  }

  /// Fetch the current user's own responses for multiple potential rehearsals.
  /// Returns rehearsalId → 'yes'/'no'/null (null = not responded).
  Future<Map<String, String?>> fetchCurrentUserRehearsalResponses({
    required List<String> rehearsalIds,
    required String userId,
  }) async {
    if (rehearsalIds.isEmpty) return {};

    final responses = await supabase
        .from('rehearsal_responses')
        .select('rehearsal_id, response')
        .eq('user_id', userId)
        .inFilter('rehearsal_id', rehearsalIds);

    final result = <String, String?>{for (final id in rehearsalIds) id: null};
    for (final r in responses) {
      result[r['rehearsal_id'] as String] = r['response'] as String?;
    }
    return result;
  }

  /// Submit or update the user's response for a specific date of a rehearsal.
  /// Has automatic retry logic for transient failures.
  Future<void> upsertResponseForDate({
    required String rehearsalId,
    required String? rehearsalDateId, // null for primary date
    required String userId,
    required String response, // 'yes' or 'no'
  }) async {
    debugPrint(
      '[RehearsalResponseRepository] upsertResponseForDate: rehearsalId=$rehearsalId, rehearsalDateId=$rehearsalDateId, response=$response',
    );

    // Retry up to 3 times with exponential backoff for transient errors
    const maxRetries = 3;
    Exception? lastError;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _performUpsertForDate(
          rehearsalId: rehearsalId,
          rehearsalDateId: rehearsalDateId,
          userId: userId,
          response: response,
        );
        debugPrint(
          '[RehearsalResponseRepository] upsertResponseForDate succeeded on attempt $attempt',
        );
        return; // Success!
      } catch (e, stackTrace) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint(
          '[RehearsalResponseRepository] upsertResponseForDate attempt $attempt failed: $e',
        );
        debugPrint('[RehearsalResponseRepository] Stack trace: $stackTrace');

        // Don't retry on non-transient errors
        if (_isNonRetryableError(e)) {
          debugPrint(
              '[RehearsalResponseRepository] Non-retryable error, stopping');
          break;
        }

        // Wait before retry
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 100 * (1 << (attempt - 1)));
          await Future.delayed(delay);
        }
      }
    }

    throw RehearsalResponseError.fromException(lastError!);
  }

  /// Internal method to perform the actual upsert for date
  Future<void> _performUpsertForDate({
    required String rehearsalId,
    required String? rehearsalDateId,
    required String userId,
    required String response,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    // Build the query for finding existing response
    var query = supabase
        .from('rehearsal_responses')
        .select('id')
        .eq('rehearsal_id', rehearsalId)
        .eq('user_id', userId);

    if (rehearsalDateId != null) {
      query = query.eq('rehearsal_date_id', rehearsalDateId);
    } else {
      query = query.isFilter('rehearsal_date_id', null);
    }

    final existing = await query.maybeSingle();

    if (existing != null) {
      // Update existing response
      var updateQuery = supabase
          .from('rehearsal_responses')
          .update({'response': response, 'updated_at': now})
          .eq('rehearsal_id', rehearsalId)
          .eq('user_id', userId);

      if (rehearsalDateId != null) {
        updateQuery = updateQuery.eq('rehearsal_date_id', rehearsalDateId);
      } else {
        updateQuery = updateQuery.isFilter('rehearsal_date_id', null);
      }

      await updateQuery;
      debugPrint('[RehearsalResponseRepository] Updated response for date');
    } else {
      // Insert new response
      await supabase.from('rehearsal_responses').insert({
        'rehearsal_id': rehearsalId,
        'rehearsal_date_id': rehearsalDateId,
        'user_id': userId,
        'response': response,
      });
      debugPrint('[RehearsalResponseRepository] Inserted response for date');
    }
  }

  /// Delete the user's response for a specific date of a rehearsal.
  /// Pass rehearsalDateId = null to delete the primary-date response.
  Future<void> deleteResponseForDate({
    required String rehearsalId,
    required String userId,
    required String? rehearsalDateId,
  }) async {
    debugPrint(
      '[RehearsalResponseRepository] deleteResponseForDate: rehearsalId=$rehearsalId, rehearsalDateId=$rehearsalDateId, userId=$userId',
    );

    try {
      if (rehearsalDateId != null) {
        await supabase
            .from('rehearsal_responses')
            .delete()
            .eq('rehearsal_id', rehearsalId)
            .eq('user_id', userId)
            .eq('rehearsal_date_id', rehearsalDateId);
      } else {
        await supabase
            .from('rehearsal_responses')
            .delete()
            .eq('rehearsal_id', rehearsalId)
            .eq('user_id', userId)
            .isFilter('rehearsal_date_id', null);
      }
      debugPrint('[RehearsalResponseRepository] Delete successful for date');
    } catch (e, stackTrace) {
      debugPrint('[RehearsalResponseRepository] Delete failed: $e');
      debugPrint('[RehearsalResponseRepository] Stack trace: $stackTrace');
      throw RehearsalResponseError.fromException(
        e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Fetch the current user's responses across ALL dates of all potential rehearsals.
  /// Returns rehearsalId → (rehearsalDateId? → response).
  /// rehearsalDateId? is null for the primary date, a string ID for additional dates.
  Future<Map<String, Map<String?, String?>>>
      fetchCurrentUserRehearsalAllDateResponses({
    required List<String> rehearsalIds,
    required String userId,
  }) async {
    if (rehearsalIds.isEmpty) return {};

    final responses = await supabase
        .from('rehearsal_responses')
        .select('rehearsal_id, rehearsal_date_id, response')
        .eq('user_id', userId)
        .inFilter('rehearsal_id', rehearsalIds);

    // Seed result with empty maps for each rehearsal
    final result = <String, Map<String?, String?>>{
      for (final id in rehearsalIds) id: {},
    };
    for (final r in responses) {
      final rehearsalId = r['rehearsal_id'] as String;
      final rehearsalDateId =
          r['rehearsal_date_id'] as String?; // null = primary date
      final response = r['response'] as String?;
      result[rehearsalId]![rehearsalDateId] = response;
    }
    return result;
  }

  /// Fetch member availability for ALL dates of a multi-date potential rehearsal.
  /// Returns map keyed by 'primary' (primary date) or rehearsalDateId (additional dates).
  /// Each value is a map of userId → response ('yes', 'no', or null = not responded).
  Future<Map<String, Map<String, String?>>> fetchAllDateResponses({
    required String rehearsalId,
    required String bandId,
    required List<String> rehearsalDateIds,
  }) async {
    debugPrint(
      '[RehearsalResponseRepository] fetchAllDateResponses: rehearsalId=$rehearsalId, dates=${rehearsalDateIds.length}',
    );

    final membersResponse = await supabase
        .from('band_members')
        .select('user_id')
        .eq('band_id', bandId)
        .eq('status', 'active');

    final memberIds =
        (membersResponse as List).map((m) => m['user_id'] as String).toList();

    final result = <String, Map<String, String?>>{};
    result['primary'] = {for (var id in memberIds) id: null};
    for (final dateId in rehearsalDateIds) {
      result[dateId] = {for (var id in memberIds) id: null};
    }

    final responsesResponse = await supabase
        .from('rehearsal_responses')
        .select('user_id, response, rehearsal_date_id')
        .eq('rehearsal_id', rehearsalId);

    for (final r in responsesResponse as List) {
      final userId = r['user_id'] as String;
      final response = r['response'] as String?;
      final rehearsalDateId = r['rehearsal_date_id'] as String?;
      final dateKey = rehearsalDateId ?? 'primary';
      if (result.containsKey(dateKey) && memberIds.contains(userId)) {
        result[dateKey]![userId] = response;
      }
    }

    debugPrint(
      '[RehearsalResponseRepository] Loaded responses for ${result.length} dates',
    );
    return result;
  }
}

/// Provider for the repository
final rehearsalResponseRepositoryProvider = Provider(
  (ref) => RehearsalResponseRepository(),
);

// ============================================================================
// POTENTIAL REHEARSAL RESPONSE SUMMARIES PROVIDER
// Provides reactive availability summaries for all potential rehearsals.
//
// DATA FLOW:
// 1. Watches rehearsalProvider.potentialRehearsals for the list to summarize
// 2. Watches activeBandIdProvider for band context
// 3. Fetches summaries from database when either changes
// 4. Invalidated after availability updates
//
// This ensures the dashboard card always shows fresh availability counts.
// ============================================================================

/// Async provider that fetches response summaries for all potential rehearsals.
/// Automatically refreshes when rehearsal list or band changes.
final potentialRehearsalResponseSummariesProvider =
    FutureProvider<Map<String, RehearsalResponseSummary>>((ref) async {
  // Import dependencies
  final rehearsalState = ref.watch(rehearsalProvider);
  final bandId = ref.watch(activeBandIdProvider);

  // Return empty map if no band or no potential rehearsals
  if (bandId == null || rehearsalState.potentialRehearsals.isEmpty) {
    return {};
  }

  // Avoid fetching while rehearsals are still loading to prevent stale data
  if (rehearsalState.isLoading) {
    return {};
  }

  final repository = ref.read(rehearsalResponseRepositoryProvider);
  final rehearsalIds =
      rehearsalState.potentialRehearsals.map((r) => r.id).toList();

  debugPrint(
    '[potentialRehearsalResponseSummariesProvider] Fetching summaries for ${rehearsalIds.length} potential rehearsals',
  );

  try {
    final summaries = await repository.fetchMultipleRehearsalResponseSummaries(
      rehearsalIds: rehearsalIds,
      bandId: bandId,
    );
    debugPrint(
      '[potentialRehearsalResponseSummariesProvider] Loaded ${summaries.length} summaries',
    );
    return summaries;
  } catch (e) {
    debugPrint('[potentialRehearsalResponseSummariesProvider] Error: $e');
    rethrow;
  }
});

/// Async provider for the current user's own responses across all potential rehearsals.
/// Returns rehearsalId → 'yes'/'no'/null. Invalidated after the user submits a response.
final currentUserRehearsalResponsesProvider =
    FutureProvider<Map<String, String?>>((ref) async {
  final rehearsalState = ref.watch(rehearsalProvider);
  final userId = supabase.auth.currentUser?.id;

  if (userId == null || rehearsalState.potentialRehearsals.isEmpty) {
    return {};
  }
  if (rehearsalState.isLoading) return {};

  final repository = ref.read(rehearsalResponseRepositoryProvider);
  final rehearsalIds =
      rehearsalState.potentialRehearsals.map((r) => r.id).toList();

  try {
    return await repository.fetchCurrentUserRehearsalResponses(
      rehearsalIds: rehearsalIds,
      userId: userId,
    );
  } catch (e) {
    debugPrint('[currentUserRehearsalResponsesProvider] Error: $e');
    return {};
  }
});

/// Async provider for the current user's responses across ALL dates of all potential rehearsals.
/// Returns rehearsalId → (rehearsalDateId? → response). rehearsalDateId? null = primary date.
/// Invalidated after the user submits a response for any date.
final currentUserRehearsalAllDateResponsesProvider =
    FutureProvider<Map<String, Map<String?, String?>>>((ref) async {
  final rehearsalState = ref.watch(rehearsalProvider);
  final bandId = ref.watch(activeBandIdProvider);
  final userId = supabase.auth.currentUser?.id;

  if (bandId == null ||
      userId == null ||
      rehearsalState.potentialRehearsals.isEmpty) {
    return {};
  }
  if (rehearsalState.isLoading) return {};

  final repository = ref.read(rehearsalResponseRepositoryProvider);
  final rehearsalIds =
      rehearsalState.potentialRehearsals.map((r) => r.id).toList();

  try {
    return await repository.fetchCurrentUserRehearsalAllDateResponses(
      rehearsalIds: rehearsalIds,
      userId: userId,
    );
  } catch (e) {
    debugPrint('[currentUserRehearsalAllDateResponsesProvider] Error: $e');
    return {};
  }
});
