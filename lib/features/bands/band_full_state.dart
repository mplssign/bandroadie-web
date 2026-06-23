import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/models/band_member.dart';
import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/models/rehearsal.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import '../setlists/models/setlist.dart';
import 'active_band_controller.dart';

// ============================================================================
// BAND FULL STATE
// Single RPC call to load all band-scoped data at once.
//
// Replaces multiple sequential/parallel Supabase queries with one
// database round-trip via the get_band_full_state RPC function.
//
// Used for initial band load. Individual controllers still handle
// targeted refresh after mutations (create/edit/delete).
// ============================================================================

/// Container for all band-scoped data returned by the RPC
class BandFullState {
  final Band band;
  final List<BandMember> members;
  final List<Gig> gigs;
  final List<Rehearsal> rehearsals;
  final List<Setlist> setlists;

  const BandFullState({
    required this.band,
    required this.members,
    required this.gigs,
    required this.rehearsals,
    required this.setlists,
  });
}

// ============================================================================
// REPOSITORY
// ============================================================================

class BandFullStateRepository {
  /// Fetch all band-scoped data in a single RPC call.
  ///
  /// Returns structured data from the get_band_full_state Postgres function,
  /// which joins bands, band_members, gigs (with gig_dates), rehearsals,
  /// and setlists (with song counts) server-side.
  Future<BandFullState> fetchBandFullState(String bandId) async {
    final data = await supabase.rpc(
      'get_band_full_state',
      params: {'p_band_id': bandId},
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () =>
          throw TimeoutException('Dashboard load timed out after 15 seconds'),
    );

    final result = data as Map<String, dynamic>;

    // Parse band (null means band was deleted or RPC returned invalid data)
    final bandData = result['band'];
    if (bandData == null) {
      throw Exception('Band data not found in RPC response');
    }
    final band = Band.fromJson(bandData as Map<String, dynamic>);

    // Parse members
    final membersRaw = result['members'] as List<dynamic>;
    final members = membersRaw
        .map((m) => BandMember.fromJson(m as Map<String, dynamic>))
        .toList();

    // Parse gigs (includes nested gig_dates from the RPC)
    final gigsRaw = result['gigs'] as List<dynamic>;
    final gigs =
        gigsRaw.map((g) => Gig.fromJson(g as Map<String, dynamic>)).toList();

    // Parse rehearsals
    final rehearsalsRaw = result['rehearsals'] as List<dynamic>;
    final rehearsals = rehearsalsRaw
        .map((r) => Rehearsal.fromJson(r as Map<String, dynamic>))
        .toList();

    // Parse setlists (song_count is a flat integer from the RPC)
    final setlistsRaw = result['setlists'] as List<dynamic>;
    final setlists = setlistsRaw
        .map((s) => Setlist.fromSupabase(s as Map<String, dynamic>))
        .toList();

    return BandFullState(
      band: band,
      members: members,
      gigs: gigs,
      rehearsals: rehearsals,
      setlists: setlists,
    );
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

final bandFullStateRepositoryProvider =
    Provider<BandFullStateRepository>((ref) {
  return BandFullStateRepository();
});

/// Reactive provider that fetches full band state when the active band changes.
///
/// Watched by GigNotifier and RehearsalNotifier for initial data load.
/// Invalidate this provider to re-fetch everything via RPC (e.g., pull-to-refresh).
///
/// NOT autoDispose: consumers (gigProvider, rehearsalProvider) are non-autoDispose
/// NotifierProviders, so this would never actually be disposed. Using a plain
/// FutureProvider makes the lifecycle intent explicit.
final bandFullStateProvider = FutureProvider<BandFullState?>((ref) async {
  final bandId = ref.watch(activeBandIdProvider);
  if (bandId == null) return null;

  final repo = ref.read(bandFullStateRepositoryProvider);
  return repo.fetchBandFullState(bandId);
});
