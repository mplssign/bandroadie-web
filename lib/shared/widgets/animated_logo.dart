import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Animated Band Roadie logo with subtle gradient shimmer effect.
/// 
/// Uses the existing gradient colors (#46c4da cyan, #fdec00 yellow, #ca4f9d pink)
/// with a slow, App Store-safe animation that creates a gentle glow pulse.
class AnimatedBandRoadieLogo extends StatefulWidget {
  const AnimatedBandRoadieLogo({
    super.key,
    this.height = 80,
    this.animate = true,
  });

  /// The height of the logo. Width scales proportionally.
  final double height;

  /// Whether to animate the logo. Set to false for reduced motion.
  final bool animate;

  @override
  State<AnimatedBandRoadieLogo> createState() => _AnimatedBandRoadieLogoState();
}

class _AnimatedBandRoadieLogoState extends State<AnimatedBandRoadieLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  // Brand colors from the logo gradient
  static const Color _cyan = Color(0xFF46C4DA);
  // ignore: unused_field - reserved for future gradient animation
  static const Color _pink = Color(0xFFCA4F9D);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    // Subtle glow pulse: 0.0 -> 0.3 -> 0.0
    _glowAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 0.25)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.25, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(_controller);

    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedBandRoadieLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final shouldAnimate = widget.animate && !reduceMotion;

    if (!shouldAnimate) {
      return _buildStaticLogo();
    }

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            boxShadow: [
              // Soft cyan glow
              BoxShadow(
                color: _cyan.withValues(alpha: _glowAnimation.value * 0.4),
                blurRadius: 20 + (_glowAnimation.value * 15),
                spreadRadius: _glowAnimation.value * 3,
              ),
              // Subtle pink accent glow
              BoxShadow(
                color: _pink.withValues(alpha: _glowAnimation.value * 0.2),
                blurRadius: 15 + (_glowAnimation.value * 10),
                spreadRadius: _glowAnimation.value * 2,
                offset: const Offset(5, 0),
              ),
            ],
          ),
          child: child,
        );
      },
      child: _buildStaticLogo(),
    );
  }

  Widget _buildStaticLogo() {
    return SvgPicture.asset(
      'assets/images/bandroadie_logo_optimized.svg',
      height: widget.height,
      fit: BoxFit.contain,
      semanticsLabel: 'Band Roadie Logo',
      placeholderBuilder: (context) => Image.asset(
        'assets/images/bandroadie_horiz.png',
        height: widget.height,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Static version of the logo for use without animation.
/// Falls back to PNG if SVG fails to load.
class BandRoadieLogo extends StatelessWidget {
  const BandRoadieLogo({
    super.key,
    this.height = 80,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/bandroadie_logo_optimized.svg',
      height: height,
      fit: BoxFit.contain,
      semanticsLabel: 'Band Roadie Logo',
      placeholderBuilder: (context) => Image.asset(
        'assets/images/bandroadie_horiz.png',
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }
}
