import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/scroll/scroll_blur_notifier.dart';
import '../../../shared/widgets/animated_logo.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../../bands/widgets/band_avatar.dart';

// ============================================================================
// SETLISTS APP BAR
// Figma: height 41px, bg gray-800 #1e293b at 50% opacity, blur 2px
//
// Modes:
// - backOnly = false (default): Shows hamburger menu, BandRoadie title, avatar
// - backOnly = true: Shows only Back button (for setlist screens per design)
//
// GLASS EFFECT:
// Uses GlassSurface with scroll-driven blur (same as HomeAppBar and bottom nav).
// ============================================================================

class SetlistsAppBar extends ConsumerWidget {
  final String bandName;
  final VoidCallback onMenuTap;
  final VoidCallback onAvatarTap;
  final String? bandAvatarColor;
  final String? bandImageUrl;
  final File? localImageFile;

  /// When true, shows only a Back button (no title, no avatar).
  /// Used on setlist list/detail screens per design requirements.
  final bool backOnly;

  /// Custom back callback. Only used when [backOnly] is true.
  final VoidCallback? onBack;

  const SetlistsAppBar({
    super.key,
    required this.bandName,
    required this.onMenuTap,
    required this.onAvatarTap,
    this.bandAvatarColor,
    this.bandImageUrl,
    this.localImageFile,
    this.backOnly = false,
    this.onBack,
  });

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

    // Back-only mode: just show Back button
    if (backOnly) {
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
          ],
        ),
      );
    }

    // Default mode: hamburger + BandRoadie title + avatar
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
          // Hamburger menu icon with 48px tap target for accessibility
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onMenuTap,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Icon(
                  Icons.menu_rounded,
                  color: AppColors.textPrimary,
                  size: 26,
                ),
              ),
            ),
          ),
          const Spacer(),
          // Centered app logo
          const AnimatedBandRoadieLogo(height: 24),
          const Spacer(),
          // Avatar with band image/initials
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAvatarTap,
            child: BandAvatar(
              imageUrl: bandImageUrl,
              localImageFile: localImageFile,
              name: bandName,
              avatarColor: bandAvatarColor,
              size: 36,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
