import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/features/setlists/tuning/tuning_helpers.dart';

void main() {
  group('Rose Primary Color Swap Verification', () {
    test('AppColors.primary is #FF2056', () {
      expect(AppColors.primary, equals(const Color(0xFFFF2056)));
    });

    test('BrandColors.dark.primaryDim is #FF2056', () {
      expect(BrandColors.dark.primaryDim, equals(const Color(0xFFFF2056)));
    });

    test('BrandColors.light.primaryDim is #FF2056', () {
      expect(BrandColors.light.primaryDim, equals(const Color(0xFFFF2056)));
    });

    test('Open E tuning color is unchanged (not brand primary)', () {
      final openETuning = tuningBadgeColor('open_e');
      expect(openETuning,
          equals(const Color(0xFFBE123C))); // Must remain old value
    });

    test('Verify no other color constants changed', () {
      // This test verifies that primarySubtle values remain unchanged
      // as specified in the plan (pre-existing drift issue, out of scope)
      expect(BrandColors.dark.primarySubtle, equals(const Color(0x4DF43F5E)));
      expect(BrandColors.light.primarySubtle, equals(const Color(0x1AF43F5E)));
    });
  });
}
