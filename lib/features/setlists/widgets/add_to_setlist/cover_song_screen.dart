import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/utils/snackbar_helper.dart';
import '../../../songs/external_song_lookup_service.dart';
import '../../models/song.dart';
import '../../setlist_repository.dart';

// ============================================================================
// COVER SONG SCREEN
// Reuses existing Spotify Song Lookup functionality exactly as-is.
// Relocated inside the new Add to Setlist flow.
//
// NO CHANGES to: Spotify search logic, result rendering, add-to-setlist logic.
// ============================================================================

class CoverSongScreen extends ConsumerStatefulWidget {
  final String bandId;
  final String setlistId;
  final Future<AddSongResult> Function(
    String songId,
    String title,
    String artist,
  )
  onSongAdded;
  final VoidCallback onClose;

  const CoverSongScreen({
    super.key,
    required this.bandId,
    required this.setlistId,
    required this.onSongAdded,
    required this.onClose,
  });

  @override
  ConsumerState<CoverSongScreen> createState() => _CoverSongScreenState();
}

class _CoverSongScreenState extends ConsumerState<CoverSongScreen>
    with SingleTickerProviderStateMixin {
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

  // Entrance animation
  late AnimationController _entranceController;
  late Animation<double> _searchBarFade;

  @override
  void initState() {
    super.initState();
    _externalService = ExternalSongLookupService(Supabase.instance.client);

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _searchBarFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _loadSongs();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceController.forward();
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _searchFocus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // ── Existing logic (unchanged) ──────────────────────────────────────────

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
      setState(() => _filteredSongs = []);
      return;
    }
    final lowerQuery = query.toLowerCase();
    final filtered = _allSongs.where((song) {
      return song.title.toLowerCase().contains(lowerQuery) ||
          song.artist.toLowerCase().contains(lowerQuery);
    }).toList();
    setState(() => _filteredSongs = filtered);
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
      debugPrint('[CoverSong] External search error: $e');
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

    setState(() => _isAdding = true);

    final result = await widget.onSongAdded(song.id, song.title, song.artist);

    if (mounted) {
      if (result.success) {
        widget.onClose();
        showAppSnackBar(context, message: result.friendlyMessage);
      } else {
        setState(() => _isAdding = false);
        showErrorSnackBar(
          context,
          message: 'Failed to add song. Please try again.',
        );
      }
    }
  }

  Future<void> _handleExternalSongTap(SongLookupResult result) async {
    if (_isAdding) return;

    setState(() => _isAdding = true);

    try {
      final repo = ref.read(setlistRepositoryProvider);
      final songId = await repo.upsertExternalSong(
        bandId: widget.bandId,
        title: result.title,
        artist: result.artist,
        bpm: result.bpm,
        durationSeconds: result.durationSeconds,
        albumArtwork: result.albumArtwork,
        spotifyId: result.spotifyId,
        musicbrainzId: result.musicbrainzId,
      );

      if (songId == null) throw Exception('Failed to create song in catalog');

      final addResult = await widget.onSongAdded(
        songId,
        result.title,
        result.artist,
      );

      if (mounted) {
        if (addResult.success) {
          widget.onClose();
          showAppSnackBar(context, message: addResult.friendlyMessage);
        } else {
          setState(() => _isAdding = false);
          showErrorSnackBar(
            context,
            message: 'Failed to add song. Please try again.',
          );
        }
      }
    } catch (e) {
      debugPrint('[CoverSong] External song upsert error: $e');
      if (mounted) {
        setState(() => _isAdding = false);
        showErrorSnackBar(context, message: 'Failed to add song: $e');
      }
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FadeTransition(opacity: _searchBarFade, child: _buildSearchField()),
        const Divider(color: AppColors.borderMuted, height: 1),
        Expanded(child: _buildBody()),
      ],
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
    if (_isLoading) return _buildLoadingState();
    if (_error != null) return _buildErrorState();
    if (_searchController.text.isEmpty) return _buildEmptyQueryState();
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
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3A),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
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
        if (hasCatalogResults) ...[
          _buildSectionHeader('In Catalog', Icons.library_music_rounded),
          ...(_filteredSongs.map(
            (song) => _CoverSongResultRow(
              title: song.title,
              artist: song.artist,
              formattedDuration: song.formattedDuration,
              formattedBpm: song.formattedBpm,
              albumArtwork: song.albumArtwork,
              onTap: () => _handleSongTap(song),
              isAdding: _isAdding,
            ),
          )),
        ],

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
            (result) => _CoverSongResultRow(
              title: result.title,
              artist: result.artist,
              formattedDuration:
                  result.durationSeconds != null && result.durationSeconds! > 0
                  ? _formatDuration(result.durationSeconds!)
                  : null,
              formattedBpm: result.bpm != null && result.bpm! > 0
                  ? '${result.bpm} BPM'
                  : null,
              albumArtwork: result.albumArtwork,
              onTap: () => _handleExternalSongTap(result),
              isAdding: _isAdding,
            ),
          )),
        ],

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

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// SONG RESULT ROW (shared for both catalog and external results)
// ============================================================================

class _CoverSongResultRow extends StatefulWidget {
  final String title;
  final String artist;
  final String? formattedDuration;
  final String? formattedBpm;
  final String? albumArtwork;
  final VoidCallback onTap;
  final bool isAdding;

  const _CoverSongResultRow({
    required this.title,
    required this.artist,
    this.formattedDuration,
    this.formattedBpm,
    this.albumArtwork,
    required this.onTap,
    this.isAdding = false,
  });

  @override
  State<_CoverSongResultRow> createState() => _CoverSongResultRowState();
}

class _CoverSongResultRowState extends State<_CoverSongResultRow>
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
                _buildArtwork(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.formattedDuration != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              widget.formattedDuration!,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.artist,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.formattedBpm != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              widget.formattedBpm!,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
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

  Widget _buildArtwork() {
    const size = 52.0;
    final artwork = widget.albumArtwork;

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
