import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/design_tokens.dart';

// ============================================================================
// RESTRICTED TAB CONTENT
// Shown when a contributor navigates to a tab they don't have access to.
// Displays a white heading message above a VIP-only graphic that zooms in
// and gently pulsates.
//
// Asset: assets/images/vip_only.svg
// ============================================================================

class RestrictedTabContent extends StatefulWidget {
  final String featureName;

  const RestrictedTabContent({
    super.key,
    required this.featureName,
  });

  @override
  State<RestrictedTabContent> createState() => _RestrictedTabContentState();
}

class _RestrictedTabContentState extends State<RestrictedTabContent>
    with TickerProviderStateMixin {
  late final AnimationController _zoomController;
  late final AnimationController _pulseController;
  late final Animation<double> _zoomAnimation;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Zoom-in: scales from 0 → 1 once over 600ms
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _zoomAnimation = CurvedAnimation(
      parent: _zoomController,
      curve: Curves.easeOutBack,
    );

    // Gentle pulsate: scales between 1.0 and 1.05 forever
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start zoom, then begin pulsating once zoom finishes
    _zoomController.forward().then((_) {
      if (mounted) _pulseController.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _zoomController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.scaffoldBg,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.space32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Primary message — white, large heading
                  Text(
                    'You don\'t have access to this page.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.displayLarge.copyWith(
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: Spacing.space12),

                  Text(
                    'Try asking the band admin for a backstage pass.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.displayMedium.copyWith(
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: Spacing.space40),

                  // VIP-only graphic — zooms in then gently pulsates
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _zoomAnimation,
                      _pulseAnimation,
                    ]),
                    builder: (context, child) {
                      final scale =
                          _zoomAnimation.value * _pulseAnimation.value;
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: SvgPicture.asset(
                      'assets/images/vip_only.svg',
                      height: 210,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
