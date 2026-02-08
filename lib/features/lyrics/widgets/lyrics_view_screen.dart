import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/lyrics_data.dart';
import '../services/lyrics_view_settings_service.dart';

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
  required LyricsData lyrics,
  required String songId,
  required String songTitle,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, _, _) => _LyricsViewScreen(
        lyrics: lyrics,
        songId: songId,
        songTitle: songTitle,
      ),
      transitionsBuilder: (_, animation, _, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(
            position:
                Tween<Offset>(
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
  final LyricsData lyrics;
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
      backgroundColor: AppColors.scaffoldBg,
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
              AppColors.scaffoldBg,
              AppColors.scaffoldBg.withValues(alpha: 0.85),
              AppColors.scaffoldBg.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: AppColors.textPrimary,
                size: 20,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                widget.songTitle,
                style: AppTextStyles.headline.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Font size controls
            IconButton(
              icon: const Icon(
                Icons.text_decrease,
                color: AppColors.textSecondary,
                size: 20,
              ),
              onPressed: () => _changeFontSize(-2),
            ),
            IconButton(
              icon: const Icon(
                Icons.text_increase,
                color: AppColors.textSecondary,
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
    // Speed controls appear automatically when auto-scrolling
    final showSpeedControls = _isAutoScrolling && _toolbarVisible;

    return Positioned(
      right: 16,
      bottom: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Speed controls (visible while auto-scrolling) ──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: showSpeedControls
                ? Column(
                    key: const ValueKey('speed-controls'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _miniSpeedButton(
                        icon: Icons.add,
                        onTap: () => _changeScrollSpeed(10),
                      ),
                      const SizedBox(height: 8),
                      _miniSpeedButton(
                        icon: Icons.remove,
                        onTap: () => _changeScrollSpeed(-10),
                      ),
                      const SizedBox(height: 12),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('speed-hidden')),
          ),

          // ── Primary FAB ──
          GestureDetector(
            onTap: _toggleAutoScroll,
            child: Opacity(
              opacity: 0.45,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _isAutoScrolling
                      ? AppColors.accent
                      : AppColors.surfaceDark,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isAutoScrolling
                        ? AppColors.accent
                        : AppColors.borderMuted,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _isAutoScrolling
                          ? AppColors.accent.withValues(alpha: 0.35)
                          : Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _isAutoScrolling ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniSpeedButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: 0.7,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.borderMuted),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 18),
        ),
      ),
    );
  }

  // ── Lyrics content ────────────────────────────────────────────────────────

  Widget _buildLyricsContent() {
    if (widget.lyrics.isEmpty) {
      return Center(
        child: Text(
          'No lyrics added yet.',
          style: AppTextStyles.callout.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(
        top: 72,
        bottom: 120,
        left: Spacing.pagePadding,
        right: Spacing.pagePadding,
      ),
      itemCount: widget.lyrics.blocks.length,
      itemBuilder: (_, index) => _buildBlock(widget.lyrics.blocks[index]),
    );
  }

  Widget _buildBlock(LyricsBlock block) {
    final fontSize = _settingsLoaded ? _settings.fontSize : block.fontSize;

    final textWidget = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        block.text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: block.highlight != LyricsHighlight.none
              ? Color(block.highlight.accentColorValue)
              : AppColors.textPrimary,
          fontSize: fontSize,
          fontWeight: block.isBold ? FontWeight.bold : FontWeight.normal,
          height: 1.7,
        ),
      ),
    );

    if (block.highlight != LyricsHighlight.none) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Color(block.highlight.colorValue),
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          border: Border.all(
            color: Color(
              block.highlight.accentColorValue,
            ).withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          children: [
            // Section label
            Text(
              block.highlight.label.toUpperCase(),
              style: AppTextStyles.footnote.copyWith(
                color: Color(
                  block.highlight.accentColorValue,
                ).withValues(alpha: 0.7),
                fontSize: 10,
                letterSpacing: 1.4,
              ),
            ),
            textWidget,
          ],
        ),
      );
    }

    return textWidget;
  }
}
