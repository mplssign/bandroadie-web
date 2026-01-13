import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/scroll/scroll_blur_notifier.dart';
import '../../../shared/widgets/glass_surface.dart';

// ============================================================================
// BACK ONLY APP BAR
// Simple app bar with just a back button, used on setlist screens.
// No BandRoadie title, no band avatar/switcher.
//
// GLASS EFFECT:
// Uses GlassSurface with scroll-driven blur (same as HomeAppBar and bottom nav).
// ============================================================================

class BackOnlyAppBar extends ConsumerWidget {
  /// Optional callback for back button. Defaults to Navigator.pop().
  final VoidCallback? onBack;

  /// Optional loading indicator shown on the right side.
  final bool showLoading;

  const BackOnlyAppBar({super.key, this.onBack, this.showLoading = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch scroll blur for dynamic glass effect
    final scrollBlur = ref.watch(scrollBlurProvider);

    // Dynamic blur: 8 at rest, 18 when scrolled
    final blurSigma = scrollBlur.lerpTo(8.0, 18.0);
    // Dynamic tint: 0.10 at rest, 0.25 when scrolled
    final tintOpacity = scrollBlur.lerpTo(0.10, 0.25);
    // Dynamic edge fade: 0.15 at rest, 0.55 when scrolled
    final edgeFadeStrength = scrollBlur.lerpTo(0.15, 0.55);

    // Get safe area top padding for status bar/notch
    final topSafeArea = MediaQuery.of(context).padding.top;

    return GlassSurface(
      // Total height = app bar content (41px) + safe area top padding
      height: Spacing.appBarHeight + topSafeArea,
      blurSigma: blurSigma,
      tintOpacity: tintOpacity,
      edge: GlassEdge.bottom,
      edgeFadeStrength: edgeFadeStrength,
      padding: EdgeInsets.only(
        left: Spacing.space16,
        right: Spacing.space16,
        // Push content below the status bar/notch
        top: topSafeArea,
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: onBack ?? () => Navigator.of(context).pop(),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 18,
                  color: AppColors.textPrimary,
                ),
                SizedBox(width: 4),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Optional loading indicator
          if (showLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
        ],
      ),
    );
  }
}
