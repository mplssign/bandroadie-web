import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../services/lyrics_view_settings_service.dart';
import '../services/chordpro_parser.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// LYRICS VIEW SCREEN
// Full-screen, distraction-free, read-only lyrics viewer.
//
// Features:
// - Formatted blocks with section-highlight tint & label
// - Auto-scroll with adjustable speed (persisted per-song)
// - Font-size adjustment (persisted per-song)
// - Floating action button: start/stop + speed ±
// - Manual scroll pauses auto-scroll; FAB resumes it
// - Tap screen to toggle toolbar visibility
// - Compatible with mobile, web, touch & mouse
// ============================================================================

/// Push the lyrics view as a full-screen route.
void showLyricsViewScreen(
  BuildContext context, {
  required String lyrics,
  required String songId,
  required String songTitle,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      pageBuilder: (context, anim1, anim2) => _LyricsViewScreen(
        lyrics: lyrics,
        songId: songId,
        songTitle: songTitle,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: AppCurves.ease),
            ),
            child: child,
          ),
        );
      },
      transitionDuration: AppDurations.medium,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class _LyricsViewScreen extends StatefulWidget {
  final String lyrics;
  final String songId;
  final String songTitle;

  const _LyricsViewScreen({
    required this.lyrics,
    required this.songId,
    required this.songTitle,
  });

  @override
  State<_LyricsViewScreen> createState() => _LyricsViewScreenState();
}

class _LyricsViewScreenState extends State<_LyricsViewScreen> {
  late ScrollController _scrollController;
  late LyricsViewSettings _settings;

  bool _settingsLoaded = false;
  bool _toolbarVisible = true;
  bool _isAutoScrolling = false;
  bool _chordsVisible = true;

  Timer? _autoScrollTimer;
  Timer? _toolbarHideTimer;

  // Track manual scroll to pause auto-scroll
  bool _userScrolling = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _settings = const LyricsViewSettings();
    _loadSettings();
    _loadChordsVisible();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _toolbarHideTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final loaded = await LyricsViewSettingsService.load(widget.songId);
    if (!mounted) return;
    setState(() {
      _settings = loaded;
      _settingsLoaded = true;
    });
  }

  Future<void> _saveSettings() async {
    await LyricsViewSettingsService.save(widget.songId, _settings);
  }

  Future<void> _loadChordsVisible() async {
    final visible = await LyricsViewSettingsService.loadChordsVisible();
    if (!mounted) return;
    setState(() => _chordsVisible = visible);
  }

  Future<void> _saveChordsVisible(bool visible) async {
    await LyricsViewSettingsService.saveChordsVisible(visible);
  }

  // ── Auto-Scroll ───────────────────────────────────────────────────────────

  void _startAutoScroll() {
    _stopAutoScroll();
    setState(() => _isAutoScrolling = true);

    // ~60 fps
    const frameDuration = Duration(milliseconds: 16);
    _autoScrollTimer = Timer.periodic(frameDuration, (_) {
      if (!_scrollController.hasClients || _userScrolling) return;

      final max = _scrollController.position.maxScrollExtent;
      final cur = _scrollController.offset;

      if (cur >= max) {
        _stopAutoScroll();
        return;
      }

      final pxPerFrame = _settings.scrollSpeed / 60.0;
      _scrollController.jumpTo(cur + pxPerFrame);
    });

    _scheduleToolbarHide();
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (mounted) setState(() => _isAutoScrolling = false);
  }

  void _toggleAutoScroll() {
    HapticFeedback.lightImpact();
    if (_isAutoScrolling) {
      _stopAutoScroll();
    } else {
      _startAutoScroll();
    }
    _settings = _settings.copyWith(autoScrollEnabled: _isAutoScrolling);
    _saveSettings();
  }

  // ── Toolbar auto-hide ─────────────────────────────────────────────────────

  void _scheduleToolbarHide() {
    _toolbarHideTimer?.cancel();
    if (_isAutoScrolling) {
      _toolbarHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _isAutoScrolling) {
          setState(() {
            _toolbarVisible = false;
          });
        }
      });
    }
  }

  void _onScreenTap() {
    if (!_toolbarVisible) {
      setState(() => _toolbarVisible = true);
      _scheduleToolbarHide();
    } else if (_isAutoScrolling) {
      _stopAutoScroll();
    }
  }

  // ── Font size ─────────────────────────────────────────────────────────────

  void _changeFontSize(double delta) {
    HapticFeedback.selectionClick();
    final newSize = (_settings.fontSize + delta).clamp(12.0, 36.0);
    setState(() => _settings = _settings.copyWith(fontSize: newSize));
    _saveSettings();
  }

  // ── Scroll speed ──────────────────────────────────────────────────────────

  void _changeScrollSpeed(double delta) {
    HapticFeedback.selectionClick();
    final newSpeed = (_settings.scrollSpeed + delta).clamp(10.0, 120.0);
    setState(() => _settings = _settings.copyWith(scrollSpeed: newSpeed));
    _saveSettings();

    // If already scrolling, restart with new speed
    if (_isAutoScrolling) {
      _startAutoScroll();
    }
  }

  // ── Manual scroll detection ───────────────────────────────────────────────

  bool _onScrollNotification(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      // User-initiated drag
      _userScrolling = true;
    } else if (n is ScrollEndNotification) {
      _userScrolling = false;
    }
    return false;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: GestureDetector(
            onTap: _onScreenTap,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                _buildLyricsContent(),
                if (_toolbarVisible) _buildTopBar(),
                _buildScrollFab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              context.colors.background,
              context.colors.background.withValues(alpha: 0.85),
              context.colors.background.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                AppIcons.back,
                color: context.colors.textPrimary,
                size: 20,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                widget.songTitle,
                style: AppTextStyles.headline.copyWith(
                  color: context.colors.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Chords toggle
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Chords',
                  style: AppTextStyles.caption.copyWith(
                    color: context.colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                Switch(
                  value: _chordsVisible,
                  onChanged: (value) {
                    setState(() => _chordsVisible = value);
                    _saveChordsVisible(value);
                  },
                  activeTrackColor: AppColors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(width: 8),
            // Font size controls
            IconButton(
              icon: Icon(
                Icons.text_decrease,
                color: context.colors.textSecondary,
                size: 20,
              ),
              onPressed: () => _changeFontSize(-2),
            ),
            IconButton(
              icon: Icon(
                Icons.text_increase,
                color: context.colors.textSecondary,
                size: 20,
              ),
              onPressed: () => _changeFontSize(2),
            ),
          ],
        ),
      ),
    );
  }

  // ── FAB ────────────────────────────────────────────────────────────────────

  Widget _buildScrollFab() {
    return Positioned(
      right: 16,
      bottom: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Speed controls ──
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _speedButton(
                icon: AppIcons.add,
                onTap: () => _changeScrollSpeed(10),
              ),
              const SizedBox(height: 8),
              _speedButton(
                icon: AppIcons.remove,
                onTap: () => _changeScrollSpeed(-10),
              ),
              const SizedBox(height: 32),
            ],
          ),

          // ── Primary FAB ──
          GestureDetector(
            onTap: _toggleAutoScroll,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _isAutoScrolling
                    ? AppColors.primary.withValues(alpha: 0.65)
                    : context.colors.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isAutoScrolling
                      ? AppColors.primary.withValues(alpha: 0.65)
                      : context.colors.border,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isAutoScrolling
                        ? AppColors.primary.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                _isAutoScrolling ? AppIcons.pause : AppIcons.play,
                color: _isAutoScrolling ? Colors.white : AppColors.primary,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _speedButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.25),
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: Icon(icon, color: AppColors.primary, size: 24),
      ),
    );
  }

  // ── Lyrics content ────────────────────────────────────────────────────────

  Widget _buildLyricsContent() {
    if (widget.lyrics.trim().isEmpty) {
      return Center(
        child: Text(
          'No lyrics added yet.',
          style:
              AppTextStyles.callout.copyWith(color: context.colors.textMuted),
        ),
      );
    }

    final parsedLines = ChordProParser.parse(widget.lyrics);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(
        top: 72,
        bottom: 120,
        left: Spacing.pagePadding,
        right: Spacing.pagePadding,
      ),
      itemCount: parsedLines.length,
      itemBuilder: (_, index) => _buildLyricsLine(parsedLines[index]),
    );
  }

  Widget _buildLyricsLine(ParsedLyricsLine line) {
    final fontSize = _settingsLoaded ? _settings.fontSize : 18.0;

    // Blank line spacing
    if (line.isEmpty) {
      return const SizedBox(height: 16);
    }

    // No chords in this line - render as plain text
    if (line.chords.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          line.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            height: 1.7,
          ),
        ),
      );
    }

    // Line has chords - parse and align
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _buildLineWithChords(line, fontSize),
    );
  }

  /// Build a line with chords aligned above words
  Widget _buildLineWithChords(ParsedLyricsLine line, double fontSize) {
    // Split text into words
    final words = line.text.split(' ');
    final wordWidgets = <Widget>[];

    // Track character position for word alignment
    var charPos = 0;

    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final wordStart = charPos;
      final wordEnd = charPos + word.length;

      // Find chords that apply to this word (nearest at or before word start)
      final wordChords = <String>[];
      for (final chord in line.chords) {
        if (chord.position >= wordStart && chord.position < wordEnd) {
          wordChords.add(chord.chord);
        } else if (chord.position == wordStart && i == 0) {
          // Chord at start of line applies to first word
          wordChords.add(chord.chord);
        }
      }

      // Build word with optional chords above
      wordWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_chordsVisible && wordChords.isNotEmpty)
                Text(
                  wordChords.join('/'),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              Text(
                word,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      );

      // Update character position (word + space)
      charPos = wordEnd + 1;
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 0,
      runSpacing: 4,
      children: wordWidgets,
    );
  }
}
