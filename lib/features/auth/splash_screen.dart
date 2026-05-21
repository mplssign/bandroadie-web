import 'package:flutter/material.dart';

/// Full-screen image splash screen.
///
/// Fades in from black → holds → fades out to black → calls [onComplete].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _kImageAsset = 'assets/images/splash.png';
  static const _kFadeInDuration = Duration(milliseconds: 300);
  static const _kHoldDuration = Duration(milliseconds: 1000);
  static const _kFadeOutDuration = Duration(milliseconds: 300);
  static const _kBlackHoldDuration = Duration(milliseconds: 150);

  late final AnimationController _fadeInCtrl;
  late final AnimationController _fadeOutCtrl;
  late final Animation<double> _fadeIn;
  late final Animation<double> _fadeOut;

  bool _completeCalled = false;

  @override
  void initState() {
    super.initState();

    _fadeInCtrl = AnimationController(duration: _kFadeInDuration, vsync: this);
    _fadeOutCtrl = AnimationController(duration: _kFadeOutDuration, vsync: this);

    _fadeIn = CurvedAnimation(parent: _fadeInCtrl, curve: Curves.easeOut);
    _fadeOut = CurvedAnimation(parent: _fadeOutCtrl, curve: Curves.easeIn);

    _fadeOutCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_completeCalled) {
        _completeCalled = true;
        Future.delayed(_kBlackHoldDuration, () {
          if (mounted) widget.onComplete?.call();
        });
      }
    });

    // Sequence: fade in → hold → fade out
    _fadeInCtrl.forward().then((_) {
      Future.delayed(_kHoldDuration, () {
        if (mounted) _fadeOutCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _fadeInCtrl.dispose();
    _fadeOutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_fadeIn, _fadeOut]),
      builder: (context, child) {
        final opacity = _fadeIn.value * (1.0 - _fadeOut.value);
        return ColoredBox(
          color: Colors.black,
          child: Opacity(
            opacity: opacity,
            child: child,
          ),
        );
      },
      child: Image.asset(
        _kImageAsset,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}
