import 'package:bandroadie/app/models/rehearsal.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import '../gigs/gig_repository.dart';

// ============================================================================
// REHEARSAL REPOSITORY
// Handles all rehearsal-related data fetching.
//
// ISOLATION RULES (NON-NEGOTIABLE):
// - Every query REQUIRES a non-null bandId
// - If bandId is null, we throw an error — NEVER query all rehearsals
// - Supabase RLS should also enforce this, but we add client-side checks
// ============================================================================

class RehearsalRepository {
  /// Fetches all rehearsals for the specified band.
  ///
  /// IMPORTANT: bandId is REQUIRED. If null, throws NoBandSelectedError.
  Future<List<Rehearsal>> fetchRehearsalsForBand(String? bandId) async {
    // =========================================
    // BAND ISOLATION CHECK — NON-NEGOTIABLE
    // =========================================
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedError(
        'Cannot fetch rehearsals without a band context.',
      );
    }

    final response = await supabase
        .from('rehearsals')
        .select()
        .eq('band_id', bandId)
        .order('date', ascending: true);

    return response.map<Rehearsal>((json) => Rehearsal.fromJson(json)).toList();
  }

  /// Fetches upcoming rehearsals (date >= today) for the specified band.
  Future<List<Rehearsal>> fetchUpcomingRehearsals(String? bandId) async {
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedError(
        'Cannot fetch rehearsals without a band context.',
      );
    }

    final today = DateTime.now().toIso8601String().split('T')[0];

    final response = await supabase
        .from('rehearsals')
        .select()
        .eq('band_id', bandId)
        .gte('date', today)
        .order('date', ascending: true);

    return response.map<Rehearsal>((json) => Rehearsal.fromJson(json)).toList();
  }

  /// Fetches the next upcoming rehearsal for the specified band.
  Future<Rehearsal?> fetchNextRehearsal(String? bandId) async {
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedError(
        'Cannot fetch rehearsals without a band context.',
      );
    }

    final today = DateTime.now().toIso8601String().split('T')[0];

    final response = await supabase
        .from('rehearsals')
        .select()
        .eq('band_id', bandId)
        .gte('date', today)
        .order('date', ascending: true)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return Rehearsal.fromJson(response);
  }
}
