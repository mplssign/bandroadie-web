import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/utils/title_case_formatter.dart';
import '../models/setlist_song.dart';
import '../tuning/tuning_helpers.dart';
import 'masked_duration_input.dart';
import 'tuning_picker_bottom_sheet.dart';

// ============================================================================
// SONG DETAILS BOTTOM SHEET
// Bottom sheet for viewing/editing song notes and tuning.
//
// Features:
// - Editable song title and artist (tap to edit)
// - Tuning selector (tap to change)
// - Notes text field (multi-line, title case)
// - Save button
// - Physics-based entrance/exit animation
// ============================================================================

/// Result from the song details bottom sheet
class SongDetailsResult {
  final String? title;
  final String? artist;
  final String? notes;
  final String? tuning;
  final int? bpm;
  final int? duration;
  final bool hasChanges;

  // Flags to indicate which fields were changed (needed to distinguish
  // "no change" from "changed to null/empty")
  final bool titleChanged;
  final bool artistChanged;
  final bool notesChanged;
  final bool tuningChanged;
  final bool bpmChanged;
  final bool durationChanged;

  const SongDetailsResult({
    this.title,
    this.artist,
    this.notes,
    this.tuning,
    this.bpm,
    this.duration,
    required this.hasChanges,
    this.titleChanged = false,
    this.artistChanged = false,
    this.notesChanged = false,
    this.tuningChanged = false,
    this.bpmChanged = false,
    this.durationChanged = false,
  });
}

/// Show the song details bottom sheet.
///
/// Returns a [SongDetailsResult] with any changes, or null if cancelled.
Future<SongDetailsResult?> showSongDetailsBottomSheet(
  BuildContext context, {
  required SetlistSong song,
}) async {
  HapticFeedback.lightImpact();

  return showModalBottomSheet<SongDetailsResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) => _SongDetailsSheet(song: song),
  );
}

class _SongDetailsSheet extends StatefulWidget {
  final SetlistSong song;

  const _SongDetailsSheet({required this.song});

  @override
  State<_SongDetailsSheet> createState() => _SongDetailsSheetState();
}

class _SongDetailsSheetState extends State<_SongDetailsSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _notesController;
  late TextEditingController _bpmController;
  late String _currentTuning;

  // Duration is tracked as seconds (used by MaskedDurationInput)
  late int _currentDurationSeconds;

  bool _isEditingTitle = false;
  bool _isEditingArtist = false;
  bool _hasChanges = false;

  final FocusNode _titleFocus = FocusNode();
  final FocusNode _artistFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: widget.song.title);
    _artistController = TextEditingController(text: widget.song.artist);
    _notesController = TextEditingController(text: widget.song.notes ?? '');
    _bpmController = TextEditingController(
      text: widget.song.bpm != null ? widget.song.bpm.toString() : '',
    );
    _currentDurationSeconds = widget.song.durationSeconds;
    _currentTuning = widget.song.tuning ?? 'standard_e';

    _titleController.addListener(_checkForChanges);
    _artistController.addListener(_checkForChanges);
    _notesController.addListener(_checkForChanges);
    _bpmController.addListener(_checkForChanges);

    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus) {
        setState(() => _isEditingTitle = false);
      }
    });

    _artistFocus.addListener(() {
      if (!_artistFocus.hasFocus) {
        setState(() => _isEditingArtist = false);
      }
    });

    // Setup entrance animation
    _animController = AnimationController(
      duration: AppDurations.medium,
      vsync: this,
    );

    _slideAnimation = Tween<double>(begin: 0.3, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: AppCurves.rubberband),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _titleController.removeListener(_checkForChanges);
    _artistController.removeListener(_checkForChanges);
    _notesController.removeListener(_checkForChanges);
    _bpmController.removeListener(_checkForChanges);
    _titleController.dispose();
    _artistController.dispose();
    _notesController.dispose();
    _bpmController.dispose();
    _titleFocus.dispose();
    _artistFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _checkForChanges() {
    // Apply same transformations as _handleSave for accurate comparison
    final newTitle = toTitleCase(_titleController.text.trim());
    final newArtist = toTitleCase(_artistController.text.trim());
    final newNotes = _notesController.text.trim();
    final originalTuning = widget.song.tuning ?? 'standard_e';
    final newBpm = _parseBpm();

    final titleChanged = newTitle != widget.song.title;
    final artistChanged = newArtist != widget.song.artist;
    final notesChanged = newNotes != (widget.song.notes ?? '');
    final tuningChanged = _currentTuning != originalTuning;
    final bpmChanged = newBpm != widget.song.bpm;
    final durationChanged =
        _currentDurationSeconds != widget.song.durationSeconds;

    setState(() {
      _hasChanges =
          titleChanged ||
          artistChanged ||
          notesChanged ||
          tuningChanged ||
          bpmChanged ||
          durationChanged;
    });
  }

  /// Parse BPM from text field, returns null if empty or invalid
  int? _parseBpm() {
    final text = _bpmController.text.trim();
    if (text.isEmpty) return null;
    final bpm = int.tryParse(text);
    if (bpm != null && bpm >= 20 && bpm <= 300) return bpm;
    return null;
  }

  /// Called when duration changes via MaskedDurationInput
  void _onDurationChanged(int seconds) {
    setState(() {
      _currentDurationSeconds = seconds;
    });
    _checkForChanges();
  }

  void _startEditingTitle() {
    setState(() => _isEditingTitle = true);
    Future.delayed(const Duration(milliseconds: 50), () {
      _titleFocus.requestFocus();
    });
  }

  void _startEditingArtist() {
    setState(() => _isEditingArtist = true);
    Future.delayed(const Duration(milliseconds: 50), () {
      _artistFocus.requestFocus();
    });
  }

  Future<void> _selectTuning() async {
    final result = await showTuningPickerBottomSheet(
      context,
      selectedTuningIdOrName: _currentTuning,
    );

    if (result != null && result != _currentTuning) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentTuning = result;
        _hasChanges = true;
      });
    }
  }

  void _handleSave() {
    HapticFeedback.lightImpact();

    final newTitle = toTitleCase(_titleController.text.trim());
    final newArtist = toTitleCase(_artistController.text.trim());
    final newNotes = _notesController.text.trim();
    final originalTuning = widget.song.tuning ?? 'standard_e';
    final newBpm = _parseBpm();

    // Determine which fields changed
    final titleChanged = newTitle != widget.song.title;
    final artistChanged = newArtist != widget.song.artist;
    final notesChanged = newNotes != (widget.song.notes ?? '');
    final tuningChanged = _currentTuning != originalTuning;
    final bpmChanged = newBpm != widget.song.bpm;
    final durationChanged =
        _currentDurationSeconds != widget.song.durationSeconds;

    final result = SongDetailsResult(
      title: titleChanged ? newTitle : null,
      artist: artistChanged ? newArtist : null,
      notes: notesChanged ? newNotes : null,
      tuning: tuningChanged ? _currentTuning : null,
      bpm: newBpm, // Always include so handler can check bpmChanged flag
      duration:
          _currentDurationSeconds, // Always include so handler can check durationChanged flag
      hasChanges: _hasChanges,
      titleChanged: titleChanged,
      artistChanged: artistChanged,
      notesChanged: notesChanged,
      tuningChanged: tuningChanged,
      bpmChanged: bpmChanged,
      durationChanged: durationChanged,
    );

    Navigator.of(context).pop(result);
  }

  void _handleCancel() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return FractionalTranslation(
          translation: Offset(0, _slideAnimation.value),
          child: Opacity(opacity: _fadeAnimation.value, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: bottomPadding),
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.85,
          minHeight: screenHeight * 0.6,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Spacing.cardRadius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDragHandle(),
            _buildHeader(),
            const Divider(color: AppColors.borderMuted, height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSongInfo(),
                    const SizedBox(height: Spacing.space24),
                    _buildMetricsRow(),
                    const SizedBox(height: Spacing.space24),
                    _buildNotesSection(),
                    const SizedBox(height: Spacing.space24),
                    _buildActions(),
                    SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 16,
                    ),
                  ],
                ),
              ),
            ),
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
        color: AppColors.textMuted.withValues(alpha: 0.3),
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
              'Song Details',
              style: AppTextStyles.title3.copyWith(fontSize: 18),
            ),
          ),
          GestureDetector(
            onTap: _handleCancel,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.close_rounded,
                size: 24,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Song Title - tap to edit
        Text(
          'Song Title',
          style: AppTextStyles.callout.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _isEditingTitle
            ? Container(
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBg,
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  border: Border.all(color: AppColors.accent, width: 1.5),
                ),
                child: TextField(
                  controller: _titleController,
                  focusNode: _titleFocus,
                  textCapitalization: TextCapitalization.words,
                  style: AppTextStyles.title3,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => setState(() => _isEditingTitle = false),
                ),
              )
            : GestureDetector(
                onTap: _startEditingTitle,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.scaffoldBg,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    border: Border.all(color: AppColors.borderMuted),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _titleController.text.isEmpty
                              ? 'Enter song title'
                              : _titleController.text,
                          style: AppTextStyles.title3.copyWith(
                            color: _titleController.text.isEmpty
                                ? AppColors.textMuted
                                : AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),

        const SizedBox(height: Spacing.space16),

        // Artist - tap to edit
        Text(
          'Artist / Band',
          style: AppTextStyles.callout.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _isEditingArtist
            ? Container(
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBg,
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  border: Border.all(color: AppColors.accent, width: 1.5),
                ),
                child: TextField(
                  controller: _artistController,
                  focusNode: _artistFocus,
                  textCapitalization: TextCapitalization.words,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => setState(() => _isEditingArtist = false),
                ),
              )
            : GestureDetector(
                onTap: _startEditingArtist,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.scaffoldBg,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    border: Border.all(color: AppColors.borderMuted),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _artistController.text.isEmpty
                              ? 'Enter artist name'
                              : _artistController.text,
                          style: AppTextStyles.body.copyWith(
                            color: _artistController.text.isEmpty
                                ? AppColors.textMuted
                                : AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }

  /// Builds the metrics row with BPM, Duration, and Tuning in a single row
  Widget _buildMetricsRow() {
    final tuningOption = findTuningByIdOrName(_currentTuning);
    final tuningDisplayName =
        tuningOption?.name ?? tuningShortLabel(_currentTuning);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // BPM field
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BPM',
                style: AppTextStyles.callout.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBg,
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  border: Border.all(color: AppColors.borderMuted),
                ),
                child: TextField(
                  controller: _bpmController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '—',
                    hintStyle: AppTextStyles.body.copyWith(
                      color: AppColors.textMuted,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // Duration field - uses masked input (currency-style MM:SS)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Duration',
                style: AppTextStyles.callout.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              MaskedDurationInput(
                initialSeconds: _currentDurationSeconds,
                onChanged: _onDurationChanged,
                backgroundColor: AppColors.scaffoldBg,
                borderColor: AppColors.borderMuted,
                textStyle: AppTextStyles.body.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // Tuning dropdown
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tuning',
                style: AppTextStyles.callout.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _selectTuning,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.scaffoldBg,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    border: Border.all(color: AppColors.borderMuted),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tuningDisplayName,
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notes',
          style: AppTextStyles.callout.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 180),
          decoration: BoxDecoration(
            color: AppColors.scaffoldBg,
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(color: AppColors.borderMuted),
          ),
          child: TextField(
            controller: _notesController,
            maxLines: null,
            minLines: 8,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Add notes for this song...',
              hintStyle: AppTextStyles.body.copyWith(
                color: AppColors.textMuted,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: _handleCancel,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _hasChanges ? _handleSave : null,
            style: FilledButton.styleFrom(
              backgroundColor: _hasChanges
                  ? AppColors.accent
                  : AppColors.surfaceDark,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
            ),
            child: Text(
              'Save',
              style: AppTextStyles.body.copyWith(
                color: _hasChanges ? Colors.white : AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
