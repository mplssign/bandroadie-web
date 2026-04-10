import 'package:flutter/foundation.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import 'models/venue.dart';
import 'models/venue_contact.dart';

// ============================================================================
// VENUES REPOSITORY
// Handles all venue-related data fetching from Supabase.
//
// ISOLATION RULES:
// - Every query REQUIRES a non-null bandId
// - If bandId is null, throws NoBandSelectedError
// ============================================================================

class NoBandSelectedVenuesError extends Error {
  final String message;
  NoBandSelectedVenuesError([
    this.message =
        'No band selected. Cannot fetch venues without a band context.',
  ]);

  @override
  String toString() => 'NoBandSelectedVenuesError: $message';
}

class VenuesRepository {
  final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  Future<List<Venue>> fetchVenues({
    required String? bandId,
    bool forceRefresh = false,
  }) async {
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedVenuesError();
    }

    if (!forceRefresh) {
      final cached = _cache[bandId];
      if (cached != null && !cached.isExpired) {
        return cached.data;
      }
    }

    if (kDebugMode) {
      debugPrint('[VenuesRepository] Fetching venues for band: $bandId');
    }

    final response = await supabase
        .from('venues')
        .select('*, venue_contacts(*)')
        .eq('band_id', bandId)
        .order('name', ascending: true);

    final rows = List<Map<String, dynamic>>.from(response);
    final venues = rows.map((row) => Venue.fromJson(row)).toList();

    _cache[bandId] = _CacheEntry(data: venues);

    if (kDebugMode) {
      debugPrint('[VenuesRepository] Fetched ${venues.length} venues');
    }

    return venues;
  }

  Future<Venue> createVenue({
    required String bandId,
    required Map<String, dynamic> data,
  }) async {
    final insertData = {
      'band_id': bandId,
      ...data,
    };

    final response = await supabase
        .from('venues')
        .insert(insertData)
        .select('*, venue_contacts(*)')
        .single();

    _invalidateCache(bandId);
    return Venue.fromJson(response);
  }

  Future<Venue> updateVenue({
    required String id,
    required Map<String, dynamic> data,
  }) async {
    final response = await supabase
        .from('venues')
        .update(data)
        .eq('id', id)
        .select('*, venue_contacts(*)')
        .single();

    final venue = Venue.fromJson(response);
    _invalidateCache(venue.bandId);
    return venue;
  }

  Future<void> deleteVenue({required String id, required String bandId}) async {
    await supabase.from('venues').delete().eq('id', id);
    _invalidateCache(bandId);
  }

  Future<VenueContact> addVenueContact({
    required String venueId,
    required String bandId,
    required Map<String, dynamic> data,
  }) async {
    final insertData = {
      'venue_id': venueId,
      'band_id': bandId,
      ...data,
    };

    final response = await supabase
        .from('venue_contacts')
        .insert(insertData)
        .select()
        .single();

    _invalidateCache(bandId);
    return VenueContact.fromJson(response);
  }

  Future<VenueContact> updateVenueContact({
    required String contactId,
    required String bandId,
    required Map<String, dynamic> data,
  }) async {
    final response = await supabase
        .from('venue_contacts')
        .update(data)
        .eq('id', contactId)
        .select()
        .single();

    _invalidateCache(bandId);
    return VenueContact.fromJson(response);
  }

  Future<void> removeVenueContact({
    required String contactId,
    required String bandId,
  }) async {
    await supabase.from('venue_contacts').delete().eq('id', contactId);
    _invalidateCache(bandId);
  }

  void _invalidateCache(String bandId) {
    _cache.remove(bandId);
  }

  void clearCache() {
    _cache.clear();
  }
}

class _CacheEntry {
  final List<Venue> data;
  final DateTime createdAt;

  _CacheEntry({required this.data}) : createdAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt) > VenuesRepository._cacheDuration;
}
