import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../components/ui/brand_action_button.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../bands/active_band_controller.dart';
import 'models/setlist_song.dart';
import 'setlist_detail_controller.dart';
import 'setlist_repository.dart';
import 'setlists_screen.dart' show setlistsProvider;
import 'tuning/tuning_helpers.dart';
import 'widgets/action_buttons_row.dart';
import 'widgets/back_only_app_bar.dart';
import 'widgets/bulk_add_songs_overlay.dart';
import 'widgets/reorderable_song_card.dart';
import 'widgets/song_lookup_overlay.dart';

// ============================================================================
// NEW SETLIST SCREEN
// Creates a new setlist and displays it in an editable state.
// Matches the layout and behavior of SetlistDetailScreen.
//
// FLOW:
// 1. On init, create a new setlist with name "New Setlist" in the database
// 2. Display in edit mode with inline name editing
// 3. User can add songs, rename, etc. - all changes persist immediately
//
// BAND ISOLATION: Uses activeBandId for all operations.
// ============================================================================

class NewSetlistScreen extends ConsumerStatefulWidget {
  const NewSetlistScreen({super.key});

  @override
  ConsumerState<NewSetlistScreen> createState() => _NewSetlistScreenState();
}

class _NewSetlistScreenState extends ConsumerState<NewSetlistScreen>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _entranceController;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  // Setlist state
  String? _setlistId;
  String _setlistName = 'New Setlist';
  bool _isCreating = true;
  String? _createError;

  // Name editing state
  bool _isEditingName = false;
  late TextEditingController _nameController;
  late FocusNode _nameFocusNode;
  bool _isSavingName = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _nameController = TextEditingController(text: _setlistName);
    _nameFocusNode = FocusNode();

    // Create the setlist immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _createSetlist();
    });
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
    _entranceController.dispose();
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  /// Create the setlist in the database
  Future<void> _createSetlist() async {
    final bandId = ref.read(activeBandIdProvider);
    final userId = supabase.auth.currentUser?.id;

    debugPrint(
      '[Setlists] createSetlist tapped: bandId=$bandId, userId=$userId',
    );

    if (bandId == null || bandId.isEmpty) {
      debugPrint('[Setlists] createSetlist aborted: no band selected');
      setState(() {
        _isCreating = false;
        _createError = 'No band selected. Please select a band first.';
      });
      return;
    }

    try {
      final repository = ref.read(setlistRepositoryProvider);
      final result = await repository.createSetlist(
        bandId: bandId,
        name: _setlistName,
      );

      debugPrint(
        '[Setlists] createSetlist success: id=${result.id}, name=${result.name}',
      );

      setState(() {
        _setlistId = result.id;
        _setlistName = result.name;
        _nameController.text = result.name;
        _isCreating = false;
      });

      // Set up the provider for this setlist
      ref
          .read(selectedSetlistProvider.notifier)
          .select(id: result.id, name: result.name);

      // Refresh the setlists list
      ref.read(setlistsProvider.notifier).refresh();

      // Start entrance animation
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _entranceController.forward();
      });
    } on SetlistQueryError catch (e) {
      debugPrint(
        '[Setlists] createSetlist failed (SetlistQueryError): code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}',
      );
      setState(() {
        _isCreating = false;
        _createError = e.userMessage;
      });
    } catch (e) {
      debugPrint('[Setlists] createSetlist failed (unexpected): $e');
      setState(() {
        _isCreating = false;
        _createError = 'Failed to create setlist. Please try again.';
      });
    }
  }

  /// Start editing the setlist name
  void _startEditingName() {
    setState(() {
      _isEditingName = true;
      _nameController.text = _setlistName;
    });
    // Focus after next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
      // Select all text
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    });
  }

  /// Save the setlist name
  Future<void> _saveSetlistName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      // Revert to original name
      _nameController.text = _setlistName;
      setState(() => _isEditingName = false);
      return;
    }

    if (newName == _setlistName) {
      // No change
      setState(() => _isEditingName = false);
      return;
    }

    setState(() => _isSavingName = true);

    try {
      final repository = ref.read(setlistRepositoryProvider);
      final bandId = ref.read(activeBandIdProvider);
      if (bandId == null || _setlistId == null) {
        throw Exception('Missing band or setlist ID');
      }

      await repository.renameSetlist(
        bandId: bandId,
        setlistId: _setlistId!,
        newName: newName,
      );

      setState(() {
        _setlistName = newName;
        _isEditingName = false;
        _isSavingName = false;
      });

      // Update the provider
      ref
          .read(selectedSetlistProvider.notifier)
          .select(id: _setlistId!, name: newName);

      // Refresh the setlists list
      ref.read(setlistsProvider.notifier).refresh();
    } catch (e) {
      setState(() {
        _isSavingName = false;
      });
      if (mounted) {
        showErrorSnackBar(context, message: 'Failed to rename setlist: $e');
      }
    }
  }

  /// Handle Song Lookup tap
  void _handleSongLookup() {
    if (_setlistId == null) return;
    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) return;

    showSongLookupOverlay(
      context: context,
      bandId: bandId,
      setlistId: _setlistId!,
      onSongAdded: (songId, title, artist) async {
        return ref
            .read(setlistDetailProvider.notifier)
            .addSong(songId, title, artist);
      },
    );
  }

  /// Handle Bulk Paste tap
  void _handleBulkPaste() {
    if (_setlistId == null) return;
    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) return;

    showBulkAddSongsOverlay(
      context: context,
      bandId: bandId,
      setlistId: _setlistId!,
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

  /// Handle Share tap
  /// iOS requires sharePositionOrigin to position the share sheet
  void _handleShare(BuildContext context) async {
    final state = ref.read(setlistDetailProvider);
    final text = _generateShareText(
      setlistName: _setlistName,
      songs: state.songs,
    );

    try {
      // On iOS/macOS, Share.share() needs sharePositionOrigin for the popover
      // We use the center of the screen as a fallback since we don't have the button position
      final box = context.findRenderObject() as RenderBox?;
      final position = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.fromLTWH(0, 0, MediaQuery.of(context).size.width, 56);

      await Share.share(
        text,
        sharePositionOrigin: position,
      );
    } catch (e) {
      debugPrint('[SetlistShare] Error sharing: $e');
      if (mounted) {
        showErrorSnackBar(
          context,
          message: 'Failed to share setlist',
        );
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
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  String _formatHeaderSubline(List<SetlistSong> songs) {
    final count = songs.length;
    final countText = '$count song${count == 1 ? '' : 's'}';

    final totalSeconds = songs.fold<int>(
      0,
      (sum, s) => sum + s.durationSeconds,
    );

    final durationText = _formatTotalDuration(totalSeconds);
    return '$countText • $durationText';
  }

  String _formatTotalDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0m';

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours >= 1) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      if (seconds > 0) {
        return '${minutes}m ${seconds}s';
      }
      return '${minutes}m';
    } else {
      return '${seconds}s';
    }
  }

  String _formatSongSecondLine(SetlistSong song) {
    final left = song.artist;
    final bpmText = song.bpm != null && song.bpm! > 0
        ? '${song.bpm} BPM'
        : '- BPM';
    final tuningText = tuningShortLabel(song.tuning);
    final right = '$bpmText • $tuningText';

    return _formatTwoColumnLine(left, right);
  }

  String _formatTwoColumnLine(String left, String right, {int width = 56}) {
    final needed = left.length + right.length + 1;

    if (needed >= width) {
      return '$left\n    $right';
    }

    final padding = width - left.length - right.length;
    return '$left${' ' * padding}$right';
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

  /// Handle reorder
  void _handleReorder(int oldIndex, int newIndex) {
    final notifier = ref.read(setlistDetailProvider.notifier);

    notifier.reorderLocal(oldIndex, newIndex);

    Future.delayed(const Duration(milliseconds: 500), () {
      notifier.persistReorder();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show creating state
    if (_isCreating) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.accent),
              ),
              SizedBox(height: Spacing.space16),
              Text(
                'Creating setlist...',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Show error state
    if (_createError != null) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        appBar: AppBar(
          backgroundColor: AppColors.appBarBg,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.pagePadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.error,
                  size: 64,
                ),
                const SizedBox(height: Spacing.space24),
                Text(
                  _createError!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.callout.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space24),
                BrandActionButton(
                  label: 'Try Again',
                  onPressed: () {
                    setState(() {
                      _isCreating = true;
                      _createError = null;
                    });
                    _createSetlist();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Normal state - watch the provider
    final state = ref.watch(setlistDetailProvider);

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
        child: Column(
          children: [
            _buildAppBar(state),
            Expanded(child: _buildBody(state)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(SetlistDetailState state) {
    return BackOnlyAppBar(
      onBack: () => Navigator.of(context).pop(),
      showLoading: state.isDeleting || state.isReordering || _isSavingName,
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

    if (state.songs.isEmpty) {
      return _buildEmptyState(state);
    }

    return _buildContent(state);
  }

  Widget _buildContent(SetlistDetailState state) {
    return CustomScrollView(
      slivers: [
        // Header section
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

                // Action buttons
                SlideTransition(
                  position: _headerSlide,
                  child: FadeTransition(
                    opacity: _headerFade,
                    child: ActionButtonsRow(
                      onSongLookup: _handleSongLookup,
                      onBulkPaste: _handleBulkPaste,
                      onShare: _handleShare,
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.space24),
              ],
            ),
          ),
        ),

        // Reorderable song list
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
          sliver: SliverReorderableList(
            itemCount: state.songs.length,
            onReorder: _handleReorder,
            itemBuilder: (context, index) {
              final song = state.songs[index];
              return Padding(
                key: ValueKey(song.id),
                padding: const EdgeInsets.only(bottom: Spacing.space12),
                child: ReorderableSongCard(
                  song: song,
                  index: index,
                  onEdit: () {},
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
                  final scale = Tween<double>(begin: 1.0, end: 1.02).evaluate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  );
                  return Transform.scale(
                    scale: scale,
                    child: Material(
                      color: Colors.transparent,
                      elevation: 8,
                      shadowColor: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                      child: child,
                    ),
                  );
                },
                child: child,
              );
            },
          ),
        ),

        // Bottom padding
        const SliverToBoxAdapter(child: SizedBox(height: Spacing.space32)),
      ],
    );
  }

  Widget _buildHeaderSection(SetlistDetailState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Setlist name with edit icon
        _isEditingName ? _buildNameEditField() : _buildNameDisplay(),
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

  Widget _buildNameDisplay() {
    return Row(
      children: [
        Expanded(child: Text(_setlistName, style: AppTextStyles.title3)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _startEditingName,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.scaffoldBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.edit_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNameEditField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            style: AppTextStyles.title3,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.accent, width: 2),
              ),
            ),
            onSubmitted: (_) => _saveSetlistName(),
            onEditingComplete: _saveSetlistName,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _isSavingName ? null : _saveSetlistName,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _isSavingName
                ? const Padding(
                    padding: EdgeInsets.all(6),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textPrimary,
                    ),
                  )
                : const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: AppColors.textPrimary,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(SetlistDetailState state) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header section (always show)
          Padding(
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

                // Action buttons
                SlideTransition(
                  position: _headerSlide,
                  child: FadeTransition(
                    opacity: _headerFade,
                    child: ActionButtonsRow(
                      onSongLookup: _handleSongLookup,
                      onBulkPaste: _handleBulkPaste,
                      onShare: _handleShare,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Empty state content
          Padding(
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

                const SizedBox(height: Spacing.space32),

                GestureDetector(
                  onTap: _handleSongLookup,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.space24,
                      vertical: Spacing.space12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.accent, width: 2),
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_rounded,
                          color: AppColors.accent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Add Songs',
                          style: AppTextStyles.button.copyWith(
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DELETE SONG DIALOG (copied from setlist_detail_screen.dart)
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
