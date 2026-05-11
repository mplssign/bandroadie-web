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
    );
  }
}

/// Static version of the logo for use without animation.
/// Provide [width] to size by width (height scales proportionally),
/// or [height] to size by height. If both are null, defaults to height 80.
class BandRoadieLogo extends StatelessWidget {
  const BandRoadieLogo({
    super.key,
    this.height,
    this.width,
    this.asset = 'assets/images/bandroadie_logo_optimized.svg',
  });

  final double? height;
  final double? width;

  /// Asset path for the SVG logo. Defaults to the standard b&w optimized logo.
  /// Pass a different path to use a logo variant (e.g. rose+tag on the login screen).
  final String asset;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      height: height ?? (width == null ? 80 : null),
      width: width,
      fit: BoxFit.contain,
      semanticsLabel: 'Band Roadie Logo',
    );
  }
}
