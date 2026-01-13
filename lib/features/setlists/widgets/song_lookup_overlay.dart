import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../songs/external_song_lookup_service.dart';
import '../models/song.dart';
import '../setlist_repository.dart';

// ============================================================================
// SONG LOOKUP OVERLAY
// Full-screen modal overlay for searching and adding songs to a setlist.
//
// FEATURES:
// - Search field with auto-focus and clear button
// - Live results with debounced typing (250ms)
// - Result rows: artwork | (title + duration) / (artist + BPM)
// - Tap to add song and close overlay
//
// DESIGN: Matches Figma vibe + BandRoadie dark theme
// ============================================================================

/// Shows the song lookup overlay as a full-screen modal.
///
/// [bandId] - The band to search songs from
/// [setlistId] - The setlist to add songs to
/// [onSongAdded] - Callback when a song is added, returns AddSongResult
Future<void> showSongLookupOverlay({
  required BuildContext context,
  required String bandId,
  required String setlistId,
  required Future<AddSongResult> Function(
    String songId,
    String title,
    String artist,
  )
  onSongAdded,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return SongLookupOverlay(
        bandId: bandId,
        setlistId: setlistId,
        onSongAdded: onSongAdded,
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

class SongLookupOverlay extends ConsumerStatefulWidget {
  final String bandId;
  final String setlistId;
  final Future<AddSongResult> Function(
    String songId,
    String title,
    String artist,
  )
  onSongAdded;

  const SongLookupOverlay({
    super.key,
    required this.bandId,
    required this.setlistId,
    required this.onSongAdded,
  });

  @override
  ConsumerState<SongLookupOverlay> createState() => _SongLookupOverlayState();
}

class _SongLookupOverlayState extends ConsumerState<SongLookupOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late final ExternalSongLookupService _externalService;

  List<Song> _allSongs = [];
  List<Song> _filteredSongs = [];
  List<SongLookupResult> _externalResults = [];
  bool _isLoading = true;
  bool _isAdding = false;
  bool _isSearchingExternal = false;
  String? _error;
  String? _externalError;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _externalService = ExternalSongLookupService(Supabase.instance.client);
    _loadSongs();

    // Auto-focus the search field after the overlay animation completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _searchFocus.requestFocus();
        }
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSongs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repository = ref.read(setlistRepositoryProvider);
      final songs = await repository.fetchSongsForBand(widget.bandId);
      if (mounted) {
        setState(() {
          _allSongs = songs;
          _filteredSongs = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load songs';
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _filterSongs(query);
      _searchExternal(query);
    });
  }

  void _filterSongs(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredSongs = [];
      });
      return;
    }

    final lowerQuery = query.toLowerCase();
    final filtered = _allSongs.where((song) {
      return song.title.toLowerCase().contains(lowerQuery) ||
          song.artist.toLowerCase().contains(lowerQuery);
    }).toList();

    setState(() {
      _filteredSongs = filtered;
    });
  }

  Future<void> _searchExternal(String query) async {
    if (query.isEmpty || query.length < 3) {
      setState(() {
        _externalResults = [];
        _isSearchingExternal = false;
        _externalError = null;
      });
      return;
    }

    setState(() {
      _isSearchingExternal = true;
      _externalError = null;
    });

    try {
      final results = await _externalService.searchExternalSongs(query);

      // Filter out songs that are already in the catalog results
      final catalogKeys = _filteredSongs
          .map((s) => '${s.title.toLowerCase()}|${s.artist.toLowerCase()}')
          .toSet();

      final filtered = results.where((result) {
        final key =
            '${result.title.toLowerCase()}|${result.artist.toLowerCase()}';
        return !catalogKeys.contains(key);
      }).toList();

      if (mounted) {
        setState(() {
          _externalResults = filtered;
          _isSearchingExternal = false;
        });
      }
    } catch (e) {
      debugPrint('[SongLookup] External search error: $e');
      if (mounted) {
        setState(() {
          _externalResults = [];
          _isSearchingExternal = false;
          _externalError = e.toString();
        });
      }
    }
  }

  Future<void> _handleSongTap(Song song) async {
    if (_isAdding) return;

    setState(() {
      _isAdding = true;
    });

    final result = await widget.onSongAdded(song.id, song.title, song.artist);

    if (mounted) {
      if (result.success) {
        Navigator.of(context).pop();
        showAppSnackBar(context, message: result.friendlyMessage);
      } else {
        setState(() {
          _isAdding = false;
        });
        showErrorSnackBar(
          context,
          message: 'Failed to add song. Please try again.',
        );
      }
    }
  }

  Future<void> _handleExternalSongTap(SongLookupResult result) async {
    if (_isAdding) return;

    setState(() {
      _isAdding = true;
    });

    try {
      // Upsert the external song to the catalog
      final repo = ref.read(setlistRepositoryProvider);
      final songId = await repo.upsertExternalSong(
        bandId: widget.bandId,
        title: result.title,
        artist: result.artist,
        durationSeconds: result.durationSeconds,
        spotifyId: result.spotifyId,
        musicbrainzId: result.musicbrainzId,
      );

      if (songId == null) {
        throw Exception('Failed to create song in catalog');
      }

      // Now add it to the setlist (ensures Catalog guarantee)
      final addResult = await widget.onSongAdded(
        songId,
        result.title,
        result.artist,
      );

      if (mounted) {
        if (addResult.success) {
          Navigator.of(context).pop();
          showAppSnackBar(context, message: addResult.friendlyMessage);
        } else {
          setState(() {
            _isAdding = false;
          });
          showErrorSnackBar(
            context,
            message: 'Failed to add song. Please try again.',
          );
        }
      }
    } catch (e) {
      debugPrint('[SongLookup] External song upsert error: $e');
      if (mounted) {
        setState(() {
          _isAdding = false;
        });
        showErrorSnackBar(context, message: 'Failed to add song: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(Spacing.space16),
          decoration: BoxDecoration(
            color: AppColors.scaffoldBg,
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            border: Border.all(color: AppColors.borderMuted, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            child: Column(
              children: [
                _buildHeader(),
                _buildSearchField(),
                const Divider(color: AppColors.borderMuted, height: 1),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.space16),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.arrow_back_ios_rounded,
                size: 20,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          const SizedBox(width: Spacing.space8),

          // Title
          Expanded(
            child: Text(
              'Song Lookup',
              style: AppTextStyles.title3.copyWith(fontSize: 18),
            ),
          ),

          // Close button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
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

  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space12,
      ),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2C),
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          border: Border.all(color: AppColors.borderMuted, width: 1),
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          autofocus: true,
          onChanged: _onSearchChanged,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Search songs or artists',
            hintStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 22,
              color: AppColors.textMuted,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _filterSongs('');
                      setState(() {});
                    },
                    child: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_searchController.text.isEmpty) {
      return _buildEmptyQueryState();
    }

    // Show no results only if both catalog and external are empty and not searching
    if (_filteredSongs.isEmpty &&
        _externalResults.isEmpty &&
        !_isSearchingExternal) {
      return _buildNoResultsState();
    }

    return _buildResultsList();
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.space16),
      itemCount: 6,
      itemBuilder: (context, index) => _buildSkeletonRow(),
    );
  }

  Widget _buildSkeletonRow() {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.space12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
      ),
      child: Row(
        children: [
          // Artwork skeleton
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3A),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
          // Text skeleton
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 160,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A3A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 100,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A3A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: Spacing.space16),
          Text(
            _error ?? 'Something went wrong',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: Spacing.space16),
          GestureDetector(
            onTap: _loadSongs,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.space20,
                vertical: Spacing.space10,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 1.5),
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              child: Text(
                'Retry',
                style: AppTextStyles.button.copyWith(color: AppColors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyQueryState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 56,
              color: AppColors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: Spacing.space16),
            Text(
              'Start typing. Your drummer will still be late.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_off_rounded,
              size: 56,
              color: AppColors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: Spacing.space16),
            Text(
              'No matching songs.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    final hasCatalogResults = _filteredSongs.isNotEmpty;
    final hasExternalResults = _externalResults.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(Spacing.space16),
      physics: const BouncingScrollPhysics(),
      children: [
        // Catalog section
        if (hasCatalogResults) ...[
          _buildSectionHeader('In Catalog', Icons.library_music_rounded),
          ...(_filteredSongs.map(
            (song) => _SongResultRow(
              song: song,
              onTap: () => _handleSongTap(song),
              isAdding: _isAdding,
            ),
          )),
        ],

        // External results section
        if (_isSearchingExternal)
          Padding(
            padding: const EdgeInsets.all(Spacing.space16),
            child: Center(
              child: Column(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Searching...',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          )
        else if (hasExternalResults) ...[
          if (hasCatalogResults) const SizedBox(height: Spacing.space12),
          _buildSectionHeader('External Results', Icons.cloud_rounded),
          ...(_externalResults.map(
            (result) => _ExternalSongRow(
              result: result,
              onTap: () => _handleExternalSongTap(result),
              isAdding: _isAdding,
            ),
          )),
        ],

        // External error display
        if (_externalError != null && !_isSearchingExternal)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: AppColors.error, size: 16),
                const SizedBox(width: 8),
                Text(
                  'External search failed',
                  style: TextStyle(fontSize: 13, color: AppColors.error),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _searchExternal(_searchController.text),
                  child: Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.only(bottom: Spacing.space8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SONG RESULT ROW
// Individual result row with artwork, title, duration, artist, BPM
// ============================================================================

class _SongResultRow extends StatefulWidget {
  final Song song;
  final VoidCallback onTap;
  final bool isAdding;

  const _SongResultRow({
    required this.song,
    required this.onTap,
    this.isAdding = false,
  });

  @override
  State<_SongResultRow> createState() => _SongResultRowState();
}

class _SongResultRowState extends State<_SongResultRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
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
      onTapDown: widget.isAdding ? null : _handleTapDown,
      onTapUp: widget.isAdding ? null : _handleTapUp,
      onTapCancel: widget.isAdding ? null : _handleTapCancel,
      onTap: widget.isAdding ? null : widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: Spacing.space12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(
              color: AppColors.borderMuted.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Opacity(
            opacity: widget.isAdding ? 0.5 : 1.0,
            child: Row(
              children: [
                // Album artwork
                _buildArtwork(),
                const SizedBox(width: 12),

                // Title + Artist + Metrics
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: Title + Duration
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.song.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.song.formattedDuration,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Bottom row: Artist + BPM
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.song.artist,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.song.formattedBpm,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtwork() {
    const size = 52.0;
    final artwork = widget.song.albumArtwork;

    if (artwork != null && artwork.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          artwork,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(size),
        ),
      );
    }

    return _buildPlaceholder(size);
  }

  Widget _buildPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accentMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        size: 24,
        color: AppColors.accent,
      ),
    );
  }
}

// ============================================================================
// EXTERNAL SONG RESULT ROW
// Result row for songs from Spotify/MusicBrainz with source badge
// ============================================================================

class _ExternalSongRow extends StatefulWidget {
  final SongLookupResult result;
  final VoidCallback onTap;
  final bool isAdding;

  const _ExternalSongRow({
    required this.result,
    required this.onTap,
    this.isAdding = false,
  });

  @override
  State<_ExternalSongRow> createState() => _ExternalSongRowState();
}

class _ExternalSongRowState extends State<_ExternalSongRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
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
      onTapDown: widget.isAdding ? null : _handleTapDown,
      onTapUp: widget.isAdding ? null : _handleTapUp,
      onTapCancel: widget.isAdding ? null : _handleTapCancel,
      onTap: widget.isAdding ? null : widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: Spacing.space12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(color: AppColors.borderMuted, width: 1),
          ),
          child: Opacity(
            opacity: widget.isAdding ? 0.5 : 1.0,
            child: Row(
              children: [
                // Album artwork or placeholder icon
                _buildAlbumArtwork(),
                const SizedBox(width: 12),

                // Title + Artist + Metrics
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: Title + Duration
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.result.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (widget.result.durationSeconds != null &&
                              widget.result.durationSeconds! > 0)
                            Text(
                              _formatDuration(widget.result.durationSeconds!),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Bottom row: Artist + BPM
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.result.artist,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.result.bpm != null &&
                              widget.result.bpm! > 0) ...<Widget>[
                            const SizedBox(width: 8),
                            Text(
                              '${widget.result.bpm} BPM',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumArtwork() {
    const size = 52.0;

    // Show album artwork if available
    if (widget.result.albumArtwork != null &&
        widget.result.albumArtwork!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          widget.result.albumArtwork!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholderIcon(),
        ),
      );
    }

    return _buildPlaceholderIcon();
  }

  Widget _buildPlaceholderIcon() {
    const size = 52.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        size: 24,
        color: AppColors.textMuted,
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
