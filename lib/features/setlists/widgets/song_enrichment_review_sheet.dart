import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/app_button.dart';
import '../../../components/ui/segmented_button_group.dart';
import '../../songs/external_song_lookup_service.dart';
import '../../songs/song_enrichment_service.dart';
import 'bpm_input_dialog.dart';
import 'duration_input_dialog.dart';
import 'key_picker_bottom_sheet.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// SONG ENRICHMENT REVIEW SHEET
// Shown when the user taps an *external* (not-yet-catalogued) search result.
// Fetches BPM + Key in the background while letting the user review/edit
// Duration, BPM, and Key before the song is written to the Catalog.
//
// No provider name appears anywhere on this screen (Feature Input directive).
// Save is never gated on the enrichment fetch completing.
// ============================================================================

/// Final values the user confirmed on Save.
class SongEnrichmentReviewResult {
  final int? durationSeconds;
  final int? bpm;
  final String? musicalKey;

  const SongEnrichmentReviewResult({
    this.durationSeconds,
    this.bpm,
    this.musicalKey,
  });
}

/// Shows the song enrichment review sheet for an external search result.
///
/// Returns a [SongEnrichmentReviewResult] on Save, or null if cancelled.
Future<SongEnrichmentReviewResult?> showSongEnrichmentReviewSheet(
  BuildContext context, {
  required SongLookupResult result,
}) async {
  HapticFeedback.lightImpact();

  return showModalBottomSheet<SongEnrichmentReviewResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) => _SongEnrichmentReviewSheet(result: result),
  );
}

class _SongEnrichmentReviewSheet extends StatefulWidget {
  final SongLookupResult result;

  const _SongEnrichmentReviewSheet({required this.result});

  @override
  State<_SongEnrichmentReviewSheet> createState() =>
      _SongEnrichmentReviewSheetState();
}

class _SongEnrichmentReviewSheetState
    extends State<_SongEnrichmentReviewSheet> {
  late final SongEnrichmentService _enrichmentService;

  int? _currentDurationSeconds;
  int? _currentBpm;
  String? _currentMusicalKey;

  bool _isFetchingEnrichment = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _enrichmentService = SongEnrichmentService(Supabase.instance.client);
    _currentDurationSeconds = widget.result.durationSeconds;
    _fetchEnrichment();
  }

  Future<void> _fetchEnrichment() async {
    final enrichment = await _enrichmentService.lookup(
      title: widget.result.title,
      artist: widget.result.artist,
      durationSeconds: widget.result.durationSeconds,
    );

    if (mounted) {
      setState(() {
        _currentBpm = enrichment.bpm;
        _currentMusicalKey = enrichment.musicalKey;
        _isFetchingEnrichment = false;
      });
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return 'Not found';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _selectDuration() async {
    final result = await showDurationInputDialog(
      context,
      initialSeconds: _currentDurationSeconds ?? 0,
    );
    if (result is DialogCleared<int>) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentDurationSeconds = null;
        _hasChanges = true;
      });
    } else if (result is DialogValue<int>) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentDurationSeconds = result.value;
        _hasChanges = true;
      });
    }
    // DialogCancelled → no change
  }

  Future<void> _selectBpm() async {
    final result = await showBpmInputDialog(context, initialBpm: _currentBpm);
    if (result is DialogCleared<int>) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentBpm = null;
        _hasChanges = true;
      });
    } else if (result is DialogValue<int>) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentBpm = result.value;
        _hasChanges = true;
      });
    }
    // DialogCancelled → no change
  }

  Future<void> _selectKey() async {
    final result = await showKeyPickerBottomSheet(
      context,
      selectedKey: _currentMusicalKey,
    );
    if (result == '') {
      HapticFeedback.selectionClick();
      setState(() {
        _currentMusicalKey = null;
        _hasChanges = true;
      });
    } else if (result != null && result != _currentMusicalKey) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentMusicalKey = result;
        _hasChanges = true;
      });
    }
    // Cancelled or unchanged → no-op
  }

  void _handleSave() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(
      SongEnrichmentReviewResult(
        durationSeconds: _currentDurationSeconds,
        bpm: _currentBpm,
        musicalKey: _currentMusicalKey,
      ),
    );
  }

  void _handleCancel() {
    if (_hasChanges) {
      _showUnsavedChangesDialog();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showUnsavedChangesDialog() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
        ),
        title: Text(
          'Unsaved Changes',
          style:
              AppTextStyles.title3.copyWith(color: context.colors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to leave without saving?',
          style:
              AppTextStyles.body.copyWith(color: context.colors.textSecondary),
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: 'Keep Editing',
                onPressed: () => Navigator.of(context).pop(false),
                variant: AppButtonVariant.primary,
                backgroundColor: AppColors.primary,
              ),
              const SizedBox(height: 8),
              Center(
                child: AppButton(
                  label: 'Discard',
                  onPressed: () => Navigator.of(context).pop(true),
                  variant: AppButtonVariant.text,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleCancel();
      },
      child: Container(
        margin: EdgeInsets.only(bottom: bottomPadding),
        constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Spacing.cardRadius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDragHandle(),
            _buildHeader(),
            Divider(color: context.colors.border, height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSongInfo(),
                    const SizedBox(height: Spacing.space24),
                    _buildMetricsRow(),
                  ],
                ),
              ),
            ),
            _buildFixedBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: context.colors.textMuted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Review Song',
              style: AppTextStyles.pageTitle.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: _handleCancel,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                AppIcons.close,
                size: 24,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongInfo() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildArtwork(),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.result.title,
                style: AppTextStyles.title3.copyWith(
                  color: context.colors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                widget.result.artist,
                style: AppTextStyles.body.copyWith(
                  color: context.colors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildArtwork() {
    const size = 56.0;
    final artwork = widget.result.albumArtwork;

    if (artwork != null && artwork.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          artwork,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        ),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    const size = 56.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.primarySubtle,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(AppIcons.music, size: 24, color: AppColors.primary),
    );
  }

  /// 3-column metrics row: Duration | BPM | Key
  Widget _buildMetricsRow() {
    return SegmentedButtonGroup(
      segments: [
        SegmentData(
          label: 'Duration',
          value: _formatDuration(_currentDurationSeconds),
          onTap: _selectDuration,
        ),
        SegmentData(
          label: 'BPM',
          value: _isFetchingEnrichment
              ? '...'
              : (_currentBpm?.toString() ?? 'Not found'),
          onTap: _selectBpm,
        ),
        SegmentData(
          label: 'Key',
          value: _isFetchingEnrichment
              ? '...'
              : (_currentMusicalKey == null || _currentMusicalKey!.isEmpty
                  ? 'Not found'
                  : _currentMusicalKey!),
          onTap: _selectKey,
        ),
      ],
    );
  }

  Widget _buildFixedBottomActions() {
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          top: BorderSide(
            color: context.colors.border.withValues(alpha: 0.5),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: Spacing.space16,
        right: Spacing.space16,
        top: 12,
        bottom: bottomSafe + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Save',
            // Save is never gated on the enrichment fetch completing.
            onPressed: _handleSave,
            variant: AppButtonVariant.primary,
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            fullWidth: true,
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Cancel',
            onPressed: _handleCancel,
            variant: AppButtonVariant.text,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
          ),
        ],
      ),
    );
  }
}
