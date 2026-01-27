import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../bands/active_band_controller.dart';
import 'models/setlist_song.dart';
import 'services/setlist_print_handler.dart';
import 'services/tuning_sort_service.dart';
import 'setlist_detail_controller.dart';
import 'setlist_repository.dart';
import 'setlists_screen.dart' show setlistsProvider;
import 'tuning/tuning_helpers.dart';
import 'widgets/back_only_app_bar.dart';
import 'widgets/bulk_add_songs_overlay.dart';
import 'widgets/reorderable_song_card.dart';
import 'widgets/selection_circle.dart';
import 'widgets/setlist_picker_bottom_sheet.dart';
import 'widgets/song_details_bottom_sheet.dart';
import 'widgets/song_lookup_overlay.dart';

// ============================================================================
// SETLIST DETAIL SCREEN
// Figma: "Setlist Detail" artboard
//
// FEATURES:
// - Real Supabase data via Riverpod provider
// - Delete song with confirmation dialog (Catalog-aware)
// - Drag reorder with ReorderableListView
// - Micro-interactions on drag
// - Per-setlist tuning sort (non-Catalog only)
//
// BAND ISOLATION: Enforced via setlist_detail_controller + repository
// ============================================================================

class SetlistDetailScreen extends ConsumerStatefulWidget {
  final String setlistId;
  final String setlistName;

  const SetlistDetailScreen({
    super.key,
    required this.setlistId,
    required this.setlistName,
  });

  @override
  ConsumerState<SetlistDetailScreen> createState() =>
      _SetlistDetailScreenState();
}

class _SetlistDetailScreenState extends ConsumerState<SetlistDetailScreen>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  // Animation for sort reorder feedback
  late AnimationController _sortAnimController;
  late Animation<double> _sortFadeAnimation;

  // Search state
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  // Track current tuning sort mode to detect changes
  TuningSortMode? _lastTuningSortMode;

  // Track current name (can be renamed)
  late String _currentName;

  // Debounce timer for reorder persistence
  Timer? _reorderDebounceTimer;

  // ============================================================
  // SELECT MODE STATE (Catalog only)
  // Allows multi-select of songs to add to another setlist.
  // ============================================================
  bool _isSelectMode = false;
  final Set<String> _selectedSongIds = {};

  @override
  void initState() {
    super.initState();
    _currentName = widget.setlistName;
    _setupAnimations();
    _setupSortAnimation();

    // Set the selected setlist for the provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(selectedSetlistProvider.notifier)
          .select(id: widget.setlistId, name: widget.setlistName);
    });

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _entranceController.forward();
    });
  }

  void _setupSortAnimation() {
    _sortAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Fade from 1.0 → 0.7 → 1.0 (subtle pulse effect)
    _sortFadeAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.7), weight: 40),
          TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.0), weight: 60),
        ]).animate(
          CurvedAnimation(parent: _sortAnimController, curve: Curves.easeInOut),
        );
  }

  void _setupAnimations() {
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _headerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _headerSlide = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.0, 0.5, curve: Curves.easeOutQuart),
          ),
        );
  }

  @override
  void dispose() {
    _reorderDebounceTimer?.cancel();
    _entranceController.dispose();
    _sortAnimController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    // Clear any snackbars when leaving this screen
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    super.deactivate();
  }

  /// Show rename dialog for setlist
  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: _currentName);
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Rename Setlist',
          style: AppTextStyles.title3.copyWith(color: AppColors.textPrimary),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter setlist name',
              hintStyle: AppTextStyles.body.copyWith(
                color: AppColors.textMuted,
              ),
              filled: true,
              fillColor: AppColors.scaffoldBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Name cannot be empty';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(color: AppColors.textMuted),
            ),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName != _currentName && mounted) {
      final notifier = ref.read(setlistDetailProvider.notifier);
      final success = await notifier.renameSetlist(newName);

      if (success && mounted) {
        // Update local state first
        final previousName = _currentName;
        setState(() {
          _currentName = newName;
        });
        debugPrint(
          '[SetlistDetail] Name updated from "$previousName" to "$_currentName"',
        );

        // Update the selected setlist provider too
        ref
            .read(selectedSetlistProvider.notifier)
            .select(id: widget.setlistId, name: newName);

        // Also refresh the setlists list to update the card
        ref.read(setlistsProvider.notifier).refresh();

        showAppSnackBar(context, message: 'Setlist renamed to "$newName"');
      }
    }
  }

  /// Show delete confirmation dialog
  Future<bool> _showDeleteDialog(String songTitle, bool isCatalog) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _DeleteSongDialog(songTitle: songTitle, isCatalog: isCatalog),
    );
    return result ?? false;
  }

  /// Handle song deletion
  Future<void> _handleDelete(String songId, String songTitle) async {
    final state = ref.read(setlistDetailProvider);

    final confirmed = await _showDeleteDialog(songTitle, state.isCatalog);
    if (!confirmed) return;

    final notifier = ref.read(setlistDetailProvider.notifier);

    final success = await notifier.deleteSong(songId);

    if (mounted) {
      if (success) {
        showAppSnackBar(
          context,
          message: state.isCatalog
              ? 'Song removed from Catalog and all setlists'
              : 'Song removed from setlist',
        );
      }
    }
  }

  /// Handle reorder with debouncing.
  ///
  /// Uses a debounce timer to batch rapid reorders. The persist only happens
  /// after 500ms of no additional reorders.
  void _handleReorder(int oldIndex, int newIndex) {
    final notifier = ref.read(setlistDetailProvider.notifier);

    // Apply local change immediately (optimistic UI)
    notifier.reorderLocal(oldIndex, newIndex);

    // Cancel any pending persist
    _reorderDebounceTimer?.cancel();

    // Schedule persist after debounce period
    _reorderDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;

      final success = await notifier.persistReorder();

      // If failed, the controller already reverted the UI and set an error.
      // The error will be shown via the listener in build.
      if (!success && mounted) {
        // Give haptic feedback on failure
        // (Error message is handled by state.error in the UI)
      }
    });
  }

  /// Handle Song Lookup tap
  void _handleSongLookup() {
    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) return;

    showSongLookupOverlay(
      context: context,
      bandId: bandId,
      setlistId: widget.setlistId,
      onSongAdded: (songId, title, artist) async {
        return ref
            .read(setlistDetailProvider.notifier)
            .addSong(songId, title, artist);
      },
    );
  }

  /// Handle Bulk Paste tap
  void _handleBulkPaste() {
    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) return;

    showBulkAddSongsOverlay(
      context: context,
      bandId: bandId,
      setlistId: widget.setlistId,
      onComplete: (addedCount, setlistSongIds) {
        // Refresh the song list
        ref.read(setlistDetailProvider.notifier).loadSongs();

        // Refresh setlists list to update song count and duration stats
        ref.read(setlistsProvider.notifier).refresh();

        // Show success snackbar with undo option
        if (mounted && addedCount > 0) {
          showAppSnackBar(
            context,
            message: '$addedCount song${addedCount == 1 ? '' : 's'} added',
            duration: const Duration(seconds: 4),
            action: setlistSongIds.isNotEmpty
                ? SnackBarAction(
                    label: 'UNDO',
                    textColor: AppColors.accent,
                    onPressed: () => _handleUndoBulkAdd(setlistSongIds),
                  )
                : null,
          );
        }
      },
    );
  }

  /// Undo bulk add by removing songs from the setlist
  Future<void> _handleUndoBulkAdd(List<String> setlistSongIds) async {
    if (setlistSongIds.isEmpty) return;

    final repository = ref.read(setlistRepositoryProvider);
    final removedCount = await repository.undoBulkAdd(
      setlistSongIds: setlistSongIds,
    );

    // Refresh the song list
    ref.read(setlistDetailProvider.notifier).loadSongs();

    // Refresh setlists list to update song count and duration stats
    ref.read(setlistsProvider.notifier).refresh();

    if (mounted && removedCount > 0) {
      showAppSnackBar(
        context,
        message: 'Removed $removedCount song${removedCount == 1 ? '' : 's'}',
      );
    }
  }

  /// Enter search mode
  void _startSearch() {
    setState(() {
      _isSearching = true;
      _searchQuery = '';
      _searchController.clear();
    });
    // Focus the search field after the widget rebuilds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  /// Exit search mode
  void _cancelSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
    _searchFocusNode.unfocus();
  }

  // ============================================================
  // SELECT MODE METHODS (Catalog only)
  // Entry/exit for multi-select to add songs to another setlist.
  // ============================================================

  /// Enter Select Mode
  void _enterSelectMode() {
    setState(() {
      _isSelectMode = true;
      _selectedSongIds.clear();
    });
  }

  /// Exit Select Mode and clear selections
  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _selectedSongIds.clear();
    });
  }

  /// Select all songs in the catalog
  void _selectAllSongs() {
    final state = ref.read(setlistDetailProvider);
    setState(() {
      _selectedSongIds.clear();
      _selectedSongIds.addAll(state.songs.map((s) => s.id));
    });
  }

  /// Unselect all songs
  void _unselectAllSongs() {
    setState(() {
      _selectedSongIds.clear();
    });
  }

  /// Check if all songs are currently selected
  bool get _allSongsSelected {
    final state = ref.read(setlistDetailProvider);
    return state.songs.isNotEmpty &&
        _selectedSongIds.length == state.songs.length;
  }

  /// Toggle selection state for a song
  void _toggleSongSelection(String songId) {
    setState(() {
      if (_selectedSongIds.contains(songId)) {
        _selectedSongIds.remove(songId);
      } else {
        _selectedSongIds.add(songId);
      }
    });
  }

  /// Handle "Add To Setlist" button tap
  Future<void> _handleAddToSetlist() async {
    if (_selectedSongIds.isEmpty) return;

    final result = await showSetlistPickerBottomSheet(
      context,
      selectedSongCount: _selectedSongIds.length,
    );

    if (result == null) return;

    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) return;

    final repository = ref.read(setlistRepositoryProvider);

    String targetSetlistId;
    String targetSetlistName;

    // Create new setlist if requested
    if (result.createNew && result.newSetlistName != null) {
      try {
        final newSetlist = await repository.createSetlist(
          bandId: bandId,
          name: result.newSetlistName!,
        );
        targetSetlistId = newSetlist.id;
        targetSetlistName = newSetlist.name;
      } catch (e) {
        if (mounted) {
          showErrorSnackBar(context, message: 'Failed to create setlist');
        }
        return;
      }
    } else {
      targetSetlistId = result.setlistId!;
      targetSetlistName = result.setlistName!;
    }

    // Add all selected songs to the target setlist
    int addedCount = 0;
    int skippedCount = 0;

    for (final songId in _selectedSongIds) {
      try {
        final song = ref
            .read(setlistDetailProvider)
            .songs
            .firstWhere((s) => s.id == songId);
        final addResult = await repository.addSongToSetlistEnsureCatalog(
          bandId: bandId,
          setlistId: targetSetlistId,
          songId: songId,
          songTitle: song.title,
          songArtist: song.artist,
        );
        if (addResult.wasAlreadyInSetlist) {
          skippedCount++;
        } else if (addResult.success) {
          addedCount++;
        }
      } catch (e) {
        debugPrint('[SelectMode] Error adding song $songId: $e');
      }
    }

    // Refresh setlists to update counts
    ref.read(setlistsProvider.notifier).refresh();

    // Exit select mode
    _exitSelectMode();

    // Show result snackbar
    if (mounted) {
      if (addedCount > 0) {
        final songWord = addedCount == 1 ? 'song' : 'songs';
        showAppSnackBar(
          context,
          message: '🎸 Added $addedCount $songWord to "$targetSetlistName"',
        );
      } else if (skippedCount > 0) {
        showAppSnackBar(
          context,
          message: 'Songs already in "$targetSetlistName"',
        );
      }
    }
  }

  /// Update search query
  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  /// Filter songs based on search query
  List<SetlistSong> _filterSongs(List<SetlistSong> songs) {
    if (_searchQuery.isEmpty) return songs;
    return songs.where((song) {
      final titleMatch = song.title.toLowerCase().contains(_searchQuery);
      final artistMatch = song.artist.toLowerCase().contains(_searchQuery);
      return titleMatch || artistMatch;
    }).toList();
  }

  /// Handle tapping a song card - show details bottom sheet
  Future<void> _handleSongTap(SetlistSong song) async {
    final result = await showSongDetailsBottomSheet(context, song: song);

    if (result != null && result.hasChanges) {
      debugPrint('[SetlistDetail] Song edit result:');
      debugPrint(
        '  titleChanged: ${result.titleChanged}, title: ${result.title}',
      );
      debugPrint(
        '  artistChanged: ${result.artistChanged}, artist: ${result.artist}',
      );
      debugPrint('  bpmChanged: ${result.bpmChanged}, bpm: ${result.bpm}');
      debugPrint(
        '  durationChanged: ${result.durationChanged}, duration: ${result.duration}',
      );
      debugPrint(
        '  notesChanged: ${result.notesChanged}, notes: ${result.notes}',
      );
      debugPrint(
        '  tuningChanged: ${result.tuningChanged}, tuning: ${result.tuning}',
      );

      final notifier = ref.read(setlistDetailProvider.notifier);

      // Update title/artist if changed
      if (result.titleChanged || result.artistChanged) {
        debugPrint('[SetlistDetail] Saving title/artist...');
        final success = await notifier.updateSongTitleArtist(
          song.id,
          title: result.titleChanged ? result.title : null,
          artist: result.artistChanged ? result.artist : null,
        );
        debugPrint('[SetlistDetail] Title/artist save result: $success');
      }

      // Update BPM if changed (including clearing to null)
      if (result.bpmChanged) {
        debugPrint('[SetlistDetail] Saving BPM...');
        bool success;
        if (result.bpm != null) {
          success = await notifier.updateSongBpm(song.id, result.bpm!);
        } else {
          // User cleared the BPM field
          success = await notifier.clearSongBpm(song.id);
        }
        debugPrint('[SetlistDetail] BPM save result: $success');
      }

      // Update duration if changed
      if (result.durationChanged && result.duration != null) {
        debugPrint('[SetlistDetail] Saving duration...');
        final success = await notifier.updateSongDuration(
          song.id,
          result.duration!,
        );
        debugPrint('[SetlistDetail] Duration save result: $success');
      }

      // Update notes if changed
      if (result.notesChanged) {
        debugPrint('[SetlistDetail] Saving notes...');
        final success = await notifier.updateSongNotes(song.id, result.notes);
        debugPrint('[SetlistDetail] Notes save result: $success');
      }

      // Update tuning if changed
      if (result.tuningChanged && result.tuning != null) {
        debugPrint('[SetlistDetail] Saving tuning...');
        final success = await notifier.updateSongTuning(
          song.id,
          result.tuning!,
        );
        debugPrint('[SetlistDetail] Tuning save result: $success');
      }
    }
  }

  /// Handle Share tap - generates plain text and opens native share sheet
  ///
  /// Output format:
  /// ```
  /// Setlist Name
  /// 49 songs • 1h 39m
  ///
  /// Song Title
  /// Artist Name                       125 BPM • Standard
  ///
  /// Another Song
  /// Another Artist                    - BPM • Drop D
  /// ```
  Future<void> _handleShare() async {
    final state = ref.read(setlistDetailProvider);
    final text = _generateShareText(
      setlistName: _currentName,
      songs: state.songs,
    );

    try {
      // On iOS/macOS, Share.share() needs sharePositionOrigin for the popover
      // We use the center of the screen as a fallback since we don't have the button position
      final box = context.findRenderObject() as RenderBox?;
      final position = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.fromLTWH(0, 0, MediaQuery.of(context).size.width, 56);

      await Share.share(text, sharePositionOrigin: position);
    } catch (e) {
      debugPrint('[SetlistDetail] Error sharing: $e');
      if (mounted) {
        showErrorSnackBar(context, message: 'Failed to share setlist');
      }
    }
  }

  /// Handle print setlist action.
  /// Uses stage-optimized formatting: large bold text, BPM only, tuning dividers.
  /// Works on all platforms (Web uses HTML, native uses PDF).
  void _handlePrint() {
    final state = ref.read(setlistDetailProvider);
    SetlistPrintHandler.print(setlistName: _currentName, songs: state.songs);
  }

  /// Handle delete setlist with confirmation dialog
  Future<void> _handleDeleteSetlist() async {
    final state = ref.read(setlistDetailProvider);
    if (state.isCatalog) return; // Safety check

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text(
          'Delete "${state.setlistName}"?',
          style: AppTextStyles.title3.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'This will remove the setlist. Songs will remain in your Catalog.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: AppTextStyles.body.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref
          .read(setlistDetailProvider.notifier)
          .deleteSetlist();
      if (success && mounted) {
        Navigator.of(context).pop(); // Return to setlists screen
      }
    }
  }

  /// Generate plain-text share content for the setlist
  String _generateShareText({
    required String setlistName,
    required List<SetlistSong> songs,
  }) {
    final buffer = StringBuffer();

    // Header block
    buffer.writeln(setlistName);
    buffer.writeln(_formatHeaderSubline(songs));
    buffer.writeln();

    // Song list block
    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];
      buffer.writeln(song.title);
      buffer.writeln(_formatSongSecondLine(song));
      if (i < songs.length - 1) {
        buffer.writeln(); // Blank line between songs
      }
    }

    return buffer.toString();
  }

  /// Format: "49 songs • 1h 39m"
  String _formatHeaderSubline(List<SetlistSong> songs) {
    final count = songs.length;
    final countText = '$count song${count == 1 ? '' : 's'}';

    // Sum duration_seconds, ignoring nulls (treated as 0)
    final totalSeconds = songs.fold<int>(
      0,
      (sum, s) => sum + s.durationSeconds,
    );

    final durationText = _formatTotalDuration(totalSeconds);
    return '$countText • $durationText';
  }

  /// Format total duration:
  /// - < 60 min: "Xm" or "Xm Ys" (if non-zero seconds)
  /// - >= 60 min: "Hh Mm"
  String _formatTotalDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0m';

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours >= 1) {
      // 1h 39m style
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      // Just minutes if no seconds, or "Xm Ys" if seconds
      if (seconds > 0) {
        return '${minutes}m ${seconds}s';
      }
      return '${minutes}m';
    } else {
      // Less than a minute
      return '${seconds}s';
    }
  }

  /// Format the second line: "Artist{spaces}### BPM • Tuning"
  /// Right-justifies BPM/Tuning within a fixed width
  String _formatSongSecondLine(SetlistSong song) {
    final left = song.artist;
    final bpmText = song.bpm != null && song.bpm! > 0
        ? '${song.bpm} BPM'
        : '- BPM';
    final tuningText = tuningShortLabel(song.tuning);
    final right = '$bpmText • $tuningText';

    return _formatTwoColumnLine(left, right);
  }

  /// Format two columns with right-justified second column.
  /// If content exceeds width, puts right on its own line.
  String _formatTwoColumnLine(String left, String right, {int width = 56}) {
    final needed = left.length + right.length + 1; // +1 for min spacing

    if (needed >= width) {
      // Overflow: put right on next line (indented for readability)
      return '$left\n    $right';
    }

    // Pad spaces between left and right
    final padding = width - left.length - right.length;
    return '$left${' ' * padding}$right';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setlistDetailProvider);

    // Detect tuning sort mode changes and trigger animation
    if (_lastTuningSortMode != null &&
        _lastTuningSortMode != state.tuningSortMode &&
        !state.isCatalog) {
      // Sort mode changed - play the subtle reorder animation
      _sortAnimController.forward(from: 0);
    }
    _lastTuningSortMode = state.tuningSortMode;

    // Listen for errors
    ref.listen<SetlistDetailState>(setlistDetailProvider, (previous, next) {
      if (next.error != null && previous?.error != next.error) {
        showErrorSnackBar(context, message: next.error!);
        ref.read(setlistDetailProvider.notifier).clearError();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            Column(
              children: [
                _buildAppBar(state),
                Expanded(child: _buildBody(state)),
              ],
            ),

            // Sticky bottom actions (Select Mode only)
            if (_isSelectMode && state.isCatalog)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildSelectModeBottomActions(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(SetlistDetailState state) {
    return BackOnlyAppBar(
      onBack: () => Navigator.of(context).pop(),
      showLoading: state.isDeleting || state.isReordering,
    );
  }

  /// Build the action buttons row (default state)
  Widget _buildActionButtonsRow(SetlistDetailState state) {
    return SingleChildScrollView(
      key: const ValueKey('action-buttons'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Tuning sort toggle (Catalog only, text-only)
          if (state.isCatalog && state.songs.isNotEmpty) ...[
            _TuningSortToggle(
              mode: state.tuningSortMode,
              onTap: () => ref
                  .read(setlistDetailProvider.notifier)
                  .cycleTuningSortMode(),
            ),
            const SizedBox(width: 8),
          ],
          // Song Lookup button
          _ActionButton(
            icon: Icons.search_rounded,
            label: 'Song Lookup',
            onTap: _handleSongLookup,
          ),
          const SizedBox(width: 8),
          // Bulk Paste button
          _ActionButton(
            icon: Icons.list_rounded,
            label: 'Bulk Paste',
            onTap: _handleBulkPaste,
          ),
          const SizedBox(width: 8),
          // Search filter button (icon only)
          _ActionButton(icon: Icons.filter_list_rounded, onTap: _startSearch),
        ],
      ),
    );
  }

  /// Build the search bar (search state)
  Widget _buildSearchBar() {
    return Row(
      key: const ValueKey('search-bar'),
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              onChanged: _onSearchChanged,
              style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Filter songs...',
                hintStyle: AppTextStyles.body.copyWith(
                  color: AppColors.textMuted,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppColors.textMuted,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceDark,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: AppColors.accent, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: AppColors.accent, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: AppColors.accent, width: 1.5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _cancelSearch,
          child: Text(
            'Cancel',
            style: AppTextStyles.body.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(SetlistDetailState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(AppColors.accent),
        ),
      );
    }

    // Single source of truth: always render the full layout.
    // Empty setlists show header + action row + empty content area.
    return _buildContent(state);
  }

  Widget _buildContent(SetlistDetailState state) {
    return CustomScrollView(
      slivers: [
        // Header section (always shown)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.pagePadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Spacing.space20),

                // Header with animations
                SlideTransition(
                  position: _headerSlide,
                  child: FadeTransition(
                    opacity: _headerFade,
                    child: _buildHeaderSection(state),
                  ),
                ),

                const SizedBox(height: Spacing.space16),

                // Action buttons row OR Search bar
                // Layout: [Sort Toggle] [Song Lookup] [Bulk Paste] [Search] OR [Search Bar] [Cancel]
                SlideTransition(
                  position: _headerSlide,
                  child: FadeTransition(
                    opacity: _headerFade,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            axisAlignment: -1,
                            child: child,
                          ),
                        );
                      },
                      child: _isSearching
                          ? _buildSearchBar()
                          : _buildActionButtonsRow(state),
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.space24),
              ],
            ),
          ),
        ),

        // Songs area: either empty content or song list
        // Catalog uses regular SliverList (no reordering, sorted by artist)
        // Non-Catalog uses SliverReorderableList (draggable)
        ..._buildSongsList(state),

        // Delete button (non-Catalog only)
        if (!state.isCatalog)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.pagePadding,
                vertical: Spacing.space24,
              ),
              child: Center(
                child: TextButton(
                  onPressed: state.isDeleting ? null : _handleDeleteSetlist,
                  child: Text(
                    state.isDeleting ? 'Deleting...' : 'Delete Setlist',
                    style: AppTextStyles.body.copyWith(
                      color: state.isDeleting
                          ? AppColors.textMuted
                          : AppColors.error,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Bottom padding for nav bar (extra space to scroll past)
        SliverToBoxAdapter(
          child: SizedBox(
            height:
                Spacing.space48 +
                Spacing.bottomNavHeight +
                MediaQuery.of(context).padding.bottom +
                32, // Extra scroll clearance
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderSection(SetlistDetailState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Setlist name row: [Star/Name + Edit] ... [Share Icon]
        Row(
          children: [
            // Left side: Catalog star (if catalog) + Name + Edit icon
            Expanded(
              child: Row(
                children: [
                  if (state.isCatalog) ...[
                    const Icon(Icons.star, color: AppColors.accent, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      _currentName,
                      style: AppTextStyles.title3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!state.isCatalog) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _showRenameDialog,
                      child: const Icon(
                        Icons.edit_outlined,
                        color: AppColors.textMuted,
                        size: 16,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Right side: Select link (Catalog only) + Share icon
            // Select Mode toggle appears only for Catalog setlist
            if (state.isCatalog && state.songs.isNotEmpty) ...[
              // Toggle between Select all / Unselect all when in select mode
              GestureDetector(
                onTap: _isSelectMode
                    ? (_allSongsSelected ? _unselectAllSongs : _selectAllSongs)
                    : _enterSelectMode,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Text(
                    _isSelectMode
                        ? (_allSongsSelected ? 'Unselect all' : 'Select all')
                        : 'Select',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
            // Print icon - stage-optimized formatting for live performance
            // Available on all platforms (Web uses HTML, native uses PDF)
            IconButton(
              onPressed: _handlePrint,
              icon: const Icon(
                Icons.print_rounded,
                size: 20,
                color: AppColors.accent,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            // Share icon - opens share sheet with text share option
            IconButton(
              onPressed: _handleShare,
              icon: const Icon(
                Icons.ios_share_rounded,
                size: 20,
                color: AppColors.accent,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Metadata
        Text(
          '${state.formattedSongCount} • ${state.formattedDuration}',
          style: AppTextStyles.headline.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// Empty content area shown when setlist has no songs.
  /// Part of the unified layout - header + action row are shown above this.
  Widget _buildEmptyContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.pagePadding,
        vertical: Spacing.space48,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: AppColors.textMuted,
              size: 40,
            ),
          ),
          const SizedBox(height: Spacing.space24),
          Text(
            'Silence is Golden...',
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.space12),
          Text(
            "But this setlist is looking a bit too quiet.\nTime to add some bangers!",
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Build the songs list (filtered if searching)
  List<Widget> _buildSongsList(SetlistDetailState state) {
    // Apply search filter if active
    final displaySongs = _isSearching ? _filterSongs(state.songs) : state.songs;

    // Empty state (no songs at all)
    if (state.songs.isEmpty) {
      return [SliverToBoxAdapter(child: _buildEmptyContent())];
    }

    // No search results
    if (_isSearching && displaySongs.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.pagePadding,
              vertical: Spacing.space48,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  color: AppColors.textMuted,
                  size: 48,
                ),
                const SizedBox(height: Spacing.space16),
                Text(
                  'No songs found',
                  style: AppTextStyles.title3.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space8),
                Text(
                  'Try a different search term',
                  style: AppTextStyles.callout.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    // When searching, always use non-reorderable list
    // Catalog uses this path (with optional Select Mode)
    if (_isSearching || state.isCatalog) {
      return [
        AnimatedBuilder(
          animation: _sortAnimController,
          builder: (context, child) {
            return SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.pagePadding,
              ),
              sliver: SliverOpacity(
                opacity: _sortFadeAnimation.value,
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final song = displaySongs[index];
                    final isSelected = _selectedSongIds.contains(song.id);

                    // In Select Mode: show selectable card with circle
                    if (_isSelectMode && state.isCatalog) {
                      return Padding(
                        key: ValueKey('select-${song.id}'),
                        padding: const EdgeInsets.only(bottom: Spacing.space12),
                        child: _SelectableSongCard(
                          song: song,
                          isSelected: isSelected,
                          onToggle: () => _toggleSongSelection(song.id),
                        ),
                      );
                    }

                    // Normal mode: standard reorderable card
                    return Padding(
                      key: ValueKey(song.id),
                      padding: const EdgeInsets.only(bottom: Spacing.space12),
                      child: ReorderableSongCard(
                        song: song,
                        index: index,
                        isDraggable: false,
                        onEdit: () => _handleSongTap(song),
                        onDelete: () => _handleDelete(song.id, song.title),
                        onTuningChanged: (tuning) => ref
                            .read(setlistDetailProvider.notifier)
                            .updateSongTuning(song.id, tuning),
                      ),
                    );
                  }, childCount: displaySongs.length),
                ),
              ),
            );
          },
        ),
      ];
    }

    // Non-Catalog, not searching: reorderable list
    return [
      AnimatedBuilder(
        animation: _sortAnimController,
        builder: (context, child) {
          return SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.pagePadding,
            ),
            sliver: SliverOpacity(
              opacity: _sortFadeAnimation.value,
              sliver: SliverReorderableList(
                itemCount: displaySongs.length,
                onReorder: _handleReorder,
                itemBuilder: (context, index) {
                  final song = displaySongs[index];
                  return Padding(
                    key: ValueKey(song.id),
                    padding: const EdgeInsets.only(bottom: Spacing.space12),
                    child: ReorderableSongCard(
                      song: song,
                      index: index,
                      isDraggable: true,
                      onEdit: () => _handleSongTap(song),
                      onDelete: () => _handleDelete(song.id, song.title),
                      onTuningChanged: (tuning) => ref
                          .read(setlistDetailProvider.notifier)
                          .updateSongTuning(song.id, tuning),
                    ),
                  );
                },
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      final scale = Tween<double>(begin: 1.0, end: 1.02)
                          .evaluate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOut,
                            ),
                          );
                      return Transform.scale(
                        scale: scale,
                        child: Material(
                          color: Colors.transparent,
                          elevation: 8,
                          shadowColor: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(
                            Spacing.buttonRadius,
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: child,
                  );
                },
              ),
            ),
          );
        },
      ),
    ];
  }

  // ============================================================
  // SELECT MODE BOTTOM ACTIONS
  // Sticky bottom bar with Cancel and Add To Setlist buttons.
  // ============================================================

  Widget _buildSelectModeBottomActions() {
    final hasSelection = _selectedSongIds.isNotEmpty;
    final selectedCount = _selectedSongIds.length;
    final buttonLabel = selectedCount > 0
        ? 'Add $selectedCount to Setlist'
        : 'Add To Setlist';

    return Container(
      padding: EdgeInsets.only(
        left: Spacing.pagePadding,
        right: Spacing.pagePadding,
        top: Spacing.space16,
        bottom: MediaQuery.of(context).padding.bottom + Spacing.space16,
      ),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        border: Border(
          top: BorderSide(
            color: AppColors.textSecondary.withValues(alpha: 0.2),
          ),
        ),
        // Subtle shadow for separation
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Cancel button (text style)
          Expanded(
            child: TextButton(
              onPressed: _exitSelectMode,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'Cancel',
                style: AppTextStyles.button.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),

          const SizedBox(width: Spacing.space12),

          // Add To Setlist button (primary, disabled when no selection)
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: hasSelection ? _handleAddToSetlist : null,
              style: FilledButton.styleFrom(
                backgroundColor: hasSelection
                    ? AppColors.accent
                    : AppColors.accent.withValues(alpha: 0.4),
                disabledBackgroundColor: AppColors.accent.withValues(
                  alpha: 0.4,
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                ),
              ),
              child: Text(
                buttonLabel,
                style: AppTextStyles.button.copyWith(
                  color: hasSelection
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SELECTABLE SONG CARD
// Song card variant with selection circle instead of drag handle.
// ============================================================================
// SELECTABLE SONG CARD
// Song card variant with selection circle for Catalog Select Mode.
//
// RESPONSIVE LAYOUT:
// - Selection circle on far left (same position as drag handle)
// - Top row: Title/Artist (left-aligned)
// - Bottom row (metrics): BPM | Duration | Tuning
//   - Uses MainAxisAlignment.spaceBetween for equidistant spacing
//   - BPM left-aligns with song title
//   - Tuning right-aligns within card bounds
//   - Spacing adjusts evenly as screen width changes
//
// SELECT MODE ANIMATION:
// - Content shifts right smoothly to accommodate selection circle
// ============================================================================

class _SelectableSongCard extends StatefulWidget {
  final SetlistSong song;
  final bool isSelected;
  final VoidCallback onToggle;

  const _SelectableSongCard({
    required this.song,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  State<_SelectableSongCard> createState() => _SelectableSongCardState();
}

class _SelectableSongCardState extends State<_SelectableSongCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      duration: AppDurations.instant,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeInOut));
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) => _tapController.forward();
  void _handleTapUp(TapUpDetails details) => _tapController.reverse();
  void _handleTapCancel() => _tapController.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onToggle,
      child: AnimatedBuilder(
        animation: _tapController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(opacity: _opacityAnimation.value, child: child),
          );
        },
        child: Container(
          width: double.infinity,
          height: 121,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: AppColors.scaffoldBg,
            border: Border.all(
              // Highlight selected cards with accent border
              color: widget.isSelected
                  ? AppColors.accent
                  : StandardCardBorder.color,
              width: StandardCardBorder.width,
            ),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          child: Row(
            children: [
              // ================================================
              // SELECTION CIRCLE - far left, fixed width area
              // ================================================
              SizedBox(
                width: SongCardLayout.contentLeftPadding,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: SongCardLayout.dragHandleLeft,
                    ),
                    child: SelectionCircle(
                      isSelected: widget.isSelected,
                      onToggle: widget.onToggle,
                    ),
                  ),
                ),
              ),

              // ================================================
              // MAIN CONTENT - expands to fill remaining width
              // ================================================
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: SongCardLayout.cardHorizontalPadding,
                    top: SongCardLayout.cardVerticalPadding,
                    bottom: SongCardLayout.cardVerticalPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ============================================
                      // TOP SECTION: Title + Artist (left-aligned)
                      // ============================================
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text(
                              widget.song.title,
                              style: AppTextStyles.title3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.song.artist,
                              style: AppTextStyles.callout,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // ============================================
                      // METRICS ROW: Responsive flexbox layout
                      // Left: BPM | Right: Duration → Tuning
                      // ============================================
                      _buildMetricsRow(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Metrics row with equidistant spacing for Select Mode.
  ///
  /// LAYOUT STRUCTURE:
  /// [BPM] ←--equal space--→ [Duration] ←--equal space--→ [Tuning]
  ///
  /// Uses MainAxisAlignment.spaceBetween to distribute 3 elements evenly:
  /// - BPM anchors to left edge (aligns with song title above)
  /// - Tuning anchors to right edge
  /// - Duration is centered between them
  /// - As screen width changes, spacing adjusts proportionally
  Widget _buildMetricsRow() {
    final song = widget.song;
    final shortLabel = tuningShortLabel(song.tuning);
    final bgColor = tuningBadgeColor(song.tuning);
    final textColor = tuningBadgeTextColor(bgColor);

    return SizedBox(
      height: SongCardLayout.metricsRowHeight,
      child: Row(
        // ================================================
        // EQUIDISTANT SPACING: spaceBetween distributes
        // elements evenly from left edge to right edge
        // ================================================
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ================================================
          // 1. BPM - anchors to left (aligns with title)
          // Shows "- BPM" placeholder if no value set
          // ================================================
          Text(
            song.isBpmPlaceholder ? '- BPM' : song.formattedBpm,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF5F5F5),
              height: 1,
            ),
          ),

          // ================================================
          // 2. DURATION - centered, evenly spaced
          // ================================================
          Text(
            song.formattedDuration,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF5F5F5),
              height: 1,
            ),
          ),

          // ================================================
          // 3. TUNING - anchors to right edge
          // ================================================
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.space12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              shortLabel,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TUNING SORT TOGGLE
// Per-setlist sort mode toggle (non-Catalog only).
//
// Cycles through: Standard → Half-Step → Full-Step → Drop D → Standard
// Displays the current "first tuning" with a down-arrow icon.
// Sort mode is persisted via TuningSortService (SharedPreferences).
// ============================================================================

class _TuningSortToggle extends StatelessWidget {
  final TuningSortMode mode;
  final VoidCallback onTap;

  const _TuningSortToggle({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Get the color for the current tuning mode
    final badgeColor = tuningBadgeColor(mode.dbValue);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.space12,
          vertical: Spacing.space8,
        ),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          border: Border.all(
            color: badgeColor.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: 16, color: badgeColor),
            const SizedBox(width: 4),
            Text(
              mode.label,
              style: AppTextStyles.footnote.copyWith(
                color: badgeColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ACTION BUTTON
// Outlined action button with icon and optional label
// ============================================================================

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, this.label, this.onTap});

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppDurations.instant,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) => _controller.forward();
  void _handleTapUp(TapUpDetails details) => _controller.reverse();
  void _handleTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space16,
            vertical: Spacing.space8,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.accent, width: 2),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: AppColors.accent),
              if (widget.label != null) ...[
                const SizedBox(width: 8),
                Text(
                  widget.label!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// DELETE SONG DIALOG
// Roadie-ish copy with stronger warning for Catalog deletion
// ============================================================================

class _DeleteSongDialog extends StatelessWidget {
  final String songTitle;
  final bool isCatalog;

  const _DeleteSongDialog({required this.songTitle, required this.isCatalog});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
      ),
      title: Text(
        isCatalog ? '⚠️ Delete from Catalog?' : 'Remove from Setlist?',
        style: AppTextStyles.title3,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"$songTitle"',
            style: AppTextStyles.headline.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: Spacing.space16),
          Text(
            isCatalog
                ? 'Hold up, roadie! This will remove this song from your Catalog AND from ALL setlists in this band. No take-backs. The song will be gone for good.'
                : 'This will remove the song from this setlist only. It\'ll still be in your Catalog and other setlists.',
            style: AppTextStyles.callout,
          ),
          if (isCatalog) ...[
            const SizedBox(height: Spacing.space12),
            Container(
              padding: const EdgeInsets.all(Spacing.space12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_rounded,
                    color: AppColors.error,
                    size: 20,
                  ),
                  const SizedBox(width: Spacing.space8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone!',
                      style: AppTextStyles.footnote.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: AppTextStyles.button.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            backgroundColor: isCatalog
                ? AppColors.error.withValues(alpha: 0.15)
                : AppColors.accent.withValues(alpha: 0.15),
          ),
          child: Text(
            isCatalog ? 'Delete Forever' : 'Remove',
            style: AppTextStyles.button.copyWith(
              color: isCatalog ? AppColors.error : AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}
