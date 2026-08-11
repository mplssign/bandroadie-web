/// Enrichment settings model for band-level enrichment preferences
class EnrichmentSettings {
  final String id;
  final String bandId;
  final NewSongBehavior newSongBehavior;
  final ExistingSongBehavior existingSongBehavior;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EnrichmentSettings({
    required this.id,
    required this.bandId,
    required this.newSongBehavior,
    required this.existingSongBehavior,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EnrichmentSettings.fromSupabase(Map<String, dynamic> json) {
    return EnrichmentSettings(
      id: json['id'] as String,
      bandId: json['band_id'] as String,
      newSongBehavior:
          _parseNewSongBehavior(json['new_song_behavior'] as String),
      existingSongBehavior:
          _parseExistingSongBehavior(json['existing_song_behavior'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  static NewSongBehavior _parseNewSongBehavior(String value) {
    switch (value) {
      case 'ask':
        return NewSongBehavior.ask;
      case 'auto':
        return NewSongBehavior.auto;
      case 'off':
        return NewSongBehavior.off;
      default:
        return NewSongBehavior.ask; // fallback
    }
  }

  static ExistingSongBehavior _parseExistingSongBehavior(String value) {
    // Only fill-missing-only is valid after revert migration
    // Fall back to fillMissingOnly for any unexpected values
    return ExistingSongBehavior.fillMissingOnly;
  }
}

/// Enum for new song enrichment behavior
enum NewSongBehavior {
  ask, // Show review modal before adding
  auto, // Auto-enrich in background, no modal
  off, // No enrichment, manual entry only
}

/// Enum for existing song enrichment behavior
/// After Phase 2.2 revert, only fillMissingOnly is allowed
enum ExistingSongBehavior {
  fillMissingOnly, // Only update NULL fields (enrichment never overwrites)
}
