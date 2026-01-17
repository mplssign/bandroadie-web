import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Band Roadie logo widget.
///
/// Displays the logo at full opacity with no effects.
class AnimatedBandRoadieLogo extends StatelessWidget {
  const AnimatedBandRoadieLogo({
    super.key,
    this.height = 80,
    this.animate = true, // Kept for API compatibility, but ignored
  });

  /// The height of the logo. Width scales proportionally.
  final double height;

  /// Kept for API compatibility, but currently ignored (no animation).
  final bool animate;

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

/// Static version of the logo for use without animation.
/// Falls back to PNG if SVG fails to load.
class BandRoadieLogo extends StatelessWidget {
  const BandRoadieLogo({super.key, this.height = 80});

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
