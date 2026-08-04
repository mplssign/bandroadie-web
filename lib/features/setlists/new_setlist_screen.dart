import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../components/ui/brand_action_button.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../bands/active_band_controller.dart';
import '../members/permissions/band_permissions_provider.dart';
import '../lyrics/models/lyrics_data.dart';
import '../lyrics/widgets/lyrics_view_screen.dart';
import 'models/bulk_song_row.dart';
import 'models/setlist_item_type.dart';
import 'models/setlist_song.dart';
import 'setlist_detail_controller.dart';
import 'setlist_repository.dart';
import 'setlists_screen.dart' show setlistsProvider;
import 'tuning/tuning_helpers.dart';
import 'widgets/action_buttons_row.dart';
import 'widgets/add_to_setlist/add_to_setlist_overlay.dart';
import 'widgets/add_to_setlist/bulk_entry_screen.dart';
import 'widgets/add_to_setlist/category_button.dart';
import 'widgets/add_to_setlist/original_song_screen.dart';
import 'widgets/back_only_app_bar.dart';
import 'widgets/reorderable_song_card.dart';
import 'widgets/song_lookup_overlay.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

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

  // Memoized shared metrics widths for ReorderableSongCard rows.
  List<SetlistSong>? _cachedMetricsSongsRef;
  int _cachedMetricsSongCount = -1;
  int? _cachedMetricsSignature;
  SongMetricsSharedWidths? _cachedMetricsWidths;
  static const double _metricsTextSafetyMarginPx = 4.0;
  static const double _tuningExtraWidthPx = 16.0;

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
    _headerSlide =
        Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(
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

  /// Handle “+ Add to Setlist” tap — opens the unified overlay.
  void _handleAddToSetlist() {
    if (_setlistId == null) return;
    final bandName = ref.read(activeBandProvider).activeBand?.name ?? '';
    final bandId = ref.read(activeBandIdProvider);
    showAddToSetlistOverlay(
      context: context,
      isCatalog: false,
      defaultArtist: bandName,
      onOriginalSongsSubmitted: (songs) async {
        if (bandId == null || _setlistId == null) return 0;
        return _handleOriginalSongsSubmit(bandId, songs);
      },
      onBulkSongsSubmitted: (validRows) async {
        if (bandId == null || _setlistId == null) {
          return const BulkEntryResult(addedCount: 0, setlistSongIds: []);
        }
        return _handleBulkSongsSubmit(bandId, validRows);
      },
      onSetBreakSubmitted: (durationMinutes, {saveAsTemplate = false}) async {
        final notifier = ref.read(setlistDetailProvider.notifier);
        final success = await notifier.addSpecialItem(
          type: SetlistItemType.setBreak,
          durationMinutes: durationMinutes,
          saveAsTemplate: saveAsTemplate,
        );
        if (mounted && success) {
          showSuccessSnackBar(
            context,
            message: 'Set Break added — ${durationMinutes}m break',
          );
        }
        return success;
      },
      onPauseSubmitted: (config) async {
        final notifier = ref.read(setlistDetailProvider.notifier);
        final success = await notifier.addSpecialItem(
          type: SetlistItemType.pause,
          durationSeconds: config.durationSeconds,
          purposes: config.purposes,
          customPurposes: config.customPurposes,
          saveAsTemplate: config.saveAsTemplate,
        );
        if (mounted && success) {
          showSuccessSnackBar(
            context,
            message: 'Pause added to setlist!',
          );
        }
        return success;
      },
      onSavedPauseSelected: (template) async {
        final notifier = ref.read(setlistDetailProvider.notifier);
        final success = await notifier.addExistingTemplate(template);
        if (mounted && success) {
          showSuccessSnackBar(
            context,
            message: 'Pause added to setlist!',
          );
        }
        return success;
      },
      onCategorySelected: (category) {
        switch (category) {
          case AddToSetlistCategory.cover:
            _handleSongLookup();
          case AddToSetlistCategory.bulk:
          case AddToSetlistCategory.original:
          case AddToSetlistCategory.setBreak:
          case AddToSetlistCategory.pause:
            // All handled inside overlay
            break;
        }
      },
    );
  }

  /// Create original songs via the repository and add them to this setlist.
  Future<int> _handleOriginalSongsSubmit(
    String bandId,
    List<({String title, String artist})> songs,
  ) async {
    final repository = ref.read(setlistRepositoryProvider);
    var addedCount = 0;

    for (final song in songs) {
      try {
        final songId = await _ensureSongRecord(
          bandId,
          song.title,
          song.artist,
        );
        final result = await repository.addSongToSetlistEnsureCatalog(
          bandId: bandId,
          setlistId: _setlistId!,
          songId: songId,
          songTitle: song.title,
          songArtist: song.artist,
        );
        if (result.success) addedCount++;
      } catch (e) {
        debugPrint('[NewSetlist] Error adding original song: $e');
      }
    }

    if (addedCount > 0) {
      ref.read(setlistDetailProvider.notifier).loadSongs();
      ref.read(setlistsProvider.notifier).refresh();

      if (mounted) {
        showAppSnackBar(
          context,
          message: '$addedCount song${addedCount == 1 ? '' : 's'} added',
        );
      }
    }
    return addedCount;
  }

  /// Find or create a song record in the songs table.
  Future<String> _ensureSongRecord(
    String bandId,
    String title,
    String artist,
  ) async {
    final result = await supabase
        .from('songs')
        .select('id')
        .eq('band_id', bandId)
        .ilike('title', title.trim())
        .ilike('artist', artist.trim())
        .limit(1);

    if ((result as List).isNotEmpty) {
      return result[0]['id'] as String;
    }

    final inserted = await supabase
        .from('songs')
        .insert({
          'band_id': bandId,
          'title': title.trim(),
          'artist': artist.trim(),
        })
        .select('id')
        .single();

    return inserted['id'] as String;
  }

  /// Bulk add songs via the repository (called from BulkEntryScreen).
  Future<BulkEntryResult> _handleBulkSongsSubmit(
    String bandId,
    List<BulkSongRow> validRows,
  ) async {
    final repository = ref.read(setlistRepositoryProvider);
    final result = await repository.bulkAddSongs(
      bandId: bandId,
      setlistId: _setlistId!,
      rows: validRows,
    );

    if (result.hasAddedSongs) {
      ref.read(setlistDetailProvider.notifier).loadSongs();
      ref.read(setlistsProvider.notifier).refresh();

      if (mounted && result.addedCount > 0) {
        showAppSnackBar(
          context,
          message:
              '${result.addedCount} song${result.addedCount == 1 ? '' : 's'} added',
          duration: const Duration(seconds: 4),
          action: result.setlistSongIds.isNotEmpty
              ? SnackBarAction(
                  label: 'UNDO',
                  textColor: AppColors.primary,
                  onPressed: () => _handleUndoBulkAdd(result.setlistSongIds),
                )
              : null,
        );
      }
    }

    return BulkEntryResult(
      addedCount: result.addedCount,
      setlistSongIds: result.setlistSongIds,
    );
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

  /// Handle Original Song entry — shows full-screen modal
  void _handleOriginalSongEntry() {
    if (_setlistId == null) return;
    final bandId = ref.read(activeBandIdProvider);
    final bandName = ref.read(activeBandProvider).activeBand?.name ?? '';
    if (bandId == null) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Original Song Entry',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(Spacing.space16),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(Spacing.cardRadius),
                border: Border.all(color: context.colors.border, width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Spacing.cardRadius),
                child: OriginalSongScreen(
                  defaultArtist: bandName,
                  onSubmit: (songs) async {
                    final addedCount =
                        await _handleOriginalSongsSubmit(bandId, songs);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    return addedCount;
                  },
                  onBack: () => Navigator.of(dialogContext).pop(),
                  onClose: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuart,
          reverseCurve: Curves.easeInQuart,
        );

        return FadeTransition(
          opacity: curvedAnimation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }

  /// Handle Bulk Entry — shows full-screen modal
  void _handleBulkEntry() {
    if (_setlistId == null) return;
    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Bulk Entry',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(Spacing.space16),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(Spacing.cardRadius),
                border: Border.all(color: context.colors.border, width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Spacing.cardRadius),
                child: BulkEntryScreen(
                  onSubmit: (validRows) async {
                    final result =
                        await _handleBulkSongsSubmit(bandId, validRows);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    return result;
                  },
                  onBack: () => Navigator.of(dialogContext).pop(),
                  onClose: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuart,
          reverseCurve: Curves.easeInQuart,
        );

        return FadeTransition(
          opacity: curvedAnimation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: child,
          ),
        );
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
  // ignore: use_build_context_synchronously
  void _handleShare(BuildContext context) async {
    final state = ref.read(setlistDetailProvider);
    final text = _generateShareText(
      setlistName: _setlistName,
      songs: state.songs,
    );

    try {
      // On iOS/macOS, Share.share() needs sharePositionOrigin for the popover
      // We use the center of the screen as a fallback since we don't have the button position
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      final box = context.findRenderObject() as RenderBox?;
      final position = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          // ignore: use_build_context_synchronously
          : Rect.fromLTWH(0, 0, MediaQuery.of(context).size.width, 56);

      await Share.share(
        text,
        sharePositionOrigin: position,
      );
    } catch (e) {
      debugPrint('[SetlistShare] Error sharing: $e');
      if (mounted) {
        showErrorSnackBar(
          // ignore: use_build_context_synchronously
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
    final bpmText =
        song.bpm != null && song.bpm! > 0 ? '${song.bpm} BPM' : '- BPM';
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

  /// Confirm and delete a song via swipe-to-dismiss.
  /// Always returns false because deleteSong() removes the item from state,
  /// which rebuilds the widget tree without the dismissed item.
  Future<bool> _confirmDeleteSong(String songId, String songTitle) async {
    final state = ref.read(setlistDetailProvider);

    final confirmed = await _showDeleteDialog(songTitle, state.isCatalog);
    if (!confirmed || !mounted) return false;

    HapticFeedback.heavyImpact();
    final notifier = ref.read(setlistDetailProvider.notifier);
    final success = await notifier.deleteSong(songId);

    if (mounted && success) {
      showAppSnackBar(
        context,
        message: state.isCatalog
            ? 'Song removed from Catalog and all setlists'
            : 'Song removed from setlist',
      );
    }
    // Always return false — the state update already removed the item
    // from the widget tree.
    return false;
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
    // RBAC: Permission guard — bounce back if user cannot create setlists
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);
    final canCreate = permissionsAsync.when(
      data: (p) => p.canCreateSetlists,
      loading: () => false,
      error: (_, __) => false,
    );
    if (!canCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
          showAppSnackBar(
            context,
            message: 'You don\'t have permission to create setlists.',
          );
        }
      });
      return Scaffold(
        backgroundColor: context.colors.background,
        body: SizedBox.shrink(),
      );
    }

    // Show creating state
    if (_isCreating) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
              SizedBox(height: Spacing.space16),
              Text(
                'Creating setlist...',
                style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: AppFontSizes.body),
              ),
            ],
          ),
        ),
      );
    }

    // Show error state
    if (_createError != null) {
      return Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: context.colors.appBarBg,
          leading: IconButton(
            icon: Icon(AppIcons.close, color: Colors.white),
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
                  AppIcons.error,
                  color: AppColors.error,
                  size: 64,
                ),
                const SizedBox(height: Spacing.space24),
                Text(
                  _createError!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textSecondary,
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
      backgroundColor: context.colors.background,
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
          valueColor: AlwaysStoppedAnimation(AppColors.primary),
        ),
      );
    }

    if (state.songs.isEmpty) {
      return _buildEmptyState(state);
    }

    return _buildContent(state);
  }

  SongMetricsSharedWidths _sharedMetricsWidthsForSongs(
      List<SetlistSong> songs) {
    final cachedWidths = _cachedMetricsWidths;
    if (cachedWidths != null &&
        identical(_cachedMetricsSongsRef, songs) &&
        _cachedMetricsSongCount == songs.length) {
      return cachedWidths;
    }

    final signature = _buildMetricsSignature(songs);
    if (cachedWidths != null &&
        _cachedMetricsSongCount == songs.length &&
        _cachedMetricsSignature == signature) {
      _cachedMetricsSongsRef = songs;
      return cachedWidths;
    }

    final computed = _computeSharedMetricsWidths(songs);
    _cachedMetricsSongsRef = songs;
    _cachedMetricsSongCount = songs.length;
    _cachedMetricsSignature = signature;
    _cachedMetricsWidths = computed;
    return computed;
  }

  int _buildMetricsSignature(List<SetlistSong> songs) {
    return Object.hashAll(
      songs.map(
        (song) => Object.hash(
          song.bpm,
          song.durationSeconds,
          song.musicalKey,
          song.tuning,
        ),
      ),
    );
  }

  SongMetricsSharedWidths _computeSharedMetricsWidths(List<SetlistSong> songs) {
    final metricStyle = DefaultTextStyle.of(context).style.merge(
          const TextStyle(
            fontSize: AppFontSizes.subhead,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        );

    double bpmWidth = 0;
    double durationWidth = 0;
    double keyWidth = 0;
    double tuningWidth = 0;

    for (final song in songs) {
      final bpmText = song.isBpmPlaceholder ? '- BPM' : song.formattedBpm;
      bpmWidth = math.max(bpmWidth, _measureTextWidth(bpmText, metricStyle));

      durationWidth = math.max(
        durationWidth,
        _measureTextWidth(song.formattedDuration, metricStyle),
      );

      final key = song.musicalKey;
      if (key != null && key.trim().isNotEmpty) {
        keyWidth = math.max(keyWidth, _measureBadgeWidth(key, metricStyle));
      }

      final tuningText = tuningShortLabel(song.tuning);
      tuningWidth = math.max(
        tuningWidth,
        _measureBadgeWidth(tuningText, metricStyle) + _tuningExtraWidthPx,
      );
    }

    return SongMetricsSharedWidths(
      bpmWidth: bpmWidth > 0 ? bpmWidth : SongCardLayout.bpmColWidth,
      durationWidth:
          durationWidth > 0 ? durationWidth : SongCardLayout.durationColWidth,
      keyWidth: keyWidth > 0 ? keyWidth : SongCardLayout.keyColWidth,
      tuningWidth:
          tuningWidth > 0 ? tuningWidth : SongCardLayout.trailingColWidth,
    );
  }

  double _measureBadgeWidth(String label, TextStyle style) {
    final textWidth = _measureTextWidth(label, style);
    return textWidth + (Spacing.space12 * 2);
  }

  double _measureTextWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      textWidthBasis: TextWidthBasis.longestLine,
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    return painter.width.ceilToDouble() + _metricsTextSafetyMarginPx;
  }

  Widget _buildContent(SetlistDetailState state) {
    final sharedWidths = _sharedMetricsWidthsForSongs(state.songs);

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
                      onAddToSetlist: _handleAddToSetlist,
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
            onReorderItem: _handleReorder,
            itemBuilder: (context, index) {
              final song = state.songs[index];
              return Padding(
                key: ValueKey(song.id),
                padding: const EdgeInsets.only(bottom: Spacing.space12),
                child: Dismissible(
                  key: Key('dismiss_song_${song.id}'),
                  direction: DismissDirection.endToStart,
                  dismissThresholds: const {
                    DismissDirection.endToStart: 0.4,
                  },
                  confirmDismiss: (_) =>
                      _confirmDeleteSong(song.id, song.title),
                  movementDuration: AppDurations.medium,
                  background: const SizedBox.shrink(),
                  secondaryBackground: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: Spacing.space24),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Delete',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: AppFontSizes.subhead,
                          ),
                        ),
                        SizedBox(width: Spacing.space8),
                        Icon(AppIcons.delete, color: Colors.white, size: 22),
                      ],
                    ),
                  ),
                  child: ReorderableSongCard(
                    song: song,
                    index: index,
                    sharedWidths: sharedWidths,
                    onTap: () {},
                    onLyricsView: () {
                      final lyrics = LyricsData.fromJsonString(song.lyrics);
                      showLyricsViewScreen(
                        context,
                        lyrics: lyrics,
                        songId: song.id,
                        songTitle: song.title,
                      );
                    },
                    onEdit: () {},
                    onDelete: () => _handleDelete(song.id, song.title),
                    onTuningChanged: (tuning) {
                      final notifier = ref.read(setlistDetailProvider.notifier);
                      if (tuning.isEmpty) {
                        return notifier.clearSongTuning(song.id);
                      }
                      return notifier.updateSongTuning(song.id, tuning);
                    },
                  ),
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
          '${state.formattedMetadata} • ${state.formattedDuration}',
          style: AppTextStyles.headline.copyWith(
            color: context.colors.textSecondary,
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
              color: context.colors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              AppIcons.edit,
              size: 18,
              color: context.colors.textSecondary,
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
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
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
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _isSavingName
                ? Padding(
                    padding: EdgeInsets.all(6),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.textPrimary,
                    ),
                  )
                : Icon(
                    AppIcons.check,
                    size: 18,
                    color: context.colors.textPrimary,
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
                      onAddToSetlist: _handleAddToSetlist,
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
                // Subtitle
                Text(
                  "Choose how you'd like to add songs:",
                  textAlign: TextAlign.center,
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space32),

                // Action buttons
                CategoryButton(
                  icon: AppIcons.search,
                  label: 'Cover Song',
                  subtitle: 'Search by song or artist',
                  onTap: _handleSongLookup,
                ),
                const SizedBox(height: Spacing.space16),
                CategoryButton(
                  icon: AppIcons.edit,
                  label: 'Original Song',
                  subtitle: 'Add originals or hard to find covers',
                  onTap: _handleOriginalSongEntry,
                ),
                const SizedBox(height: Spacing.space16),
                CategoryButton(
                  icon: Icons.list_rounded,
                  label: 'Bulk Entry',
                  subtitle: 'Paste from a spreadsheet',
                  onTap: _handleBulkEntry,
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
      backgroundColor: context.colors.surface,
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
            style: AppTextStyles.headline.copyWith(color: AppColors.primary),
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
                    AppIcons.warning,
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
              color: context.colors.textSecondary,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            backgroundColor: isCatalog
                ? AppColors.error.withValues(alpha: 0.15)
                : AppColors.primary.withValues(alpha: 0.15),
          ),
          child: Text(
            isCatalog ? 'Delete Forever' : 'Remove',
            style: AppTextStyles.button.copyWith(
              color: isCatalog ? AppColors.error : AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}
