import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../shared/scroll/scroll_blur_notifier.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../../bands/widgets/band_avatar.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// CALENDAR APP BAR
// Figma: height 41px, bg gray-800 #1e293b at 50% opacity, blur 2px
// Hamburger left 16px, avatar right with band initials
//
// GLASS EFFECT:
// Uses GlassSurface with scroll-driven blur (same as HomeAppBar and bottom nav).
// ============================================================================

class CalendarAppBar extends ConsumerWidget {
  final String bandName;
  final VoidCallback onMenuTap;
  final VoidCallback onAvatarTap;
  final String? bandAvatarColor;
  final String? bandImageUrl;
  final File? localImageFile;

  const CalendarAppBar({
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
                    color: context.colors.textPrimary,
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
                  color: const Color(0xFF334155),
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
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
