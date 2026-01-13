import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/block_out.dart';
import 'package:bandroadie/app/services/supabase_client.dart';

// ============================================================================
// BLOCK OUT REPOSITORY
// Repository for managing block dates (unavailable dates).
// Implements lightweight caching with 5-minute TTL, keyed by bandId.
//
// Table: public.block_dates
// Columns: id, user_id, band_id, date (date), reason (text NOT NULL),
//          created_at, updated_at
// Unique: (user_id, band_id, date)
//
// BAND ISOLATION: Every operation REQUIRES a non-null bandId.
// ============================================================================

/// Exception thrown when attempting operations without a band context.
class NoBandSelectedError extends Error {
  final String message;
  NoBandSelectedError([
    this.message = 'No band selected. Cannot perform this operation.',
  ]);

  @override
  String toString() => 'NoBandSelectedError: $message';
}

/// Cache entry with timestamp
class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;

  _CacheEntry(this.data) : timestamp = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(timestamp).inMinutes >= 5; // 5-minute TTL
}

class BlockOutRepository {
  // Cache: key = bandId
  final Map<String, _CacheEntry<List<BlockOut>>> _cache = {};

  /// Invalidate cache for a band (call after create/update/delete)
  void invalidateCache(String bandId) {
    debugPrint('[BlockOutRepository] Invalidating cache for band: $bandId');
    _cache.remove(bandId);
  }

  /// Clear all cache (e.g., on logout)
  void clearAllCache() {
    _cache.clear();
  }

  // ============================================================================
  // FETCH OPERATIONS
  // ============================================================================

  /// Fetch all block dates for a band
  Future<List<BlockOut>> fetchBlockOutsForBand(
    String bandId, {
    bool forceRefresh = false,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    // Check cache
    if (!forceRefresh) {
      final cached = _cache[bandId];
      if (cached != null && !cached.isExpired) {
        debugPrint(
          '[BlockOutRepository] Returning cached: ${cached.data.length} block dates',
        );
        return cached.data;
      }
    }

    debugPrint('[BlockOutRepository] Fetching block dates for band: $bandId');

    try {
      final response = await supabase
          .from('block_dates')
          .select()
          .eq('band_id', bandId)
          .order('date', ascending: true);

      final blockOuts = (response as List)
          .map((row) => BlockOut.fromJson(row as Map<String, dynamic>))
          .toList();

      // Update cache
      _cache[bandId] = _CacheEntry(blockOuts);

      debugPrint(
        '[BlockOutRepository] Fetched ${blockOuts.length} block dates',
      );

      return blockOuts;
    } catch (e) {
      debugPrint('[BlockOutRepository] Failed to load block_dates: $e');
      rethrow;
    }
  }

  // ============================================================================
  // CREATE / UPDATE / DELETE
  // ============================================================================

  /// Create a new block date
  /// If creating a range (startDate to untilDate), creates multiple rows.
  Future<List<BlockOut>> createBlockOut({
    required String bandId,
    required String userId,
    required DateTime startDate,
    DateTime? untilDate,
    String? reason,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    debugPrint('[BlockOutRepository] Creating block date(s) for band: $bandId');

    // Normalize reason: empty string if null/blank (DB column is NOT NULL)
    final normalizedReason = reason?.trim().isNotEmpty == true
        ? reason!.trim()
        : '';

    // Format date as YYYY-MM-DD
    String formatDate(DateTime dt) {
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    final results = <BlockOut>[];

    // If untilDate is provided and different from startDate, create multiple rows
    if (untilDate != null && !_isSameDay(startDate, untilDate)) {
      // Multi-day range: create one row per date
      var current = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(untilDate.year, untilDate.month, untilDate.day);

      while (!current.isAfter(end)) {
        final data = {
          'band_id': bandId,
          'user_id': userId,
          'date': formatDate(current),
          'reason': normalizedReason,
        };

        try {
          final response = await supabase
              .from('block_dates')
              .insert(data)
              .select()
              .single();

          results.add(BlockOut.fromJson(response));
        } catch (e) {
          // Skip duplicates (unique constraint on user_id, band_id, date)
          debugPrint(
            '[BlockOutRepository] Skipping duplicate date ${formatDate(current)}: $e',
          );
        }

        current = current.add(const Duration(days: 1));
      }
    } else {
      // Single day
      final data = {
        'band_id': bandId,
        'user_id': userId,
        'date': formatDate(startDate),
        'reason': normalizedReason,
      };

      final response = await supabase
          .from('block_dates')
          .insert(data)
          .select()
          .single();

      results.add(BlockOut.fromJson(response));
    }

    invalidateCache(bandId);

    debugPrint('[BlockOutRepository] Created ${results.length} block date(s)');
    return results;
  }

  /// Update an existing block date
  Future<BlockOut> updateBlockOut({
    required String blockOutId,
    required String bandId,
    required DateTime date,
    String? reason,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    debugPrint(
      '[BlockOutRepository] Updating block date $blockOutId for band: $bandId',
    );

    // Format date as YYYY-MM-DD
    String formatDate(DateTime dt) {
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    // Normalize reason
    final normalizedReason = reason?.trim().isNotEmpty == true
        ? reason!.trim()
        : '';

    final data = {
      'date': formatDate(date),
      'reason': normalizedReason,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final response = await supabase
        .from('block_dates')
        .update(data)
        .eq('id', blockOutId)
        .eq('band_id', bandId)
        .select()
        .single();

    invalidateCache(bandId);
    return BlockOut.fromJson(response);
  }

  /// Delete a block date
  Future<void> deleteBlockOut({
    required String blockOutId,
    required String bandId,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    debugPrint(
      '[BlockOutRepository] Deleting block date $blockOutId for band: $bandId',
    );

    await supabase
        .from('block_dates')
        .delete()
        .eq('id', blockOutId)
        .eq('band_id', bandId);

    invalidateCache(bandId);
  }

  /// Delete all block dates in a span (startDate through endDate)
  /// Used when editing or deleting a multi-day block out.
  Future<void> deleteBlockOutSpan({
    required String userId,
    required String bandId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    debugPrint(
      '[BlockOutRepository] Deleting block date span for band: $bandId from $startDate to $endDate',
    );

    // Format dates as YYYY-MM-DD
    String formatDate(DateTime dt) {
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    await supabase
        .from('block_dates')
        .delete()
        .eq('user_id', userId)
        .eq('band_id', bandId)
        .gte('date', formatDate(startDate))
        .lte('date', formatDate(endDate));

    invalidateCache(bandId);
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ============================================================================
// PROVIDER
// ============================================================================

final blockOutRepositoryProvider = Provider<BlockOutRepository>((ref) {
  return BlockOutRepository();
});
