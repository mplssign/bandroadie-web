import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/segmented_button_group.dart';
import '../../lyrics/models/lyrics_data.dart';
import '../../lyrics/widgets/lyrics_editor_sheet.dart';
import '../models/setlist_song.dart';
import '../tuning/tuning_helpers.dart';
import '../setlist_repository.dart';
import '../setlist_detail_controller.dart';
import '../../songs/song_enrichment_service.dart';
import '../../songs/external_song_lookup_service.dart';
import '../../songs/services/song_enrichment_orchestrator.dart';
import '../../songs/widgets/enrichment_selector_bottom_sheet.dart';
import '../../songs/widgets/enrichment_results_overlay.dart';
import '../../bands/active_band_controller.dart';
import 'bpm_input_dialog.dart';
import 'duration_input_dialog.dart';
import 'key_picker_bottom_sheet.dart';
import 'tuning_picker_bottom_sheet.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import '../links/song_link.dart';
import '../links/song_link_detector.dart';

// ============================================================================
// SONG DETAILS BOTTOM SHEET
// Bottom sheet for viewing/editing song notes and tuning.
//
// Features:
// - Editable song title and artist (tap to edit)
// - Tuning selector (tap to change)
// - Musical key selector (tap to change, 24 standard keys)
// - Notes text field (button-triggered, in-drawer sub-view pattern)
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
  final List<SongLink>? youtubeLinks;
  final String? lyrics;
  final String? musicalKey;
  final bool hasChanges;

  // Flags to indicate which fields were changed (needed to distinguish
  // "no change" from "changed to null/empty")
  final bool titleChanged;
  final bool artistChanged;
  final bool notesChanged;
  final bool tuningChanged;
  final bool bpmChanged;
  final bool durationChanged;
  final bool youtubeLinksChanged;
  final bool lyricsChanged;
  final bool musicalKeyChanged;

  const SongDetailsResult({
    this.title,
    this.artist,
    this.notes,
    this.tuning,
    this.bpm,
    this.duration,
    this.youtubeLinks,
    this.lyrics,
    this.musicalKey,
    required this.hasChanges,
    this.titleChanged = false,
    this.artistChanged = false,
    this.notesChanged = false,
    this.tuningChanged = false,
    this.bpmChanged = false,
    this.durationChanged = false,
    this.youtubeLinksChanged = false,
    this.lyricsChanged = false,
    this.musicalKeyChanged = false,
  });
}

/// Show the song details bottom sheet.
///
/// Returns a [SongDetailsResult] with any changes, or null if cancelled.
/// When [isReadOnly] is true, all fields are non-editable (view-only mode).
Future<SongDetailsResult?> showSongDetailsBottomSheet(
  BuildContext context, {
  required SetlistSong song,
  bool isReadOnly = false,
}) async {
  HapticFeedback.lightImpact();

  return showModalBottomSheet<SongDetailsResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) => _SongDetailsSheet(song: song, isReadOnly: isReadOnly),
  );
}

class _SongDetailsSheet extends ConsumerStatefulWidget {
  final SetlistSong song;
  final bool isReadOnly;

  const _SongDetailsSheet({required this.song, this.isReadOnly = false});

  @override
  ConsumerState<_SongDetailsSheet> createState() => _SongDetailsSheetState();
}

class _SongDetailsSheetState extends ConsumerState<_SongDetailsSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _notesController;
  late String _currentTuning;

  // BPM is tracked as nullable int (dialog-based input)
  late int? _currentBpm;

  // Duration is tracked as seconds (used by MaskedDurationInput)
  late int _currentDurationSeconds;

  // YouTube links list
  late List<SongLink> _youtubeLinks;
  late List<SongLink> _originalYoutubeLinks;

  // Lyrics state
  late String? _currentLyrics;
  late String? _originalLyrics;

  // Musical key state
  late String? _currentMusicalKey;
  late String? _originalMusicalKey;

  bool _isEditingTitle = false;
  bool _isEditingArtist = false;
  bool _isEditingNotes = false;
  bool _hasChanges = false;

  final FocusNode _titleFocus = FocusNode();
  final FocusNode _artistFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(text: widget.song.title);
    _artistController = TextEditingController(text: widget.song.artist);
    _notesController = TextEditingController(text: widget.song.notes ?? '');
    _currentBpm = widget.song.bpm;
    _currentDurationSeconds = widget.song.durationSeconds;
    _currentTuning = widget.song.tuning ?? 'standard_e';

    // Initialize YouTube links from song data
    debugPrint(
      '[SongDetails] Raw youtubeLinks from song: ${widget.song.youtubeLinks}',
    );
    _originalYoutubeLinks = SongLink.listFromJson(widget.song.youtubeLinks);
    _youtubeLinks = List.from(_originalYoutubeLinks);

    // Initialize lyrics from song data
    _originalLyrics = widget.song.lyrics;
    _currentLyrics = widget.song.lyrics;

    // Initialize musical key from song data
    _originalMusicalKey = widget.song.musicalKey;
    _currentMusicalKey = widget.song.musicalKey;

    _titleController.addListener(_checkForChanges);
    _artistController.addListener(_checkForChanges);
    _notesController.addListener(_checkForChanges);

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
    _titleController.dispose();
    _artistController.dispose();
    _notesController.dispose();
    _titleFocus.dispose();
    _artistFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _checkForChanges() {
    final newTitle = _titleController.text.trim();
    final newArtist = _artistController.text.trim();
    final newNotes = _notesController.text.trim();
    final originalTuning = widget.song.tuning ?? 'standard_e';

    final titleChanged = newTitle != widget.song.title;
    final artistChanged = newArtist != widget.song.artist;
    final notesChanged = newNotes != (widget.song.notes ?? '');
    final tuningChanged = _currentTuning != originalTuning;
    final bpmChanged = _currentBpm != widget.song.bpm;
    final durationChanged =
        _currentDurationSeconds != widget.song.durationSeconds;
    final youtubeLinksChanged = !_areYoutubeLinksEqual(
      _youtubeLinks,
      _originalYoutubeLinks,
    );
    final lyricsChanged = _currentLyrics != _originalLyrics;
    final musicalKeyChanged =
        (_currentMusicalKey ?? '') != (_originalMusicalKey ?? '');

    final anyChanged = titleChanged ||
        artistChanged ||
        notesChanged ||
        tuningChanged ||
        bpmChanged ||
        durationChanged ||
        youtubeLinksChanged ||
        lyricsChanged ||
        musicalKeyChanged;

    debugPrint(
      '[SongDetails] _checkForChanges: bpmChanged=$bpmChanged, anyChanged=$anyChanged',
    );

    setState(() {
      _hasChanges = anyChanged;
    });
  }

  /// Compare two lists of YouTube links for equality
  bool _areYoutubeLinksEqual(List<SongLink> a, List<SongLink> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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

    if (result != null) {
      // Compose the compound tuning string (e.g. "standard_e|capo:3")
      final newTuning = composeCapoTuning(result.tuningId, result.capoFret) ??
          result.tuningId;

      if (newTuning != _currentTuning) {
        HapticFeedback.selectionClick();
        setState(() {
          _currentTuning = newTuning;
          _hasChanges = true;
        });
      }
    }
  }

  Future<void> _selectBpm() async {
    final result = await showBpmInputDialog(
      context,
      initialBpm: _currentBpm,
    );
    if (result is DialogCleared<int>) {
      setState(() {
        _currentBpm = null;
      });
      _checkForChanges();
    } else if (result is DialogValue<int>) {
      setState(() {
        _currentBpm = result.value;
      });
      _checkForChanges();
    }
    // DialogCancelled → no change
  }

  Future<void> _selectDuration() async {
    final result = await showDurationInputDialog(
      context,
      initialSeconds: _currentDurationSeconds,
    );
    if (result is DialogCleared<int>) {
      setState(() {
        _currentDurationSeconds = 0;
      });
      _checkForChanges();
    } else if (result is DialogValue<int>) {
      setState(() {
        _currentDurationSeconds = result.value;
      });
      _checkForChanges();
    }
    // DialogCancelled → no change
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '—';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _selectKey() async {
    final result = await showKeyPickerBottomSheet(
      context,
      selectedKey: _currentMusicalKey,
    );
    // Handle three cases:
    // - result is null: user cancelled, do nothing
    // - result is empty string: user tapped selected key to unselect, clear to null
    // - result is a key string: user selected a different key, update
    if (result == '') {
      // Empty string means unselect (tap on already-selected key)
      HapticFeedback.selectionClick();
      setState(() {
        _currentMusicalKey = '';
      });
      _checkForChanges();
    } else if (result != null && result != _currentMusicalKey) {
      // New key selected
      HapticFeedback.selectionClick();
      setState(() {
        _currentMusicalKey = result;
      });
      _checkForChanges();
    }
    // If result is null (cancelled) or same as current, do nothing
  }

  void _handleSave() {
    // RBAC self-defense: block save in read-only mode
    if (widget.isReadOnly) return;
    HapticFeedback.lightImpact();
    debugPrint('[SongDetails] _handleSave called');

    final newTitle = _titleController.text.trim();
    final newArtist = _artistController.text.trim();
    final newNotes = _notesController.text.trim();
    final originalTuning = widget.song.tuning ?? 'standard_e';

    debugPrint('[SongDetails] Original song.bpm: ${widget.song.bpm}');
    debugPrint('[SongDetails] New BPM from state: $_currentBpm');

    // Determine which fields changed
    final titleChanged = newTitle != widget.song.title;
    final artistChanged = newArtist != widget.song.artist;
    final notesChanged = newNotes != (widget.song.notes ?? '');
    final tuningChanged = _currentTuning != originalTuning;
    final bpmChanged = _currentBpm != widget.song.bpm;
    final durationChanged =
        _currentDurationSeconds != widget.song.durationSeconds;
    final youtubeLinksChanged = !_areYoutubeLinksEqual(
      _youtubeLinks,
      _originalYoutubeLinks,
    );
    final lyricsChanged = _currentLyrics != _originalLyrics;
    final musicalKeyChanged = _currentMusicalKey != _originalMusicalKey;

    debugPrint(
      '[SongDetails] bpmChanged: $bpmChanged (newBpm=$_currentBpm, original=${widget.song.bpm})',
    );
    debugPrint('[SongDetails] _hasChanges state: $_hasChanges');

    final result = SongDetailsResult(
      title: titleChanged ? newTitle : null,
      artist: artistChanged ? newArtist : null,
      notes: notesChanged ? newNotes : null,
      tuning: tuningChanged ? _currentTuning : null,
      bpm: _currentBpm, // Always include so handler can check bpmChanged flag
      duration:
          _currentDurationSeconds, // Always include so handler can check durationChanged flag
      youtubeLinks: youtubeLinksChanged ? _youtubeLinks : null,
      lyrics: lyricsChanged ? _currentLyrics : null,
      musicalKey: musicalKeyChanged ? _currentMusicalKey : null,
      hasChanges: _hasChanges,
      titleChanged: titleChanged,
      artistChanged: artistChanged,
      notesChanged: notesChanged,
      tuningChanged: tuningChanged,
      bpmChanged: bpmChanged,
      durationChanged: durationChanged,
      youtubeLinksChanged: youtubeLinksChanged,
      lyricsChanged: lyricsChanged,
      musicalKeyChanged: musicalKeyChanged,
    );

    Navigator.of(context).pop(result);
  }

  void _handleCancel() {
    if (_hasChanges) {
      _showUnsavedChangesDialog();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Shows a confirmation dialog when there are unsaved changes.
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
              FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text(
                  'Keep Editing',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    'Discard',
                    style: AppTextStyles.body.copyWith(
                      color: context.colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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

  /// Handle enrichment action (Task 7: single-song entry point)
  Future<void> _handleEnrichSong() async {
    // Get active band ID
    final activeBandState = ref.read(activeBandProvider);
    final bandId = activeBandState.activeBandId;
    if (bandId == null) {
      debugPrint('[SongDetails] No active band - cannot enrich');
      return;
    }

    // Step 1: Show selector
    final selection = await showEnrichmentSelectorBottomSheet(
      context,
      songCount: 1,
    );
    if (selection == null || !mounted) return;

    // Step 2: Orchestrate enrichment
    final supabase = Supabase.instance.client;
    final repository = SetlistRepository();
    final enrichmentService = SongEnrichmentService(supabase);
    final lookupService = ExternalSongLookupService(supabase);

    final orchestrator = SongEnrichmentOrchestrator(
      repository: repository,
      enrichmentService: enrichmentService,
      lookupService: lookupService,
    );

    final result = await orchestrator.enrichSongs(
      songIds: [widget.song.id],
      bandId: bandId,
      enrichBpm: selection.bpmSelected,
      enrichDuration: selection.durationSelected,
      enrichKey: selection.keySelected,
    );

    if (!mounted) return;

    // Step 3: Broadcast updates for enriched fields to refresh catalog/list views.
    final broadcaster = ref.read(songUpdateBroadcasterProvider.notifier);
    for (final detail in result.details) {
      if (detail.bpmResult == EnrichmentFieldResult.updated ||
          detail.durationResult == EnrichmentFieldResult.updated ||
          detail.keyResult == EnrichmentFieldResult.updated) {
        broadcaster.broadcast(SongUpdateEvent(songId: detail.songId));
      }
    }

    // Step 4: Show results overlay
    await showEnrichmentResultsOverlay(
      context: context,
      result: result,
    );
  }

  /// Show modal to add a new YouTube link
  Future<void> _showAddLinkModal() async {
    final urlController = TextEditingController();
    final titleController = TextEditingController();

    final result = await showDialog<SongLink>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
        ),
        title: Text(
          'Add Link',
          style:
              AppTextStyles.title3.copyWith(color: context.colors.textPrimary),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: AppTextStyles.body
                  .copyWith(color: context.colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Link name (e.g., "Live Performance")',
                hintStyle: AppTextStyles.body.copyWith(
                  color: context.colors.textMuted,
                ),
                filled: true,
                fillColor: context.colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              style: AppTextStyles.body
                  .copyWith(color: context.colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Link URL',
                hintStyle: AppTextStyles.body.copyWith(
                  color: context.colors.textMuted,
                ),
                filled: true,
                fillColor: context.colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                final url = urlController.text.trim();
                if (title.isNotEmpty && url.isNotEmpty) {
                  final detectedType = detectLinkType(url);
                  Navigator.of(context).pop(
                      SongLink(title: title, url: url, type: detectedType));
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 48),
              ),
              child: Text(
                'Save',
                style: AppTextStyles.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cancel',
                  style: AppTextStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      HapticFeedback.lightImpact();
      setState(() {
        _youtubeLinks.add(result);
      });
      _checkForChanges();
    }
  }

  /// Remove a YouTube link at the given index
  void _removeYouTubeLink(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _youtubeLinks.removeAt(index);
    });
    _checkForChanges();
  }

  /// Open a YouTube link in the browser
  Future<void> _openYouTubeLink(String url) async {
    HapticFeedback.lightImpact();
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('[SongDetails] Failed to launch URL: $e');
      }
    }
  }

  /// Returns the icon for a given link type.
  IconData _getIconForLinkType(SongLinkType type) {
    switch (type) {
      case SongLinkType.youtube:
        return Icons.play_circle_outline;
      case SongLinkType.spotify:
        return AppIcons.spotify;
      case SongLinkType.appleMusic:
        return AppIcons.appleMusic;
      case SongLinkType.amazonMusic:
        return AppIcons.amazonMusic;
      case SongLinkType.soundcloud:
        return LucideIcons.music;
      case SongLinkType.googleDocs:
        return LucideIcons.fileText;
      case SongLinkType.pdf:
        return AppIcons.pdf;
      case SongLinkType.googleSheets:
        return LucideIcons.table;
      case SongLinkType.generic:
        return AppIcons.globe;
    }
  }

  /// Returns the color for a given link type.
  Color _getColorForLinkType(SongLinkType type) {
    switch (type) {
      case SongLinkType.youtube:
        return Colors.red; // YouTube red
      case SongLinkType.spotify:
        return const Color(0xFF1DB954); // Spotify green
      case SongLinkType.appleMusic:
        return const Color(0xFFFA243C); // Apple Music pink/red
      case SongLinkType.amazonMusic:
        return const Color(0xFF00A8E1); // Amazon Music blue
      case SongLinkType.soundcloud:
        return const Color(0xFFFF5500); // SoundCloud orange
      case SongLinkType.googleDocs:
        return Colors.blue; // Google Docs blue
      case SongLinkType.googleSheets:
        return Colors.green; // Google Sheets green
      case SongLinkType.pdf:
        return Colors.red; // PDF red
      case SongLinkType.generic:
        return context.colors.textSecondary; // Default text color
    }
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
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handleCancel();
        },
        child: Container(
          margin: EdgeInsets.only(bottom: bottomPadding),
          constraints: BoxConstraints(
            maxHeight: screenHeight * 0.85,
            minHeight: screenHeight * 0.6,
          ),
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
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Spacing.space16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _isEditingNotes
                        ? [_buildNotesSubView()]
                        : [
                            _buildSongInfo(),
                            const SizedBox(height: Spacing.space24),
                            _buildMetricsRow(),
                            const SizedBox(height: Spacing.space24),
                            _buildNotesSection(),
                            const SizedBox(height: Spacing.space24),
                          ],
                  ),
                ),
              ),
              _buildFixedBottomActions(),
            ],
          ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Song Details',
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
          const SizedBox(height: 4),
          Text(
            widget.isReadOnly
                ? 'View-only mode.'
                : 'Changes apply to this song everywhere.',
            style: AppTextStyles.callout.copyWith(
              color: context.colors.textMuted,
              fontSize: AppFontSizes.caption,
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
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _isEditingTitle && !widget.isReadOnly
            ? Container(
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  border: Border.all(color: AppColors.primary, width: 1.5),
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
                onTap: widget.isReadOnly ? null : _startEditingTitle,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.background,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    border: Border.all(color: context.colors.border),
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
                                ? context.colors.textMuted
                                : context.colors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!widget.isReadOnly)
                        Icon(
                          AppIcons.edit,
                          size: 18,
                          color: context.colors.textMuted,
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
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _isEditingArtist && !widget.isReadOnly
            ? Container(
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: TextField(
                  controller: _artistController,
                  focusNode: _artistFocus,
                  textCapitalization: TextCapitalization.words,
                  style: AppTextStyles.body.copyWith(
                    color: context.colors.textPrimary,
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
                onTap: widget.isReadOnly ? null : _startEditingArtist,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.background,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    border: Border.all(color: context.colors.border),
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
                                ? context.colors.textMuted
                                : context.colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!widget.isReadOnly)
                        Icon(
                          AppIcons.edit,
                          size: 18,
                          color: context.colors.textMuted,
                        ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }

  /// 4-column metrics row: BPM | Duration | Tuning | Key
  Widget _buildMetricsRow() {
    // Parse capo suffix so findTuningByIdOrName sees the base tuning
    final baseTuning =
        parseCapoTuning(_currentTuning).tuningId ?? _currentTuning;
    final tuningOption = findTuningByIdOrName(baseTuning);
    final tuningDisplayName =
        tuningOption?.name ?? tuningShortLabel(_currentTuning);

    return SegmentedButtonGroup(
      segments: [
        SegmentData(
          label: 'BPM',
          value: _currentBpm?.toString() ?? '—',
          onTap: widget.isReadOnly ? null : _selectBpm,
        ),
        SegmentData(
          label: 'Duration',
          value: _formatDuration(_currentDurationSeconds),
          onTap: widget.isReadOnly ? null : _selectDuration,
        ),
        SegmentData(
          label: 'Tuning',
          value: tuningDisplayName,
          onTap: widget.isReadOnly ? null : _selectTuning,
        ),
        SegmentData(
          label: 'Key',
          value: (_currentMusicalKey == null || _currentMusicalKey!.isEmpty)
              ? '—'
              : _currentMusicalKey!,
          onTap: widget.isReadOnly ? null : _selectKey,
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 3-button action row (hidden in read-only)
        if (!widget.isReadOnly) _buildAddButtonsRow(),
        if (!widget.isReadOnly) const SizedBox(height: 12),
        // YouTube link buttons (if links exist)
        _buildYouTubeLinksList(),
        // Notes preview (if notes exist and not editing)
        _buildNotesPreview(),
      ],
    );
  }

  /// 3 equal-width outlined rose buttons: Add Lyrics | Add YouTube | Add Notes
  Widget _buildAddButtonsRow() {
    final hasLyrics = _currentLyrics != null && _currentLyrics!.isNotEmpty;
    final hasNotes = _notesController.text.trim().isNotEmpty;

    return Row(
      children: [
        // + Add Lyrics
        Expanded(
          child: GestureDetector(
            onTap: _showLyricsEditor,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.music,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasLyrics ? 'Edit Lyrics' : 'Add Lyrics',
                    style: AppTextStyles.footnote.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),

        // + Add YouTube
        Expanded(
          child: GestureDetector(
            onTap: _showAddLinkModal,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.link,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add a link',
                    style: AppTextStyles.footnote.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),

        // + Add Notes
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isEditingNotes = true),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.noteFile,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasNotes ? 'Edit Notes' : 'Add Notes',
                    style: AppTextStyles.footnote.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Notes preview card shown when notes are non-empty and not in edit mode.
  Widget _buildNotesPreview() {
    final notes = _notesController.text.trim();
    if (notes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: widget.isReadOnly
            ? null
            : () => setState(() => _isEditingNotes = true),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(color: context.colors.border),
          ),
          child: Text(
            notes.length > 120 ? '${notes.substring(0, 120)}…' : notes,
            style: AppTextStyles.body.copyWith(
              color: context.colors.textSecondary,
              height: 1.4,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  /// Notes in-drawer sub-view: back nav row + text field.
  /// Shown when [_isEditingNotes] is true, replacing the main content area.
  Widget _buildNotesSubView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back navigation row
        GestureDetector(
          onTap: () => setState(() => _isEditingNotes = false),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                AppIcons.back,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Text(
                'Back',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Notes',
          style: AppTextStyles.callout.copyWith(
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 180),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(color: context.colors.border),
          ),
          child: TextField(
            controller: _notesController,
            readOnly: widget.isReadOnly,
            maxLines: null,
            minLines: 8,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: AppTextStyles.headline
                .copyWith(color: context.colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Add notes for this song...',
              hintStyle: AppTextStyles.headline.copyWith(
                color: context.colors.textMuted,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the lyrics preview (shown below the add buttons row when lyrics exist)
  /// Builds the YouTube link buttons list (shown below the add buttons row)
  Widget _buildYouTubeLinksList() {
    if (_youtubeLinks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(_youtubeLinks.length, (index) {
          final link = _youtubeLinks[index];
          return _buildSongLinkButton(link, index);
        }),
      ),
    );
  }

  /// Builds a single YouTube link button with tap-to-open and X to delete
  Widget _buildSongLinkButton(SongLink link, int index) {
    final displayTitle = link.title.length > 25
        ? '${link.title.substring(0, 25)}...'
        : link.title;

    return Container(
      padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6, right: 4),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tap to open link
          GestureDetector(
            onTap: () => _openYouTubeLink(link.url),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getIconForLinkType(link.type),
                  color: _getColorForLinkType(link.type),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  displayTitle,
                  style: AppTextStyles.body.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Delete button (hidden in read-only mode)
          if (!widget.isReadOnly)
            GestureDetector(
              onTap: () => _removeYouTubeLink(index),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(AppIcons.close,
                    color: context.colors.textMuted, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  /// Opens the lyrics editor bottom sheet
  Future<void> _showLyricsEditor() async {
    final currentData = _currentLyrics != null && _currentLyrics!.isNotEmpty
        ? LyricsData.fromJsonString(_currentLyrics)
        : null;

    final result = await showLyricsEditor(
      context,
      initialData: currentData,
    );

    if (result != null) {
      setState(() {
        if (result.isEmpty) {
          _currentLyrics = null;
        } else {
          _currentLyrics = result.toJsonString();
        }
        _checkForChanges();
      });
    }
  }

  /// Fixed bottom action area: full-width Save + centered Cancel below
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
          // Full-width Save button (hidden in read-only mode)
          if (!widget.isReadOnly)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _hasChanges ? _handleSave : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _hasChanges
                      ? AppColors.primary
                      : context.colors.border.withValues(alpha: 0.3),
                  disabledBackgroundColor:
                      context.colors.border.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  ),
                ),
                child: Text(
                  'Save',
                  style: AppTextStyles.body.copyWith(
                    color:
                        _hasChanges ? Colors.white : context.colors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: AppFontSizes.body,
                  ),
                ),
              ),
            ),
          if (!widget.isReadOnly) const SizedBox(height: 8),
          // Enrich Data button
          if (!widget.isReadOnly)
            TextButton.icon(
              onPressed: _handleEnrichSong,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              ),
              icon: Icon(
                Icons.auto_awesome,
                size: 16,
                color: context.colors.primary,
              ),
              label: Text(
                'Enrich Song Data',
                style: AppTextStyles.body.copyWith(
                  color: context.colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (!widget.isReadOnly) const SizedBox(height: 4),
          // Centered Cancel/Close text button
          TextButton(
            onPressed: widget.isReadOnly
                ? () => Navigator.of(context).pop()
                : _handleCancel,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
            ),
            child: Text(
              widget.isReadOnly ? 'Close' : 'Cancel',
              style: AppTextStyles.body.copyWith(
                color: context.colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
