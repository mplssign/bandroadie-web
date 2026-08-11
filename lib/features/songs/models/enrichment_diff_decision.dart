// ============================================================================
// ENRICHMENT DIFF DECISION
// Model for per-song field acceptance decisions in diff review UI
// ============================================================================

/// Represents user's accept/reject decisions for enriched fields.
///
/// Used by [EnrichmentDiffReviewSheet] to track which fields the user
/// accepted for each song, then passed to [applyEnrichmentDiff()] to
/// write only the accepted fields to the database.
class EnrichmentDiffDecision {
  final int? acceptedBpm;
  final String? acceptedKey;
  final int? acceptedDuration;

  const EnrichmentDiffDecision({
    this.acceptedBpm,
    this.acceptedKey,
    this.acceptedDuration,
  });

  /// Returns true if at least one field is accepted.
  bool get hasAnyAcceptedFields =>
      acceptedBpm != null || acceptedKey != null || acceptedDuration != null;

  /// Creates a copy with updated fields.
  EnrichmentDiffDecision copyWith({
    int? acceptedBpm,
    String? acceptedKey,
    int? acceptedDuration,
  }) {
    return EnrichmentDiffDecision(
      acceptedBpm: acceptedBpm ?? this.acceptedBpm,
      acceptedKey: acceptedKey ?? this.acceptedKey,
      acceptedDuration: acceptedDuration ?? this.acceptedDuration,
    );
  }
}
