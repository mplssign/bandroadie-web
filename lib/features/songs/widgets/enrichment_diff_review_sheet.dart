import 'package:flutter/material.dart';

import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../models/enrichment_diff_decision.dart';
import '../services/song_enrichment_orchestrator.dart';

// ============================================================================
// ENRICHMENT DIFF REVIEW SHEET
// Shows side-by-side comparison of current vs enriched values with per-field
// accept/reject controls for Show Diffs mode.
// ============================================================================

/// Shows diff review bottom sheet for enrichment preview results.
///
/// Returns map of song ID → accepted fields, or null if cancelled.
Future<Map<String, EnrichmentDiffDecision>?> showEnrichmentDiffReviewSheet(
  BuildContext context, {
  required List<SongEnrichmentDetail> songs,
}) async {
  return showModalBottomSheet<Map<String, EnrichmentDiffDecision>>(
    context: context,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (context) => _EnrichmentDiffReviewSheet(songs: songs),
  );
}

class _EnrichmentDiffReviewSheet extends StatefulWidget {
  final List<SongEnrichmentDetail> songs;

  const _EnrichmentDiffReviewSheet({required this.songs});

  @override
  State<_EnrichmentDiffReviewSheet> createState() =>
      _EnrichmentDiffReviewSheetState();
}

class _EnrichmentDiffReviewSheetState
    extends State<_EnrichmentDiffReviewSheet> {
  // Track per-song decisions
  late Map<String, _SongDiffState> _songStates;

  @override
  void initState() {
    super.initState();
    _initializeStates();
  }

  void _initializeStates() {
    _songStates = {};
    for (final song in widget.songs) {
      _songStates[song.songId] = _SongDiffState(
        // BPM: actionable if enriched value exists and differs from current
        bpmAccepted:
            song.enrichedBpm != null && song.enrichedBpm != song.currentBpm,
        // Key: actionable if enriched value exists and differs from current
        keyAccepted:
            song.enrichedKey != null && song.enrichedKey != song.currentKey,
        // Duration: actionable only if current is 0 and enriched differs
        durationAccepted: song.enrichedDuration != null &&
            (song.currentDuration == null || song.currentDuration == 0) &&
            song.enrichedDuration != song.currentDuration,
      );
    }
  }

  bool get _hasAnyAcceptedFields {
    return _songStates.values.any((state) =>
        state.bpmAccepted || state.keyAccepted || state.durationAccepted);
  }

  void _acceptAll() {
    setState(() {
      for (final song in widget.songs) {
        _songStates[song.songId] = _SongDiffState(
          bpmAccepted:
              song.enrichedBpm != null && song.enrichedBpm != song.currentBpm,
          keyAccepted:
              song.enrichedKey != null && song.enrichedKey != song.currentKey,
          durationAccepted: song.enrichedDuration != null &&
              (song.currentDuration == null || song.currentDuration == 0) &&
              song.enrichedDuration != song.currentDuration,
        );
      }
    });
  }

  void _rejectAll() {
    setState(() {
      for (final songId in _songStates.keys) {
        _songStates[songId] = const _SongDiffState(
          bpmAccepted: false,
          keyAccepted: false,
          durationAccepted: false,
        );
      }
    });
  }

  Map<String, EnrichmentDiffDecision> _buildDecisions() {
    final decisions = <String, EnrichmentDiffDecision>{};
    for (final song in widget.songs) {
      final state = _songStates[song.songId]!;
      final decision = EnrichmentDiffDecision(
        acceptedBpm: state.bpmAccepted ? song.enrichedBpm : null,
        acceptedKey: state.keyAccepted ? song.enrichedKey : null,
        // Only include acceptedDuration if current duration is 0
        acceptedDuration: state.durationAccepted &&
                (song.currentDuration == null || song.currentDuration == 0)
            ? song.enrichedDuration
            : null,
      );
      if (decision.hasAnyAcceptedFields) {
        decisions[song.songId] = decision;
      }
    }
    return decisions;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: Spacing.space12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: Spacing.space16),

              // Header
              Text(
                'Review Enrichment Changes',
                style: AppTextStyles.headline.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: Spacing.space12),

              // Subtitle
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: Spacing.space16),
                child: Text(
                  'Accept or reject enriched values for each field. Only accepted changes will be saved.',
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: Spacing.space24),

              // Song list
              Expanded(
                child: ListView.builder(
                  itemCount: widget.songs.length,
                  itemBuilder: (context, index) {
                    final song = widget.songs[index];
                    final state = _songStates[song.songId]!;
                    return _SongDiffTile(
                      song: song,
                      state: state,
                      onStateChanged: (newState) {
                        setState(() {
                          _songStates[song.songId] = newState;
                        });
                      },
                    );
                  },
                ),
              ),

              // Bulk controls
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.space16,
                  vertical: Spacing.space12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _acceptAll,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: context.colors.primary),
                        ),
                        child: Text(
                          'Accept All',
                          style: TextStyle(color: context.colors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.space12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _rejectAll,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: context.colors.error),
                        ),
                        child: Text(
                          'Reject All',
                          style: TextStyle(color: context.colors.error),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Footer buttons
              Padding(
                padding: const EdgeInsets.all(Spacing.space16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: context.colors.border),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: Spacing.space12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _hasAnyAcceptedFields
                            ? () {
                                final decisions = _buildDecisions();
                                Navigator.of(context).pop(decisions);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.primary,
                          disabledBackgroundColor:
                              context.colors.primary.withValues(alpha: 0.3),
                        ),
                        child: const Text('Confirm'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongDiffState {
  final bool bpmAccepted;
  final bool keyAccepted;
  final bool durationAccepted;

  const _SongDiffState({
    required this.bpmAccepted,
    required this.keyAccepted,
    required this.durationAccepted,
  });
}

class _SongDiffTile extends StatelessWidget {
  final SongEnrichmentDetail song;
  final _SongDiffState state;
  final ValueChanged<_SongDiffState> onStateChanged;

  const _SongDiffTile({
    required this.song,
    required this.state,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Count how many diffs this song has
    final hasBpmDiff =
        song.enrichedBpm != null && song.enrichedBpm != song.currentBpm;
    final hasKeyDiff =
        song.enrichedKey != null && song.enrichedKey != song.currentKey;
    final hasDurationDiff = song.enrichedDuration != null &&
        song.enrichedDuration != song.currentDuration;

    if (!hasBpmDiff && !hasKeyDiff && !hasDurationDiff) {
      // No diffs for this song, don't show it
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space8,
      ),
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Song title/artist
          Text(
            song.title,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          Text(
            song.artist,
            style: AppTextStyles.callout.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: Spacing.space16),

          // BPM diff
          if (hasBpmDiff)
            _DiffRow(
              label: 'BPM',
              currentValue: song.currentBpm?.toString() ?? 'None',
              enrichedValue: song.enrichedBpm.toString(),
              isAccepted: state.bpmAccepted,
              isActionable: true,
              onToggle: (accepted) {
                onStateChanged(_SongDiffState(
                  bpmAccepted: accepted,
                  keyAccepted: state.keyAccepted,
                  durationAccepted: state.durationAccepted,
                ));
              },
            ),

          // Key diff
          if (hasKeyDiff) ...[
            if (hasBpmDiff) const SizedBox(height: Spacing.space12),
            _DiffRow(
              label: 'Key',
              currentValue: song.currentKey ?? 'None',
              enrichedValue: song.enrichedKey!,
              isAccepted: state.keyAccepted,
              isActionable: true,
              onToggle: (accepted) {
                onStateChanged(_SongDiffState(
                  bpmAccepted: state.bpmAccepted,
                  keyAccepted: accepted,
                  durationAccepted: state.durationAccepted,
                ));
              },
            ),
          ],

          // Duration diff
          if (hasDurationDiff) ...[
            if (hasBpmDiff || hasKeyDiff)
              const SizedBox(height: Spacing.space12),
            _DiffRow(
              label: 'Duration',
              currentValue: _formatDuration(song.currentDuration),
              enrichedValue: _formatDuration(song.enrichedDuration),
              isAccepted: state.durationAccepted,
              // Duration is only actionable if current is 0
              isActionable:
                  song.currentDuration == null || song.currentDuration == 0,
              infoMessage: (song.currentDuration != null &&
                      song.currentDuration! > 0)
                  ? 'Current duration is already set. Clear it first to apply enriched value.'
                  : null,
              onToggle: (accepted) {
                onStateChanged(_SongDiffState(
                  bpmAccepted: state.bpmAccepted,
                  keyAccepted: state.keyAccepted,
                  durationAccepted: accepted,
                ));
              },
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds == 0) return 'None';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

class _DiffRow extends StatelessWidget {
  final String label;
  final String currentValue;
  final String enrichedValue;
  final bool isAccepted;
  final bool isActionable;
  final String? infoMessage;
  final ValueChanged<bool> onToggle;

  const _DiffRow({
    required this.label,
    required this.currentValue,
    required this.enrichedValue,
    required this.isAccepted,
    required this.isActionable,
    this.infoMessage,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Label
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: AppTextStyles.callout.copyWith(
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // Current value
            Expanded(
              child: Text(
                currentValue,
                style: AppTextStyles.body.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),

            // Arrow
            Icon(
              Icons.arrow_forward,
              size: 16,
              color: context.colors.textSecondary,
            ),
            const SizedBox(width: Spacing.space8),

            // Enriched value
            Expanded(
              child: Text(
                enrichedValue,
                style: AppTextStyles.body.copyWith(
                  color: context.colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Accept/Reject toggle (only if actionable)
            if (isActionable) ...[
              const SizedBox(width: Spacing.space8),
              Row(
                children: [
                  _ToggleButton(
                    icon: Icons.check,
                    color: Colors.green,
                    isSelected: isAccepted,
                    onTap: () => onToggle(true),
                  ),
                  const SizedBox(width: Spacing.space8),
                  _ToggleButton(
                    icon: Icons.close,
                    color: context.colors.error,
                    isSelected: !isAccepted,
                    onTap: () => onToggle(false),
                  ),
                ],
              ),
            ],
          ],
        ),

        // Info message for non-actionable duration
        if (infoMessage != null) ...[
          const SizedBox(height: Spacing.space8),
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: Colors.blue,
              ),
              const SizedBox(width: Spacing.space8),
              Expanded(
                child: Text(
                  infoMessage!,
                  style: AppTextStyles.footnote.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : context.colors.border,
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? color : context.colors.textSecondary,
        ),
      ),
    );
  }
}
