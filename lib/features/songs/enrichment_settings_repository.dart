import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/enrichment_settings.dart';

/// Repository for managing enrichment settings in Supabase
class EnrichmentSettingsRepository {
  final SupabaseClient _supabase;

  EnrichmentSettingsRepository(this._supabase);

  /// Get or create enrichment settings for a band
  Future<EnrichmentSettings> getOrCreateSettings(String bandId) async {
    try {
      final response = await _supabase.rpc(
        'get_or_create_enrichment_settings',
        params: {'p_band_id': bandId},
      );
      return EnrichmentSettings.fromSupabase(response as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to get enrichment settings: $e');
    }
  }

  /// Update enrichment settings for a band
  Future<EnrichmentSettings> updateSettings({
    required String bandId,
    required NewSongBehavior newSongBehavior,
    required ExistingSongBehavior existingSongBehavior,
  }) async {
    try {
      final response = await _supabase.rpc(
        'update_enrichment_settings',
        params: {
          'p_band_id': bandId,
          'p_new_song_behavior': _serializeNewSongBehavior(newSongBehavior),
          'p_existing_song_behavior':
              _serializeExistingSongBehavior(existingSongBehavior),
        },
      );
      return EnrichmentSettings.fromSupabase(response as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to update enrichment settings: $e');
    }
  }

  String _serializeNewSongBehavior(NewSongBehavior behavior) {
    switch (behavior) {
      case NewSongBehavior.ask:
        return 'ask';
      case NewSongBehavior.auto:
        return 'auto';
      case NewSongBehavior.off:
        return 'off';
    }
  }

  String _serializeExistingSongBehavior(ExistingSongBehavior behavior) {
    switch (behavior) {
      case ExistingSongBehavior.fillMissingOnly:
        return 'fill-missing-only';
      case ExistingSongBehavior.autoReplace:
        return 'auto-replace';
      case ExistingSongBehavior.showDiffs:
        return 'show-diffs';
    }
  }
}

/// Riverpod provider for EnrichmentSettingsRepository
final enrichmentSettingsRepositoryProvider =
    Provider<EnrichmentSettingsRepository>((ref) {
  return EnrichmentSettingsRepository(Supabase.instance.client);
});
