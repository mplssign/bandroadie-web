import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/scroll/scroll_blur_notifier.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../../bands/widgets/band_avatar.dart';

// ============================================================================
// HOME APP BAR
// Figma: height 41px, bg gray-800 #1e293b at 50% opacity, blur 2px
// Hamburger left 16px, avatar right with initials "TC"
//
// GLASS EFFECT:
// Uses GlassSurface with scroll-driven blur (same as bottom nav).
// Blur strength increases as user scrolls down.
// ============================================================================

class HomeAppBar extends ConsumerWidget {
  final String bandName;
  final VoidCallback onMenuTap;
  final VoidCallback onAvatarTap;
  final String? bandAvatarColor; // Tailwind color class e.g. 'bg-red-600'
  final String? bandImageUrl; // Band's uploaded avatar image URL
  final File? localImageFile; // Local file for instant preview during editing

  const HomeAppBar({
    super.key,
    required this.bandName,
    required this.onMenuTap,
    required this.onAvatarTap,
    this.bandAvatarColor,
    this.bandImageUrl,
    this.localImageFile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch scroll blur for dynamic glass effect (same as bottom nav)
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
      edge: GlassEdge.bottom, // Shadow at bottom edge (content scrolls below)
      edgeFadeStrength: edgeFadeStrength,
      padding: EdgeInsets.only(
        left: Spacing.space16,
        right: Spacing.space16,
        // Push content below the status bar/notch
        top: topSafeArea,
      ),
      child: Row(
        children: [
          // Hamburger menu icon
          GestureDetector(
            onTap: onMenuTap,
            child: const Icon(
              Icons.menu_rounded,
              color: AppColors.textPrimary,
              size: 20.5,
            ),
          ),
          const Spacer(),
          // Centered app logo
          Image.asset('assets/images/bandroadie_horiz.png', height: 30),
          const Spacer(),
          // Avatar with band image/initials - opens band switcher
          GestureDetector(
            onTap: onAvatarTap,
            child: BandAvatar(
              imageUrl: bandImageUrl,
              localImageFile: localImageFile,
              name: bandName,
              avatarColor: bandAvatarColor,
              size: 32,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
