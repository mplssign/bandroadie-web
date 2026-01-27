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

  /// Fetches upcoming rehearsals (end time in the future) for the specified band.
  /// Filters based on end time to ensure past rehearsals don't appear.
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

    // Filter client-side by end time to exclude events that have already ended
    final now = DateTime.now().toUtc();
    final rehearsals = response
        .map<Rehearsal>((json) => Rehearsal.fromJson(json))
        .where((rehearsal) {
          try {
            // Combine date and end time to get the actual end DateTime
            final endDateTime = DateTime(
              rehearsal.date.year,
              rehearsal.date.month,
              rehearsal.date.day,
              int.parse(rehearsal.endTime.split(':')[0]),
              int.parse(rehearsal.endTime.split(':')[1]),
            ).toUtc();
            return endDateTime.isAfter(now);
          } catch (e) {
            // If parsing fails, include the rehearsal to be safe
            return true;
          }
        })
        .toList();

    return rehearsals;
  }

  /// Fetches the next upcoming rehearsal for the specified band.
  /// Returns the first rehearsal with an end time in the future.
  Future<Rehearsal?> fetchNextRehearsal(String? bandId) async {
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedError(
        'Cannot fetch rehearsals without a band context.',
      );
    }

    final today = DateTime.now().toIso8601String().split('T')[0];
    final now = DateTime.now().toUtc();

    final response = await supabase
        .from('rehearsals')
        .select()
        .eq('band_id', bandId)
        .gte('date', today)
        .order('date', ascending: true);

    // Filter to find the first rehearsal with end time in the future
    final rehearsals = response
        .map<Rehearsal>((json) => Rehearsal.fromJson(json))
        .toList();

    for (final rehearsal in rehearsals) {
      try {
        // Combine date and end time to get the actual end DateTime
        final endDateTime = DateTime(
          rehearsal.date.year,
          rehearsal.date.month,
          rehearsal.date.day,
          int.parse(rehearsal.endTime.split(':')[0]),
          int.parse(rehearsal.endTime.split(':')[1]),
        ).toUtc();
        
        if (endDateTime.isAfter(now)) {
          return rehearsal;
        }
      } catch (e) {
        // If parsing fails, return this rehearsal to be safe
        return rehearsal;
      }
    }

    return null;
  }
}
