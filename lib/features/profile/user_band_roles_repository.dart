import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/services/supabase_client.dart';

// ============================================================================
// USER BAND ROLES REPOSITORY
// Handles band-specific role assignments.
//
// PURPOSE:
// - Allows users in multiple bands to have different roles per band
// - Provides fallback to global roles when no band-specific roles exist
//
// DATA MODEL:
// - user_band_roles table: { id, user_id, band_id, roles[], updated_at }
// - One row per (user_id, band_id) pair
// - roles is text[] array
//
// CACHING:
// - Simple in-memory cache per {userId, bandId} with 5-minute TTL
// - Cache is invalidated on upsert
// ============================================================================

/// Exception thrown when user is not authenticated
class NotAuthenticatedError extends Error {
  final String message;
  NotAuthenticatedError([this.message = 'User is not authenticated']);

  @override
  String toString() => 'NotAuthenticatedError: $message';
}

/// Cache entry with expiration
class _CacheEntry {
  final List<String> roles;
  final DateTime createdAt;

  _CacheEntry({required this.roles}) : createdAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt) >
      UserBandRolesRepository._cacheDuration;
}

class UserBandRolesRepository {
  /// Cache keyed by "userId:bandId"
  final Map<String, _CacheEntry> _cache = {};

  /// Cache duration
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Generates cache key from userId and bandId
  String _cacheKey(String userId, String bandId) => '$userId:$bandId';

  /// Fetches roles for a specific user in a specific band.
  ///
  /// Returns empty list if no row exists (caller should handle fallback).
  /// Set [forceRefresh] to bypass cache.
  Future<List<String>> fetchRolesForBand({
    required String bandId,
    required String userId,
    bool forceRefresh = false,
  }) async {
    if (bandId.isEmpty || userId.isEmpty) {
      return [];
    }

    final cacheKey = _cacheKey(userId, bandId);

    // Check cache first
    if (!forceRefresh) {
      final cached = _cache[cacheKey];
      if (cached != null && !cached.isExpired) {
        return cached.roles;
      }
    }

    try {
      final response = await supabase
          .from('user_band_roles')
          .select('roles')
          .eq('user_id', userId)
          .eq('band_id', bandId)
          .maybeSingle();

      if (response == null) {
        // No row exists - return empty list (caller handles fallback)
        _cache[cacheKey] = _CacheEntry(roles: []);
        return [];
      }

      final rolesRaw = response['roles'];
      final List<String> roles;
      if (rolesRaw is List) {
        roles = rolesRaw.cast<String>();
      } else {
        roles = [];
      }

      _cache[cacheKey] = _CacheEntry(roles: roles);
      return roles;
    } catch (e) {
      // On error, return empty list and don't cache
      // ignore: avoid_print
      print('[UserBandRolesRepository] Error fetching roles: $e');
      return [];
    }
  }

  /// Upserts roles for a specific user in a specific band.
  ///
  /// Creates a new row if none exists, updates if it does.
  /// Invalidates cache after successful upsert.
  Future<void> upsertRolesForBand({
    required String bandId,
    required String userId,
    required List<String> roles,
  }) async {
    if (bandId.isEmpty || userId.isEmpty) {
      throw ArgumentError('bandId and userId must not be empty');
    }

    await supabase.from('user_band_roles').upsert({
      'user_id': userId,
      'band_id': bandId,
      'roles': roles,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,band_id');

    // Invalidate cache for this user/band
    final cacheKey = _cacheKey(userId, bandId);
    _cache.remove(cacheKey);
  }

  /// Fetches roles for a user across multiple bands (batch fetch).
  ///
  /// Returns a map of bandId -> roles[].
  /// Bands without a row will not appear in the map.
  /// Useful for loading all band roles at once on profile screen.
  Future<Map<String, List<String>>> fetchRolesForBands({
    required List<String> bandIds,
    required String userId,
  }) async {
    if (bandIds.isEmpty || userId.isEmpty) {
      return {};
    }

    try {
      final response = await supabase
          .from('user_band_roles')
          .select('band_id, roles')
          .eq('user_id', userId)
          .inFilter('band_id', bandIds);

      final Map<String, List<String>> result = {};

      for (final row in response) {
        final bandId = row['band_id'] as String?;
        final rolesRaw = row['roles'];

        if (bandId != null) {
          final List<String> roles;
          if (rolesRaw is List) {
            roles = rolesRaw.cast<String>();
          } else {
            roles = [];
          }
          result[bandId] = roles;

          // Update cache for each band
          final cacheKey = _cacheKey(userId, bandId);
          _cache[cacheKey] = _CacheEntry(roles: roles);
        }
      }

      return result;
    } catch (e) {
      // ignore: avoid_print
      print('[UserBandRolesRepository] Error batch fetching roles: $e');
      return {};
    }
  }

  /// Fetches roles for multiple users in a single band (batch fetch for Members screen).
  ///
  /// Returns a map of userId -> roles[].
  /// Users without a row will not appear in the map (caller handles fallback).
  Future<Map<String, List<String>>> fetchRolesForUsers({
    required String bandId,
    required List<String> userIds,
  }) async {
    if (bandId.isEmpty || userIds.isEmpty) {
      return {};
    }

    try {
      final response = await supabase
          .from('user_band_roles')
          .select('user_id, roles')
          .eq('band_id', bandId)
          .inFilter('user_id', userIds);

      final Map<String, List<String>> result = {};

      for (final row in response) {
        final odaId = row['user_id'] as String?;
        final rolesRaw = row['roles'];

        if (odaId != null) {
          final List<String> roles;
          if (rolesRaw is List) {
            roles = rolesRaw.cast<String>();
          } else {
            roles = [];
          }
          result[odaId] = roles;
        }
      }

      return result;
    } catch (e) {
      // ignore: avoid_print
      print('[UserBandRolesRepository] Error fetching roles for users: $e');
      return {};
    }
  }

  /// Checks if a row exists for the given user and band.
  ///
  /// Used to determine if we need to seed from global roles.
  Future<bool> hasRolesForBand({
    required String bandId,
    required String userId,
  }) async {
    if (bandId.isEmpty || userId.isEmpty) {
      return false;
    }

    // Check cache first
    final cacheKey = _cacheKey(userId, bandId);
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      // If cached, a row exists (even if empty)
      return true;
    }

    try {
      final response = await supabase
          .from('user_band_roles')
          .select('id')
          .eq('user_id', userId)
          .eq('band_id', bandId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  /// Clears cache for a specific user/band or all.
  void clearCache({String? userId, String? bandId}) {
    if (userId != null && bandId != null) {
      _cache.remove(_cacheKey(userId, bandId));
    } else {
      _cache.clear();
    }
  }
}

// ============================================================================
// PROVIDER
// ============================================================================

/// Provider for the user band roles repository
final userBandRolesRepositoryProvider = Provider<UserBandRolesRepository>((
  ref,
) {
  return UserBandRolesRepository();
});
