import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/scroll/scroll_blur_notifier.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../../bands/widgets/band_avatar.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

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
    // Dynamic tint: 0.85 at rest, 0.95 when scrolled (higher opacity for visibility in light mode)
    final tintOpacity = scrollBlur.lerpTo(0.85, 0.95);
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.back,
                    size: 18,
                    color: Colors.white,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Back',
                    style: TextStyle(
                      fontSize: AppFontSizes.body,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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

    // Default mode: hamburger + active band name + avatar
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
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onMenuTap,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Icon(
                    AppIcons.menu,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final baseStyle = AppTextStyles.title3.copyWith(
                  color: const Color(0xFFD1D5DB),
                  letterSpacing: -0.5,
                );
                final painter = TextPainter(
                  text: TextSpan(
                    text: bandName.toUpperCase(),
                    style: baseStyle,
                  ),
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                )..layout();

                final fits = painter.width <= constraints.maxWidth;
                double fontSize = 20;
                if (!fits) {
                  final scaleFactor = constraints.maxWidth / painter.width;
                  fontSize = max(13, 20 * scaleFactor);
                }

                return Text(
                  bandName.toUpperCase(),
                  style: baseStyle.copyWith(fontSize: fontSize),
                  textAlign: fits ? TextAlign.center : TextAlign.left,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAvatarTap,
              child: BandAvatar(
                imageUrl: bandImageUrl,
                localImageFile: localImageFile,
                name: bandName,
                avatarColor: bandAvatarColor,
                size: 36,
                fontSize: AppFontSizes.subhead,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
