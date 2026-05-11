import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen video splash screen.
///
/// Plays [_kVideoAsset] at full screen. When the video ends, a right-to-left
/// wipe transition reveals whatever is beneath the splash in the widget tree,
/// then [onComplete] fires so the caller can drop this widget entirely.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _kVideoAsset = 'assets/videos/splash_bandroadie.mp4';
  static const _kWipeDuration = Duration(milliseconds: 600);

  VideoPlayerController? _video;

  late final AnimationController _wipeCtrl;
  late final Animation<double> _wipeProgress; // 0 = full screen, 1 = gone

  bool _videoReady = false;
  bool _wiping = false;
  DateTime? _videoStartTime;

  @override
  void initState() {
    super.initState();

    _wipeCtrl = AnimationController(duration: _kWipeDuration, vsync: this);
    _wipeProgress = CurvedAnimation(
      parent: _wipeCtrl,
      curve: Curves.easeInOut,
    );

    _wipeCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });

    _initVideo();
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

      // Track when video playback started
      _videoStartTime = DateTime.now();

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
    if (v == null || _wiping) return;

    // Don't check for completion if video isn't actually playing
    if (!v.isPlaying) return;

    // Enforce minimum display time (4 seconds) before checking for completion
    // This ensures the full video plays even if position reporting is buggy
    final startTime = _videoStartTime;
    if (startTime != null) {
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed < const Duration(seconds: 4)) {
        return; // Video hasn't been playing long enough yet
      }
    }

    // isCompleted is set by the plugin when playback reaches the end
    if (v.isCompleted) {
      _startWipe();
      return;
    }

    // Belt-and-suspenders: also check position vs duration
    final dur = v.duration;
    final pos = v.position;
    if (dur > Duration.zero && pos >= dur - const Duration(milliseconds: 120)) {
      _startWipe();
    }
  }

  void _startWipe() {
    if (_wiping || !mounted) return;
    _wiping = true;
    _video?.removeListener(_onVideoTick);
    _wipeCtrl.forward();
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    _wipeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Solid black while video initialises — no flash
    if (!_videoReady) {
      return const ColoredBox(color: Colors.black);
    }

    return AnimatedBuilder(
      animation: _wipeProgress,
      builder: (context, child) {
        final progress = _wipeProgress.value;

        if (progress >= 1.0) return const SizedBox.shrink();

        return ClipRect(
          clipper: _RightToLeftWipeClipper(progress),
          child: child,
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

// ---------------------------------------------------------------------------
// Wipe clipper — right-to-left
//
// progress = 0 → full rect (splash covers screen)
// progress = 1 → zero width (splash wiped away, content beneath fully visible)
// ---------------------------------------------------------------------------

class _RightToLeftWipeClipper extends CustomClipper<Rect> {
  const _RightToLeftWipeClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * (1.0 - progress), size.height);

  @override
  bool shouldReclip(_RightToLeftWipeClipper old) => old.progress != progress;
}
