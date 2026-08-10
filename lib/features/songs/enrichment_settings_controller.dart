import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bands/active_band_controller.dart';
import 'enrichment_settings_repository.dart';
import 'models/enrichment_settings.dart';

/// Controller for enrichment settings state management
class EnrichmentSettingsController extends AsyncNotifier<EnrichmentSettings> {
  @override
  Future<EnrichmentSettings> build() async {
    // Watch active band to auto-refresh when band changes
    final activeBand = ref.watch(activeBandProvider);
    final bandId = activeBand.activeBand?.id;

    if (bandId == null) {
      throw Exception('No active band');
    }

    final repository = ref.read(enrichmentSettingsRepositoryProvider);
    return await repository.getOrCreateSettings(bandId);
  }

  /// Update enrichment settings for the active band
  Future<void> updateSettings({
    required NewSongBehavior newSongBehavior,
    required ExistingSongBehavior existingSongBehavior,
  }) async {
    final activeBand = ref.read(activeBandProvider);
    final bandId = activeBand.activeBand?.id;

    if (bandId == null) return;

    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final repository = ref.read(enrichmentSettingsRepositoryProvider);
      return await repository.updateSettings(
        bandId: bandId,
        newSongBehavior: newSongBehavior,
        existingSongBehavior: existingSongBehavior,
      );
    });
  }
}

/// Riverpod provider for enrichment settings
final enrichmentSettingsProvider =
    AsyncNotifierProvider<EnrichmentSettingsController, EnrichmentSettings>(
  EnrichmentSettingsController.new,
);
