import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../bands/active_band_controller.dart';
import '../lyrics/models/lyrics_data.dart';
import '../lyrics/widgets/lyrics_view_screen.dart';
import '../members/permissions/band_permissions_provider.dart';
import 'models/bulk_song_row.dart';
import 'models/setlist_item.dart';
import 'models/setlist_item_type.dart';
import 'models/setlist_song.dart';
import 'widgets/print_options_bottom_sheet.dart';
import 'services/tuning_sort_service.dart';
import 'setlist_detail_controller.dart';
import 'setlist_repository.dart';
import 'setlists_screen.dart' show setlistsProvider;
import 'tuning/tuning_helpers.dart';
import 'widgets/add_to_setlist/add_to_setlist_overlay.dart';
import 'widgets/add_to_setlist/bulk_entry_screen.dart';
import 'widgets/add_to_setlist/category_button.dart';
import 'widgets/add_to_setlist/original_song_screen.dart';
import 'widgets/back_only_app_bar.dart';
import 'widgets/reorderable_song_card.dart';
import 'widgets/selection_circle.dart';
import 'widgets/setlist_picker_bottom_sheet.dart';
import 'widgets/song_details_bottom_sheet.dart';
import 'widgets/song_lookup_overlay.dart';
import 'widgets/special_item_card.dart';
import 'special_item_repository.dart';
import 'models/special_item.dart';
import 'links/song_link.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import '../songs/song_enrichment_service.dart';
import '../songs/external_song_lookup_service.dart';
import '../songs/services/song_enrichment_orchestrator.dart';
import '../songs/widgets/enrichment_selector_bottom_sheet.dart';
import '../songs/widgets/enrichment_results_overlay.dart';
import '../songs/widgets/enrichment_progress_overlay.dart';

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

/// Share output format options
enum ShareFormat {
  textEmail, // Rich plain-text format (existing)
  spreadsheet, // Tab-delimited format
}

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
  CatalogSortMode? _lastCatalogSortMode;

  // Track current name (can be renamed)
  late String _currentName;

  // Debounce timer for reorder persistence
  Timer? _reorderDebounceTimer;

  // Memoized shared metrics widths for ReorderableSongCard rows.
  List<SetlistSong>? _cachedMetricsSongsRef;
  int _cachedMetricsSongCount = -1;
  int? _cachedMetricsSignature;
  SongMetricsSharedWidths? _cachedMetricsWidths;
  static const double _metricsTextSafetyMarginPx = 4.0;
  static const double _tuningExtraWidthPx = 16.0;

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

    // FIX: Call controller directly with route args instead of setting selectedSetlistProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(setlistDetailProvider.notifier).loadSetlist(
            widget.setlistId,
            widget.setlistName,
            forceReload: true,
          );
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
    _sortFadeAnimation = TweenSequence<double>([
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
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Rename Setlist',
          style:
              AppTextStyles.title3.copyWith(color: context.colors.textPrimary),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            style:
                AppTextStyles.body.copyWith(color: context.colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter setlist name',
              hintStyle: AppTextStyles.body.copyWith(
                color: context.colors.textMuted,
              ),
              filled: true,
              fillColor: context.colors.background,
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
              style:
                  AppTextStyles.body.copyWith(color: context.colors.textMuted),
            ),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
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

  /// Confirm and delete a song via swipe-to-dismiss.
  /// Always returns false because deleteSong() removes the item from state,
  /// which rebuilds the widget tree without the dismissed item.
  /// Returning true would cause a "dismissed Dismissible still in tree" error.
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

  /// Handle move or copy song to another setlist via swipe-right gesture.
  /// Always returns false to prevent Dismissible from removing the widget.
  Future<bool> _handleMoveOrCopySong(String songId, String songTitle) async {
    final state = ref.read(setlistDetailProvider);

    HapticFeedback.mediumImpact();

    // Open setlist picker with source setlist context
    final result = await showSetlistPickerBottomSheet(
      context,
      selectedSongCount: 1,
      sourceSetlistId: state.setlistId,
      sourceSetlistName: state.setlistName,
    );

    if (result == null || !mounted) return false;

    final notifier = ref.read(setlistDetailProvider.notifier);
    final repository = ref.read(setlistRepositoryProvider);
    final bandId = ref.read(activeBandIdProvider);
    String targetSetlistId;
    String targetSetlistName;

    // Handle create new setlist
    if (result.createNew && result.newSetlistName != null) {
      if (bandId == null || !mounted) {
        showErrorSnackBar(context, message: 'No band selected');
        return false;
      }

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
        return false;
      }
    } else {
      targetSetlistId = result.setlistId!;
      targetSetlistName = result.setlistName!;
    }

    // Check if target is the same as current setlist
    if (targetSetlistId == state.setlistId) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Same Setlist'),
            content: Text(
              '"$songTitle" is already in $targetSetlistName.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return false;
    }

    // Check if song already exists in target setlist
    final existingCheck = await supabase
        .from('setlist_songs')
        .select('id')
        .eq('setlist_id', targetSetlistId)
        .eq('song_id', songId)
        .limit(1);

    if ((existingCheck as List).isNotEmpty) {
      if (mounted) {
        showErrorSnackBar(
          context,
          message: '"$songTitle" already exists in $targetSetlistName',
        );
      }
      return false;
    }

    // Perform move or copy
    bool success;
    if (result.isMoveMode) {
      success = await notifier.moveSongToSetlist(
        songId: songId,
        targetSetlistId: targetSetlistId,
        sourceSetlistId: state.setlistId,
      );
    } else {
      success = await notifier.copySongToSetlist(
        songId: songId,
        targetSetlistId: targetSetlistId,
      );
    }

    if (mounted && success) {
      final actionText = result.isMoveMode ? 'moved to' : 'copied to';
      showSuccessSnackBar(
        context,
        message: '"$songTitle" $actionText $targetSetlistName',
      );
    } else if (mounted) {
      showErrorSnackBar(
        context,
        message: 'Failed to ${result.isMoveMode ? 'move' : 'copy'} song',
      );
    }

    // Always return false — state management handles the update
    return false;
  }

  /// Build the background widget for swipe-right (Move/Copy)
  Widget _buildMoveOrCopyBackground() {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: Spacing.space24),
      decoration: BoxDecoration(
        color: context.colors.success,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.arrowRight, color: Colors.white, size: 22),
          SizedBox(width: Spacing.space8),
          Text(
            'Move/Copy',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: AppFontSizes.subhead,
            ),
          ),
        ],
      ),
    );
  }

  /// Build the background widget for swipe-left (Delete/Remove)
  Widget _buildDeleteBackground() {
    final state = ref.read(setlistDetailProvider);
    final label = state.isCatalog ? 'Delete' : 'Remove';

    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: Spacing.space24),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: AppFontSizes.subhead,
            ),
          ),
          const SizedBox(width: Spacing.space8),
          const Icon(AppIcons.delete, color: Colors.white, size: 22),
        ],
      ),
    );
  }

  /// Returns memoized shared metrics widths for the full songs list.
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

  /// Build a song card.
  Widget _buildSongCardWithMenu({
    required SetlistSong song,
    required int index,
    required bool isDraggable,
    required bool canEdit,
    required SongMetricsSharedWidths sharedWidths,
  }) {
    final card = ReorderableSongCard(
      song: song,
      index: index,
      sharedWidths: sharedWidths,
      isDraggable: isDraggable,
      onTap: () => _handleSongTap(song, readOnly: !canEdit),
      onLyricsView: () {
        final lyrics = LyricsData.fromJsonString(song.lyrics);
        showLyricsViewScreen(
          context,
          lyrics: lyrics,
          songId: song.id,
          songTitle: song.title,
        );
      },
      onEdit: canEdit ? () => _handleSongTap(song) : null,
      onDelete: canEdit ? () => _handleDelete(song.id, song.title) : null,
      onTuningChanged: canEdit
          ? (tuning) {
              final notifier = ref.read(setlistDetailProvider.notifier);
              if (tuning.isEmpty) {
                return notifier.clearSongTuning(song.id);
              }
              return notifier.updateSongTuning(song.id, tuning);
            }
          : null,
    );

    return card;
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

  /// Handle “+ Add to Setlist” tap — opens the unified overlay.
  void _handleOpenAddOverlay() async {
    final state = ref.read(setlistDetailProvider);
    final bandName = ref.read(activeBandProvider).activeBand?.name ?? '';
    final bandId = ref.read(activeBandIdProvider);

    // Fetch saved templates for both categories
    List<SpecialItem> savedSetBreaks = [];
    List<SpecialItem> savedPauses = [];
    if (bandId != null) {
      final repo = ref.read(specialItemRepositoryProvider);
      try {
        final results = await Future.wait([
          repo.fetchTemplates(
            bandId: bandId,
            type: SetlistItemType.setBreak,
          ),
          repo.fetchTemplates(
            bandId: bandId,
            type: SetlistItemType.pause,
          ),
        ]);
        savedSetBreaks = results[0];
        savedPauses = results[1];
      } catch (_) {
        // Non-critical — overlay still works without templates
      }
    }

    if (!mounted) return;

    showAddToSetlistOverlay(
      context: context,
      isCatalog: state.isCatalog,
      defaultArtist: bandName,
      savedSetBreaks: savedSetBreaks,
      savedPauses: savedPauses,
      onOriginalSongsSubmitted: (songs) async {
        if (bandId == null) return 0;
        return _handleOriginalSongsSubmit(bandId, songs);
      },
      onBulkSongsSubmitted: (validRows) async {
        if (bandId == null) {
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
      onSavedSetBreakSelected: (template) async {
        final notifier = ref.read(setlistDetailProvider.notifier);
        final success = await notifier.addExistingTemplate(template);
        if (mounted && success) {
          showSuccessSnackBar(
            context,
            message: 'Set Break added to setlist!',
          );
        }
        return success;
      },
      onDeleteTemplate: (templateId) async {
        final repo = ref.read(specialItemRepositoryProvider);
        try {
          await repo.deleteTemplate(templateId);
          return true;
        } catch (_) {
          return false;
        }
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

  /// Handle deletion of a special item (set break / pause).
  Future<void> _handleDeleteSpecialItem(SetlistItem item) async {
    final label = item.specialItem?.displayLabel ?? item.type.displayName;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Remove $label?',
          style: AppTextStyles.title3,
        ),
        content: Text(
          'Remove this ${item.type.displayName.toLowerCase()} from the setlist?',
          style:
              AppTextStyles.body.copyWith(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.button
                  .copyWith(color: context.colors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Remove',
              style: AppTextStyles.button.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final notifier = ref.read(setlistDetailProvider.notifier);
    final success = await notifier.deleteSpecialItem(item.id);

    if (mounted && success) {
      showAppSnackBar(context, message: '$label removed');
    }
  }

  /// Confirm-and-delete for Dismissible swipe on special items.
  /// Returns true if the item was deleted (card should be dismissed).
  Future<bool> _confirmDeleteSpecialItem(SetlistItem item) async {
    final label = item.specialItem?.displayLabel ?? item.type.displayName;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove $label?', style: AppTextStyles.title3),
        content: Text(
          'Remove this ${item.type.displayName.toLowerCase()} from the setlist?',
          style:
              AppTextStyles.body.copyWith(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.button
                  .copyWith(color: context.colors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Remove',
              style: AppTextStyles.button.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    HapticFeedback.heavyImpact();
    final notifier = ref.read(setlistDetailProvider.notifier);
    final success = await notifier.deleteSpecialItem(item.id);

    if (mounted && success) {
      showAppSnackBar(context, message: '$label removed');
    }
    return success;
  }

  /// Open the edit overlay for an existing set break or pause in the setlist.
  void _handleEditSpecialItem(SetlistItem item) {
    final specialItem = item.specialItem;
    if (specialItem == null) return;

    showEditSpecialItemOverlay(
      context: context,
      item: specialItem,
      onSetBreakUpdated: (specialItemId, durationMinutes) async {
        final notifier = ref.read(setlistDetailProvider.notifier);
        final success = await notifier.updateSpecialItem(
          specialItemId: specialItemId,
          durationMinutes: durationMinutes,
        );
        if (mounted && success) {
          showSuccessSnackBar(
            context,
            message: 'Set Break updated — ${durationMinutes}m break',
          );
        }
        return success;
      },
      onPauseUpdated: (specialItemId, config) async {
        final notifier = ref.read(setlistDetailProvider.notifier);
        final success = await notifier.updateSpecialItem(
          specialItemId: specialItemId,
          durationSeconds: config.durationSeconds,
          clearDurationSeconds: config.durationSeconds == null,
          purposes: config.purposes,
          customPurposes: config.customPurposes,
        );
        if (mounted && success) {
          showSuccessSnackBar(
            context,
            message: 'Pause updated!',
          );
        }
        return success;
      },
    );
  }

  /// Handle reorder for mixed items (songs + breaks + pauses).
  void _handleItemReorder(int oldIndex, int newIndex) {
    final notifier = ref.read(setlistDetailProvider.notifier);

    notifier.reorderItemsLocal(oldIndex, newIndex);

    _reorderDebounceTimer?.cancel();
    _reorderDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      await notifier.persistItemReorder();
    });
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
          setlistId: widget.setlistId,
          songId: songId,
          songTitle: song.title,
          songArtist: song.artist,
        );
        if (result.success) addedCount++;
      } catch (e) {
        debugPrint('[SetlistDetail] Error adding original song: $e');
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
      setlistId: widget.setlistId,
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

  /// Handle Original Song entry — shows full-screen modal
  void _handleOriginalSongEntry() {
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

  /// Show sort options bottom sheet (Catalog only)
  void _showSortOptions(
    BuildContext context,
    WidgetRef ref,
    CatalogSortMode currentMode,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isDismissible: true,
      enableDrag: true,
      builder: (context) => _CatalogSortSheet(currentMode: currentMode),
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
    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Adding ${_selectedSongIds.length} ${_selectedSongIds.length == 1 ? 'song' : 'songs'}...',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    int addedCount = 0;
    int skippedCount = 0;

    try {
      // Call batch add RPC
      final bulkResult = await repository.bulkAddSongsToSetlist(
        bandId: bandId,
        setlistId: targetSetlistId,
        songIds: _selectedSongIds.toList(),
      );

      addedCount = bulkResult.addedCount;
      skippedCount = bulkResult.skippedCount;

      if (!bulkResult.success) {
        debugPrint('[SelectMode] Bulk add failed: ${bulkResult.error}');
        if (mounted) {
          showErrorSnackBar(
            context,
            message: bulkResult.error ?? 'Failed to add songs',
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('[SelectMode] Error in bulk add: $e');
      if (mounted) {
        showErrorSnackBar(context, message: 'Failed to add songs');
      }
      return;
    } finally {
      if (mounted) {
        // Close loading dialog if still open
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
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
          message: 'Added $addedCount $songWord to "$targetSetlistName"',
        );
      } else if (skippedCount > 0) {
        showAppSnackBar(
          context,
          message: 'Songs already in "$targetSetlistName"',
        );
      }
    }
  }

  /// Handle enrichment of selected songs (Task 8: multi-select entry point)
  Future<void> _handleEnrichSelectedSongs() async {
    if (_selectedSongIds.isEmpty) return;

    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) {
      debugPrint('[SelectMode] No active band - cannot enrich');
      return;
    }

    // Step 1: Show selector
    final selection = await showEnrichmentSelectorBottomSheet(
      context,
      songCount: _selectedSongIds.length,
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

    final spinner = _showEnrichmentSpinnerOverlay();
    late final EnrichmentOrchestrationResult result;
    try {
      result = await orchestrator.enrichSongs(
        songIds: _selectedSongIds.toList(),
        bandId: bandId,
        enrichBpm: selection.bpmSelected,
        enrichDuration: selection.durationSelected,
        enrichKey: selection.keySelected,
      );
    } finally {
      spinner.remove();
    }

    if (!mounted) return;

    // Step 3: Broadcast updates for enriched songs to trigger UI refresh
    final broadcaster = ref.read(songUpdateBroadcasterProvider.notifier);
    for (final detail in result.details) {
      if (detail.bpmResult == EnrichmentFieldResult.updated ||
          detail.durationResult == EnrichmentFieldResult.updated ||
          detail.keyResult == EnrichmentFieldResult.updated) {
        // Broadcast update for this song
        broadcaster.broadcast(SongUpdateEvent(songId: detail.songId));
      }
    }

    // Step 4: Show results overlay
    await showEnrichmentResultsOverlay(
      context: context,
      result: result,
    );

    // Step 5: Exit select mode
    _exitSelectMode();

    final didUpdateMetadata = result.details.any(
      (detail) =>
          detail.bpmResult == EnrichmentFieldResult.updated ||
          detail.durationResult == EnrichmentFieldResult.updated ||
          detail.keyResult == EnrichmentFieldResult.updated,
    );
    if (didUpdateMetadata) {
      await ref.read(setlistDetailProvider.notifier).loadSongs();
    }
  }

  /// Handle enrichment of all catalog songs (Task 9: catalog-wide entry point)
  Future<void> _handleEnrichAllCatalogSongs(SetlistDetailState state) async {
    if (!state.isCatalog || state.songs.isEmpty) return;

    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) {
      debugPrint('[Catalog] No active band - cannot enrich');
      return;
    }

    // Step 1: Show selector
    final selection = await showEnrichmentSelectorBottomSheet(
      context,
      songCount: state.songs.length,
    );
    if (selection == null || !mounted) return;

    // Step 2: Show progress overlay for large catalogs (50+ songs)
    void Function(int completed, int total, String currentSong)? updateProgress;
    NavigatorState? navigator;

    if (state.songs.length >= 50) {
      updateProgress = await showEnrichmentProgressOverlay(context: context);
      if (!mounted) return;
      navigator = Navigator.of(context);
    }

    final showSpinner = updateProgress == null;
    final spinner = showSpinner ? _showEnrichmentSpinnerOverlay() : null;

    // Step 3: Orchestrate enrichment with progress tracking
    final supabase = Supabase.instance.client;
    final repository = SetlistRepository();
    final enrichmentService = SongEnrichmentService(supabase);
    final lookupService = ExternalSongLookupService(supabase);

    final orchestrator = SongEnrichmentOrchestrator(
      repository: repository,
      enrichmentService: enrichmentService,
      lookupService: lookupService,
    );

    // Map song progress to overlay updates
    void onProgress(int completed, int total) {
      if (updateProgress != null && completed <= state.songs.length) {
        final currentSong = state.songs[completed - 1];
        updateProgress(
          completed,
          total,
          '${currentSong.title} • ${currentSong.artist}',
        );
      }
    }

    late final EnrichmentOrchestrationResult result;
    try {
      result = await orchestrator.enrichSongs(
        songIds: [], // Empty = all catalog songs
        bandId: bandId,
        enrichBpm: selection.bpmSelected,
        enrichDuration: selection.durationSelected,
        enrichKey: selection.keySelected,
        onProgress: onProgress,
      );
    } finally {
      spinner?.remove();
      // Remove progress overlay if it was shown
      if (navigator != null && navigator.canPop()) {
        navigator.pop();
      }
    }

    if (!mounted) return;

    // Step 4: Broadcast updates for enriched songs to trigger UI refresh
    final broadcaster = ref.read(songUpdateBroadcasterProvider.notifier);
    for (final detail in result.details) {
      if (detail.bpmResult == EnrichmentFieldResult.updated ||
          detail.durationResult == EnrichmentFieldResult.updated ||
          detail.keyResult == EnrichmentFieldResult.updated) {
        broadcaster.broadcast(SongUpdateEvent(songId: detail.songId));
      }
    }

    // Step 5: Show results overlay
    await showEnrichmentResultsOverlay(
      context: context,
      result: result,
    );

    final didUpdateMetadata = result.details.any(
      (detail) =>
          detail.bpmResult == EnrichmentFieldResult.updated ||
          detail.durationResult == EnrichmentFieldResult.updated ||
          detail.keyResult == EnrichmentFieldResult.updated,
    );
    if (didUpdateMetadata) {
      await ref.read(setlistDetailProvider.notifier).loadSongs();
    }
  }

  OverlayEntry _showEnrichmentSpinnerOverlay() {
    final overlay = Overlay.of(context, rootOverlay: true);
    final colors = context.colors;

    final entry = OverlayEntry(
      builder: (context) {
        return Material(
          color: Colors.black54,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(Spacing.space20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(Spacing.cardRadius),
                border: Border.all(color: colors.borderStrong),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: Spacing.space24,
                    height: Spacing.space24,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.space12),
                  Text(
                    'Enriching songs...',
                    style: AppTextStyles.callout.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    return entry;
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
  /// When [readOnly] is true, the sheet opens in view-only mode.
  Future<void> _handleSongTap(SetlistSong song, {bool readOnly = false}) async {
    final result = await showSongDetailsBottomSheet(
      context,
      song: song,
      isReadOnly: readOnly,
    );

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
      if (result.tuningChanged) {
        debugPrint('[SetlistDetail] Saving tuning...');
        final success = (result.tuning == null || result.tuning!.isEmpty)
            ? await notifier.clearSongTuning(song.id)
            : await notifier.updateSongTuning(song.id, result.tuning!);
        debugPrint('[SetlistDetail] Tuning save result: $success');
      }

      // Update YouTube links if changed
      if (result.youtubeLinksChanged && result.youtubeLinks != null) {
        debugPrint('[SetlistDetail] Saving YouTube links...');
        // Convert list to JSON string for storage
        final jsonString = SongLink.listToJson(result.youtubeLinks!);
        final success = await notifier.updateSongYoutubeLinks(
          song.id,
          jsonString,
        );
        debugPrint('[SetlistDetail] YouTube links save result: $success');
      }

      // Update lyrics if changed
      if (result.lyricsChanged) {
        debugPrint('[SetlistDetail] Saving lyrics...');
        final success = await notifier.updateSongLyrics(song.id, result.lyrics);
        debugPrint('[SetlistDetail] Lyrics save result: $success');
      }

      // Update musical key if changed
      if (result.musicalKeyChanged) {
        debugPrint('[SetlistDetail] Saving musical key...');
        final success =
            (result.musicalKey == null || result.musicalKey!.isEmpty)
                ? await notifier.clearSongMusicalKey(song.id)
                : await notifier.updateSongMusicalKey(
                    song.id,
                    result.musicalKey,
                  );
        debugPrint('[SetlistDetail] Musical key save result: $success');
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
    // Show format picker and get user selection
    final format = await _showShareFormatPicker();
    if (format == null) return; // User dismissed

    final state = ref.read(setlistDetailProvider);

    // Generate text based on selected format
    final text = format == ShareFormat.textEmail
        ? _generateShareText(
            setlistName: _currentName,
            songs: state.songs,
          )
        : _generateSpreadsheetText(
            songs: state.songs,
          );

    if (!mounted) return;

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

  /// Show format picker bottom sheet and return selected format.
  /// Returns null if user dismisses without selecting.
  Future<ShareFormat?> _showShareFormatPicker() async {
    if (!mounted) return null;

    final result = await showModalBottomSheet<ShareFormat>(
      context: context,
      backgroundColor:
          kIsWeb ? const Color(0xFF1a1a1a) : context.colors.surface,
      barrierColor: kIsWeb ? Colors.black.withValues(alpha: 0.7) : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isDismissible: true,
      enableDrag: !kIsWeb, // Disable drag on web (no touch gestures)
      isScrollControlled: true, // Allow custom height
      builder: (context) => const _ShareFormatSheet(),
    );

    if (!mounted) return null;
    return result;
  }

  /// Handle print setlist action.
  /// Shows print options bottom sheet, then prints with selected template.
  /// Works on all platforms (Web uses HTML, native uses PDF).
  Future<void> _handlePrint() async {
    final band = ref.read(activeBandProvider).activeBand;
    if (band == null) return;

    final state = ref.read(setlistDetailProvider);

    // Catalog has no items list — convert songs to SetlistItem wrappers.
    final items = state.isCatalog
        ? state.songs
            .asMap()
            .entries
            .map((e) => SetlistItem(
                  id: e.value.id,
                  type: SetlistItemType.song,
                  position: e.key,
                  song: e.value,
                ))
            .toList()
        : state.items;

    if (!mounted) return;

    await PrintOptionsBottomSheet.show(
      context,
      bandId: band.id,
      setlistName: _currentName,
      items: items,
      bandName: band.name,
    );
  }

  /// Handle delete setlist with confirmation dialog
  Future<void> _handleDeleteSetlist() async {
    final state = ref.read(setlistDetailProvider);
    if (state.isCatalog) return; // Safety check

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text(
          'Delete "${state.setlistName}"?',
          style:
              AppTextStyles.title3.copyWith(color: context.colors.textPrimary),
        ),
        content: Text(
          'This will remove the setlist. Songs will remain in your Catalog.',
          style:
              AppTextStyles.body.copyWith(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(
                color: context.colors.textSecondary,
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
      final success =
          await ref.read(setlistDetailProvider.notifier).deleteSetlist();
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

  /// Generate tab-delimited spreadsheet text for the setlist.
  /// Format: Title\tArtist\tBPM\tTuning
  String _generateSpreadsheetText({
    required List<SetlistSong> songs,
  }) {
    final buffer = StringBuffer();

    // Header row
    buffer.writeln('Title\tArtist\tBPM\tTuning');

    // Data rows
    for (final song in songs) {
      final title = song.title;
      final artist = song.artist;
      final bpm =
          (song.bpm != null && song.bpm! > 0) ? song.bpm.toString() : '';
      final tuning = tuningShortLabel(song.tuning);

      buffer.writeln('$title\t$artist\t$bpm\t$tuning');
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

  /// Format the second line: "Artist\n### BPM • Tuning"
  /// Always places BPM/Tuning on a new line below the artist
  String _formatSongSecondLine(SetlistSong song) {
    final artist = song.artist;
    final bpmText =
        song.bpm != null && song.bpm! > 0 ? '${song.bpm} BPM' : '- BPM';
    final tuningText = tuningShortLabel(song.tuning);
    final metadata = '$bpmText • $tuningText';

    return '$artist\n$metadata';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setlistDetailProvider);

    // RBAC: Watch permissions for mutation gating
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);
    final canEdit = permissionsAsync.when(
      data: (p) => p.canEditSetlists,
      loading: () => false, // Fail closed — no mutation flicker
      error: (err, stack) => false, // Fail closed on error
    );

    // Detect catalog sort mode changes and trigger animation
    if (_lastCatalogSortMode != null &&
        _lastCatalogSortMode != state.catalogSortMode &&
        state.isCatalog) {
      // Sort mode changed - play the subtle reorder animation
      _sortAnimController.forward(from: 0);
    }
    _lastCatalogSortMode = state.catalogSortMode;

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
        child: Stack(
          children: [
            // Main content
            Column(
              children: [
                _buildAppBar(state),
                Expanded(child: _buildBody(state, canEdit)),
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
  Widget _buildActionButtonsRow(SetlistDetailState state, bool canEdit) {
    final selectedCount = _selectedSongIds.length;
    final enrichLabel = _isSelectMode && selectedCount > 0
        ? 'Enrich ($selectedCount)'
        : 'Enrich';

    return SingleChildScrollView(
      key: const ValueKey('action-buttons'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (state.isCatalog) ...[
            // Catalog order: + Add, Search, Sort, Enrich
            if (canEdit) ...[
              _ActionButton(
                icon: AppIcons.add,
                label: 'Add',
                onTap: _handleOpenAddOverlay,
              ),
              const SizedBox(width: 8),
            ],
            _ActionButton(icon: Icons.search_rounded, onTap: _startSearch),
            if (state.songs.isNotEmpty) ...[
              const SizedBox(width: 8),
              _ActionButton(
                icon: Icons.sort_rounded,
                label: 'Sort',
                onTap: () =>
                    _showSortOptions(context, ref, state.catalogSortMode),
              ),
            ],
            if (state.songs.isNotEmpty && canEdit) ...[
              const SizedBox(width: 8),
              _ActionButton(
                icon: Icons.auto_awesome,
                label: enrichLabel,
                onTap: _isSelectMode && selectedCount > 0
                    ? _handleEnrichSelectedSongs
                    : () => _handleEnrichAllCatalogSongs(state),
              ),
            ],
          ] else ...[
            // Keep non-catalog behavior unchanged.
            if (canEdit) ...[
              _ActionButton(
                icon: AppIcons.add,
                label: 'Add to Setlist',
                onTap: _handleOpenAddOverlay,
              ),
              const SizedBox(width: 8),
            ],
            if (ref
                    .read(setlistDetailProvider.notifier)
                    .availableTunings
                    .length >
                1) ...[
              _TuningSortButton(
                startingTuningId: state.startingTuningId,
                onTap: () {
                  ref
                      .read(setlistDetailProvider.notifier)
                      .cycleStartingTuning();
                  _sortAnimController.forward(from: 0);
                },
              ),
              const SizedBox(width: 8),
            ],
            // Search filter button (icon only) — read-only action
            _ActionButton(icon: Icons.search_rounded, onTap: _startSearch),
          ],
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
              style: AppTextStyles.body
                  .copyWith(color: context.colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Filter songs...',
                hintStyle: AppTextStyles.body.copyWith(
                  color: context.colors.textMuted,
                ),
                prefixIcon: Icon(
                  AppIcons.search,
                  size: 20,
                  color: context.colors.textMuted,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        child: Icon(
                          AppIcons.close,
                          size: 18,
                          color: context.colors.textMuted,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: context.colors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
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
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(SetlistDetailState state, bool canEdit) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(AppColors.primary),
        ),
      );
    }

    // Single source of truth: always render the full layout.
    // Empty setlists show header + action row + empty content area.
    return _buildContent(state, canEdit);
  }

  Widget _buildContent(SetlistDetailState state, bool canEdit) {
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
                    child: _buildHeaderSection(state, canEdit),
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
                            alignment: Alignment.topCenter,
                            child: child,
                          ),
                        );
                      },
                      child: _isSearching
                          ? _buildSearchBar()
                          : _buildActionButtonsRow(state, canEdit),
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
        ..._buildSongsList(state, canEdit),

        // Delete button (non-Catalog only, hidden for read-only)
        if (!state.isCatalog && canEdit)
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
                          ? context.colors.textMuted
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
            height: Spacing.space48 +
                Spacing.bottomNavHeight +
                MediaQuery.of(context).padding.bottom +
                32, // Extra scroll clearance
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderSection(SetlistDetailState state, bool canEdit) {
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
                    const Icon(AppIcons.star,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      _currentName,
                      style: AppTextStyles.pageTitle.copyWith(
                        color: context.colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!state.isCatalog && canEdit) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _showRenameDialog,
                      child: Icon(
                        AppIcons.edit,
                        color: context.colors.textMuted,
                        size: 16,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Right side: Select link (Catalog only) + Share icon
            // Select Mode toggle appears only for Catalog setlist
            if (state.isCatalog && state.songs.isNotEmpty && canEdit) ...[
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
                      color: AppColors.primary,
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
                color: AppColors.primary,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            // Share icon - opens share sheet with text share option
            IconButton(
              onPressed: _handleShare,
              icon: const Icon(
                AppIcons.share,
                size: 20,
                color: AppColors.primary,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ],
        ),
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
    );
  }

  /// Build the songs list (filtered if searching)
  List<Widget> _buildSongsList(SetlistDetailState state, bool canEdit) {
    // Apply search filter if active
    final displaySongs = _isSearching ? _filterSongs(state.songs) : state.songs;
    final sharedWidths = _sharedMetricsWidthsForSongs(state.songs);

    // Empty state (no songs and no items at all)
    if (state.songs.isEmpty && state.items.isEmpty) {
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
                  color: context.colors.textMuted,
                  size: 48,
                ),
                const SizedBox(height: Spacing.space16),
                Text(
                  'No songs found',
                  style: AppTextStyles.title3.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space8),
                Text(
                  'Try a different search term',
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textMuted,
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
                      child: Dismissible(
                        key: Key('dismiss_song_${song.id}'),
                        direction: canEdit
                            ? DismissDirection.horizontal
                            : DismissDirection.none,
                        dismissThresholds: const {
                          DismissDirection.endToStart: 0.4,
                          DismissDirection.startToEnd: 0.4,
                        },
                        confirmDismiss: (direction) {
                          if (direction == DismissDirection.endToStart) {
                            return _confirmDeleteSong(song.id, song.title);
                          } else {
                            return _handleMoveOrCopySong(song.id, song.title);
                          }
                        },
                        movementDuration: AppDurations.medium,
                        background: _buildMoveOrCopyBackground(),
                        secondaryBackground: _buildDeleteBackground(),
                        child: _buildSongCardWithMenu(
                          song: song,
                          index: index,
                          isDraggable: false,
                          canEdit: canEdit,
                          sharedWidths: sharedWidths,
                        ),
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

    // Non-Catalog, not searching: reorderable list (mixed items or songs)
    // When !canEdit, use SliverList instead of SliverReorderableList
    final useItems = state.items.isNotEmpty;
    final itemCount = useItems ? state.items.length : displaySongs.length;

    Widget itemBuilder(BuildContext context, int index) {
      if (useItems) {
        final item = state.items[index];

        // Special item (set break / pause)
        if (item.isSpecial) {
          final isNewlyInserted = state.newlyInsertedItemId == item.id;

          Widget card = Dismissible(
            key: Key('dismiss_special_${item.id}'),
            direction:
                canEdit ? DismissDirection.endToStart : DismissDirection.none,
            dismissThresholds: const {
              DismissDirection.endToStart: 0.4,
            },
            confirmDismiss: (_) => _confirmDeleteSpecialItem(item),
            movementDuration: AppDurations.medium,
            background: const SizedBox.shrink(),
            secondaryBackground: _buildDeleteBackground(),
            child: SpecialItemCard(
              item: item,
              index: index,
              isDraggable: canEdit,
              onTap: canEdit ? () => _handleEditSpecialItem(item) : null,
              onDelete: canEdit ? () => _handleDeleteSpecialItem(item) : null,
            ),
          );

          // Entry animation for newly inserted items
          if (isNewlyInserted) {
            card = _SlideInEntry(
              onComplete: () => ref
                  .read(setlistDetailProvider.notifier)
                  .clearNewlyInsertedItemId(),
              child: card,
            );
          }

          return Padding(
            key: ValueKey(item.listKey),
            padding: const EdgeInsets.only(bottom: Spacing.space12),
            child: card,
          );
        }

        // Song item — delegate to ReorderableSongCard
        final song = item.song!;
        return Padding(
          key: ValueKey(item.listKey),
          padding: const EdgeInsets.only(bottom: Spacing.space12),
          child: Dismissible(
            key: Key('dismiss_song_${song.id}'),
            direction:
                canEdit ? DismissDirection.horizontal : DismissDirection.none,
            dismissThresholds: const {
              DismissDirection.endToStart: 0.4,
              DismissDirection.startToEnd: 0.4,
            },
            confirmDismiss: (direction) {
              if (direction == DismissDirection.endToStart) {
                return _confirmDeleteSong(song.id, song.title);
              } else {
                return _handleMoveOrCopySong(song.id, song.title);
              }
            },
            movementDuration: AppDurations.medium,
            background: _buildMoveOrCopyBackground(),
            secondaryBackground: _buildDeleteBackground(),
            child: _buildSongCardWithMenu(
              song: song,
              index: index,
              isDraggable: canEdit,
              canEdit: canEdit,
              sharedWidths: sharedWidths,
            ),
          ),
        );
      }

      // Fallback: songs-only (no items loaded)
      final song = displaySongs[index];
      return Padding(
        key: ValueKey(song.id),
        padding: const EdgeInsets.only(bottom: Spacing.space12),
        child: Dismissible(
          key: Key('dismiss_song_${song.id}'),
          direction:
              canEdit ? DismissDirection.horizontal : DismissDirection.none,
          dismissThresholds: const {
            DismissDirection.endToStart: 0.4,
            DismissDirection.startToEnd: 0.4,
          },
          confirmDismiss: (direction) {
            if (direction == DismissDirection.endToStart) {
              return _confirmDeleteSong(song.id, song.title);
            } else {
              return _handleMoveOrCopySong(song.id, song.title);
            }
          },
          movementDuration: AppDurations.medium,
          background: _buildMoveOrCopyBackground(),
          secondaryBackground: _buildDeleteBackground(),
          child: _buildSongCardWithMenu(
            song: song,
            index: index,
            isDraggable: canEdit,
            canEdit: canEdit,
            sharedWidths: sharedWidths,
          ),
        ),
      );
    }

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
              sliver: canEdit
                  ? SliverReorderableList(
                      itemCount: itemCount,
                      onReorderItem:
                          useItems ? _handleItemReorder : _handleReorder,
                      itemBuilder: itemBuilder,
                      proxyDecorator: (child, index, animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) {
                            final scale =
                                Tween<double>(begin: 1.0, end: 1.02).evaluate(
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
                                shadowColor:
                                    Colors.black.withValues(alpha: 0.3),
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
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        itemBuilder,
                        childCount: itemCount,
                      ),
                    ),
            ),
          );
        },
      ),
    ];
  }

  // ============================================================
  // SELECT MODE BOTTOM ACTIONS
  // Sticky bottom bar with Cancel and Move to setlist button.
  // ============================================================

  Widget _buildSelectModeBottomActions() {
    final hasSelection = _selectedSongIds.isNotEmpty;
    final selectedCount = _selectedSongIds.length;
    final buttonLabel = selectedCount > 0
        ? 'Move to setlist ($selectedCount)'
        : 'Move to setlist';

    return Container(
      padding: EdgeInsets.only(
        left: Spacing.pagePadding,
        right: Spacing.pagePadding,
        top: Spacing.space16,
        bottom: MediaQuery.of(context).padding.bottom + Spacing.space16,
      ),
      decoration: BoxDecoration(
        color: context.colors.background,
        border: Border(
          top: BorderSide(
            color: context.colors.textSecondary.withValues(alpha: 0.2),
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
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),

          const SizedBox(width: Spacing.space12),

          // Move to setlist button (primary, disabled when no selection)
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: hasSelection ? _handleAddToSetlist : null,
              style: FilledButton.styleFrom(
                backgroundColor: hasSelection
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.4),
                disabledBackgroundColor: AppColors.primary.withValues(
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
            color: context.colors.surface,
            border: Border.all(
              // Highlight selected cards with accent border
              color: widget.isSelected
                  ? AppColors.primary
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
            style: TextStyle(
              fontSize: AppFontSizes.subhead,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
              height: 1,
            ),
          ),

          // ================================================
          // 2. DURATION - centered, evenly spaced
          // ================================================
          Text(
            song.formattedDuration,
            style: TextStyle(
              fontSize: AppFontSizes.subhead,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
              height: 1,
            ),
          ),

          // ================================================
          // 3. TUNING - anchors to right edge
          // ================================================
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: AppFontSizes.subhead,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    height: 1,
                  ),
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
// TUNING SORT TOGGLE
// Per-setlist sort mode toggle (non-Catalog only).
//
// Cycles through: Standard → Half-Step → Full-Step → Drop D → Standard
// Displays the current "first tuning" with a down-arrow icon.
// Sort mode is persisted via TuningSortService (SharedPreferences).
// ============================================================================

/// Bottom sheet for selecting Catalog sort mode
class _CatalogSortSheet extends ConsumerWidget {
  final CatalogSortMode currentMode;

  const _CatalogSortSheet({required this.currentMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.pagePadding,
          vertical: Spacing.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text('Sort Catalog', style: AppTextStyles.headline),
            const SizedBox(height: Spacing.space16),

            // Sort options
            ...CatalogSortMode.values.map((mode) {
              final isSelected = mode == currentMode;
              return _SortOption(
                label: mode.label,
                isSelected: isSelected,
                onTap: () {
                  ref.read(setlistDetailProvider.notifier).setSortMode(mode);
                  Navigator.of(context).pop();
                },
              );
            }),

            const SizedBox(height: Spacing.space8),
          ],
        ),
      ),
    );
  }
}

/// Individual sort option tile
class _SortOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SortOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.space16,
          vertical: Spacing.space12,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  color: isSelected
                      ? AppColors.primary
                      : context.colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(AppIcons.check, color: AppColors.primary, size: 20),
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
            border: Border.all(color: AppColors.primary, width: 2),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: AppColors.primary),
              if (widget.label != null) ...[
                const SizedBox(width: 8),
                Text(
                  widget.label!,
                  style: const TextStyle(
                    fontSize: AppFontSizes.subhead,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
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
// TUNING SORT BUTTON
// Cycles through starting tuning groups for non-Catalog setlists.
// Shows a colored badge with the current starting tuning, or a neutral
// "Tuning" label when no sort is active.
// ============================================================================

class _TuningSortButton extends StatelessWidget {
  final String? startingTuningId;
  final VoidCallback onTap;

  const _TuningSortButton({
    required this.startingTuningId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = startingTuningId != null;
    final badgeColor =
        isActive ? tuningBadgeColor(startingTuningId) : AppColors.primary;
    final label = isActive ? tuningShortLabel(startingTuningId) : 'Sort by';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.space12,
          vertical: Spacing.space8,
        ),
        decoration: BoxDecoration(
          color: isActive ? badgeColor : Colors.transparent,
          border: Border.all(
            color: isActive ? badgeColor : AppColors.primary,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sort_rounded,
              size: 16,
              color: isActive
                  ? tuningBadgeTextColor(badgeColor)
                  : AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSizes.subhead,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? tuningBadgeTextColor(badgeColor)
                    : AppColors.primary,
                height: 1,
              ),
            ),
          ],
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

// ============================================================================
// SLIDE-IN ENTRY ANIMATION
// Horizontal slide-in for newly inserted special items.
// Runs once, then calls [onComplete] so the controller can clear the flag.
// ============================================================================

class _SlideInEntry extends StatefulWidget {
  final Widget child;
  final VoidCallback onComplete;

  const _SlideInEntry({required this.child, required this.onComplete});

  @override
  State<_SlideInEntry> createState() => _SlideInEntryState();
}

class _SlideInEntryState extends State<_SlideInEntry>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: AppCurves.slideIn));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward().then((_) {
      if (mounted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: widget.child,
      ),
    );
  }
}

/// Bottom sheet for selecting share output format
class _ShareFormatSheet extends StatelessWidget {
  const _ShareFormatSheet();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 200),
        child: Container(
          padding: EdgeInsets.only(
            left: Spacing.pagePadding,
            right: Spacing.pagePadding,
            top: Spacing.space24,
            bottom: MediaQuery.of(context).viewPadding.bottom + Spacing.space24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text('Share Format', style: AppTextStyles.headline),
              const SizedBox(height: Spacing.space16),

              // Text / Email option
              _ShareFormatOption(
                smallText: 'Share by',
                largeText: 'Text / Email',
                onTap: () => Navigator.of(context).pop(ShareFormat.textEmail),
              ),

              const SizedBox(height: Spacing.space12),

              // Spreadsheet option
              _ShareFormatOption(
                smallText: '4-column',
                largeText: 'Spreadsheet',
                onTap: () => Navigator.of(context).pop(ShareFormat.spreadsheet),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Individual share format option tile
class _ShareFormatOption extends StatelessWidget {
  final String smallText;
  final String largeText;
  final VoidCallback onTap;

  const _ShareFormatOption({
    required this.smallText,
    required this.largeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Spacing.space16),
        decoration: BoxDecoration(
          color: context.colors.surfaceElevated,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              smallText,
              style: AppTextStyles.body.copyWith(
                color: context.colors.textSecondary,
                fontSize: AppFontSizes.caption,
              ),
            ),
            const SizedBox(height: Spacing.space4),
            Text(
              largeText,
              style: AppTextStyles.title3.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
