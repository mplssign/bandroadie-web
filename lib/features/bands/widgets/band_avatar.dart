import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/models/band.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/utils/initials.dart';

// ============================================================================
// BAND AVATAR WIDGET
// Reusable avatar widget that shows either:
// - The band's uploaded image (if available)
// - Initials derived from band name (fallback)
//
// Background color uses the band's avatarColor (Tailwind class mapped to Color).
// Used by: HomeAppBar, BandSwitcher, Create/Edit Band screens
// ============================================================================

/// Map Tailwind color classes to Flutter Colors
const Map<String, Color> avatarColorMap = {
  'bg-rose-500': Color(0xFFF43F5E),
  'bg-red-600': Color(0xFFDC2626),
  'bg-orange-600': Color(0xFFEA580C),
  'bg-amber-600': Color(0xFFD97706),
  'bg-yellow-500': Color(0xFFEAB308),
  'bg-yellow-600': Color(0xFFCA8A04),
  'bg-lime-500': Color(0xFF84CC16),
  'bg-lime-600': Color(0xFF65A30D),
  'bg-green-500': Color(0xFF22C55E),
  'bg-green-600': Color(0xFF16A34A),
  'bg-emerald-500': Color(0xFF10B981),
  'bg-emerald-600': Color(0xFF059669),
  'bg-teal-500': Color(0xFF14B8A6),
  'bg-teal-600': Color(0xFF0D9488),
  'bg-cyan-500': Color(0xFF06B6D4),
  'bg-cyan-600': Color(0xFF0891B2),
  'bg-sky-500': Color(0xFF0EA5E9),
  'bg-sky-600': Color(0xFF0284C7),
  'bg-blue-600': Color(0xFF2563EB),
  'bg-indigo-600': Color(0xFF4F46E5),
  'bg-violet-600': Color(0xFF7C3AED),
  'bg-purple-600': Color(0xFF9333EA),
  'bg-fuchsia-600': Color(0xFFC026D3),
  'bg-pink-600': Color(0xFFDB2777),
  'bg-rose-600': Color(0xFFE11D48),
};

/// Get Flutter Color from Tailwind class string
Color getAvatarColor(String? tailwindClass) {
  return avatarColorMap[tailwindClass] ?? AppColors.accent;
}

class BandAvatar extends StatelessWidget {
  /// The band's image URL (if uploaded)
  final String? imageUrl;

  /// Local file for instant preview (before upload completes)
  final File? localImageFile;

  /// The band's name (used to derive initials if no image)
  final String? name;

  /// The band's avatar color (Tailwind class, e.g. 'bg-rose-500')
  final String? avatarColor;

  /// The diameter of the avatar circle
  final double size;

  /// Font size for initials (if null, auto-calculated based on size)
  final double? fontSize;

  const BandAvatar({
    super.key,
    this.imageUrl,
    this.localImageFile,
    this.name,
    this.avatarColor,
    this.size = 32,
    this.fontSize,
  });

  /// Factory constructor that takes a Band object directly
  factory BandAvatar.fromBand(
    Band band, {
    Key? key,
    double size = 32,
    double? fontSize,
    File? localImageFile,
  }) {
    return BandAvatar(
      key: key,
      imageUrl: band.imageUrl,
      localImageFile: localImageFile,
      name: band.name,
      avatarColor: band.avatarColor,
      size: size,
      fontSize: fontSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = getAvatarColor(avatarColor);
    // Use shared initials utility for consistency across app
    // No maxLetters limit - FittedBox handles scaling for long initials
    final initials = bandInitials(name);
    final hasLocalImage = localImageFile != null;
    final hasNetworkImage = imageUrl != null && imageUrl!.isNotEmpty;
    final textSize = fontSize ?? (size * 0.44);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: hasLocalImage
          ? Image.file(
              localImageFile!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (context, error, stackTrace) {
                return _buildInitials(initials, textSize);
              },
            )
          : hasNetworkImage
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (context, error, stackTrace) {
                return _buildInitials(initials, textSize);
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return _buildInitials(initials, textSize);
              },
            )
          : _buildInitials(initials, textSize),
    );
  }

  Widget _buildInitials(String initials, double textSize) {
    // Use FittedBox to automatically scale down long initials to fit the avatar
    return Center(
      child: Padding(
        padding: EdgeInsets.all(size * 0.12), // ~12% padding for breathing room
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            initials,
            style: TextStyle(
              color: Colors.white,
              fontSize: textSize,
              fontWeight: FontWeight.w600,
              decoration:
                  TextDecoration.none, // Ensure no underline on initials
            ),
          ),
        ),
      ),
    );
  }
}
