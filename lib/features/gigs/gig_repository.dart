import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/services/supabase_client.dart';

// ============================================================================
// GIG REPOSITORY
// Handles all gig-related data fetching.
//
// ISOLATION RULES (NON-NEGOTIABLE):
// - Every query REQUIRES a non-null bandId
// - If bandId is null, we throw an error or return empty — NEVER query all gigs
// - Supabase RLS should also enforce this, but we add client-side checks
//
// Multi-date support:
// - Gigs are joined with gig_dates to include additional dates
// - The primary date is in gigs.date, additional dates in gig_dates
// ============================================================================

/// Exception thrown when attempting to fetch gigs without a band context.
class NoBandSelectedError extends Error {
  final String message;
  NoBandSelectedError([
    this.message =
        'No band selected. Cannot fetch gigs without a band context.',
  ]);

  @override
  String toString() => 'NoBandSelectedError: $message';
}

/// The select clause for fetching gigs with their additional dates
const _gigSelectClause = '''
  *,
  gig_dates (
    id,
    gig_id,
    date,
    created_at,
    updated_at
  )
''';

class GigRepository {
  /// Fetches all gigs for the specified band.
  ///
  /// IMPORTANT: bandId is REQUIRED. If null, throws NoBandSelectedError.
  /// This prevents accidental cross-band data leakage.
  Future<List<Gig>> fetchGigsForBand(String? bandId) async {
    // =========================================
    // BAND ISOLATION CHECK — NON-NEGOTIABLE
    // =========================================
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    final response = await supabase
        .from('gigs')
        .select(_gigSelectClause)
        .eq('band_id', bandId)
        .order('date', ascending: true);

    return response.map<Gig>((json) => Gig.fromJson(json)).toList();
  }

  /// Fetches only potential (unconfirmed) gigs for the specified band.
  Future<List<Gig>> fetchPotentialGigs(String? bandId) async {
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    final response = await supabase
        .from('gigs')
        .select(_gigSelectClause)
        .eq('band_id', bandId)
        .eq('is_potential', true)
        .order('date', ascending: true);

    return response.map<Gig>((json) => Gig.fromJson(json)).toList();
  }

  /// Fetches only confirmed gigs for the specified band.
  Future<List<Gig>> fetchConfirmedGigs(String? bandId) async {
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    final response = await supabase
        .from('gigs')
        .select(_gigSelectClause)
        .eq('band_id', bandId)
        .eq('is_potential', false)
        .order('date', ascending: true);

    return response.map<Gig>((json) => Gig.fromJson(json)).toList();
  }

  /// Fetches upcoming gigs (date >= now) for the specified band.
  Future<List<Gig>> fetchUpcomingGigs(String? bandId) async {
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    final now = DateTime.now().toIso8601String();

    final response = await supabase
        .from('gigs')
        .select(_gigSelectClause)
        .eq('band_id', bandId)
        .gte('date', now)
        .order('date', ascending: true);

    return response.map<Gig>((json) => Gig.fromJson(json)).toList();
  }

  // ==========================================================================
  // RSVP METHODS
  // ==========================================================================

  /// Submit an RSVP response for the current user.
  /// Uses upsert to handle both insert and update cases.
  Future<void> submitRsvp({
    required String gigId,
    required String bandId,
    required String userId,
    required String response, // 'yes' or 'no'
  }) async {
    await supabase.from('gig_responses').upsert({
      'gig_id': gigId,
      'band_id': bandId,
      'user_id': userId,
      'response': response,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'gig_id,user_id');
  }

  /// Get the current user's RSVP for a specific gig (if any).
  Future<String?> getCurrentUserRsvp({
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
}
