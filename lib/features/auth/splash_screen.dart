import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen video splash screen.
///
/// Plays [_kVideoAsset] at full screen. During the last 2 seconds of the video,
/// zooms in and fades to black, then holds briefly before calling [onComplete].
/// The dashboard beneath handles its own entrance animation.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _kVideoAsset = 'assets/videos/splash_bandroadie.mp4';
  static const _kFadeDuration =
      Duration(milliseconds: 1500); // Fade video to black
  static const _kFadeStartBeforeEnd =
      Duration(seconds: 2); // Start fade 2s before video ends
  static const _kBlackHoldDuration =
      Duration(milliseconds: 300); // Hold at black before removing splash

  VideoPlayerController? _video;

  late final AnimationController _fadeCtrl;
  late final Animation<double>
      _fadeProgress; // 0 = video visible, 1 = completely faded out

  bool _videoReady = false;
  bool _fading = false;
  bool _completeCalled = false;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(duration: _kFadeDuration, vsync: this);
    _fadeProgress = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeInOut,
    );

    // Remove splash from tree slightly before animation completes to avoid flicker
    _fadeCtrl.addListener(_checkCompletion);

    _initVideo();
  }

  void _checkCompletion() {
    // Call onComplete when animation completes + black hold duration
    if (!_completeCalled && _fadeCtrl.isCompleted) {
      _completeCalled = true;
      // Hold at black briefly before signaling completion
      Future.delayed(_kBlackHoldDuration, () {
        if (mounted) {
          widget.onComplete?.call();
        }
      });
    }
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.asset(_kVideoAsset);

    try {
      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      _video = controller;
      await _video!.setLooping(false);
      await _video!.setVolume(1.0);

      // Ensure video starts from the beginning
      final initialPos = _video!.value.position;
      if (initialPos > Duration.zero) {
        await _video!.seekTo(Duration.zero);
      }

      // Start playback BEFORE adding listener to avoid immediate completion detection
      await _video!.play();

      // Add listener after play() to avoid race condition
      _video!.addListener(_onVideoTick);

      setState(() => _videoReady = true);
    } catch (e) {
      debugPrint('[SplashScreen] ❌ Video init error: $e');
      controller.dispose();
      if (mounted) widget.onComplete?.call();
    }
  }

  void _onVideoTick() {
    final v = _video?.value;
    if (v == null || _fading) return;

    // Don't check for completion if video isn't actually playing
    if (!v.isPlaying) return;

    // Check if we're within 2 seconds of the end - start the fade
    final dur = v.duration;
    final pos = v.position;
    if (dur > Duration.zero && pos >= dur - _kFadeStartBeforeEnd) {
      _startFade();
    }
  }

  void _startFade() {
    if (_fading || !mounted) return;
    _fading = true;
    _video?.removeListener(_onVideoTick);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    _fadeCtrl.removeListener(_checkCompletion);
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Solid black while video initialises — no flash
    if (!_videoReady) {
      return const ColoredBox(color: Colors.black);
    }

    return AnimatedBuilder(
      animation: _fadeProgress,
      builder: (context, child) {
        final progress = _fadeProgress.value;

        // Simple fade: zoom in and fade video to black
        // Stay at black (don't fade to transparent)
        // Dashboard will animate in when splash is removed

        final videoOpacity = 1.0 - progress; // Fade out video (1.0 -> 0.0)

        // Zoom in during fade: scale from 1.0 to 2.5
        final videoScale = 1.0 + (progress * 1.5);

        return ColoredBox(
          color: Colors.black, // Solid black - ensures dashboard is blocked
          child: SizedBox.expand(
            child: videoOpacity > 0
                ? Transform.scale(
                    scale: videoScale,
                    child: Opacity(
                      opacity: videoOpacity,
                      child: child,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
      child: _buildVideoLayer(),
    );
  }

  Widget _buildVideoLayer() {
    final video = _video;
    if (video == null) return const ColoredBox(color: Colors.black);

    // Ensure video is initialized before rendering
    if (!video.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    // Fill screen with video, maintaining aspect ratio with cover fit
    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: video.value.size.width,
            height: video.value.size.height,
            child: VideoPlayer(video),
          ),
        ),
      ),
    );
  }
}
