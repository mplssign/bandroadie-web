import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

/// Community/Support section with Reddit link
class SupportSection extends StatefulWidget {
  const SupportSection({super.key});

  @override
  State<SupportSection> createState() => _SupportSectionState();
}

class _SupportSectionState extends State<SupportSection> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: isMobile ? 40 : 60,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2a1020), // Richer rose
            const Color(0xFF201028), // Richer purple
            const Color(0xFF1a0a1a), // Dark blend
          ],
        ),
      ),
      child: Column(
        children: [
          // Section title
          Text(
            'Join Our Community',
            textAlign: TextAlign.center,
            style: AppTextStyles.title3.copyWith(fontSize: isMobile ? 32 : 40),
          ),
          const SizedBox(height: 16),
          Text(
            'Questions or feedback? We\'re here for you!',
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              fontSize: AppFontSizes.title,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 40),

          // Reddit button
          MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () async {
                final uri = Uri.parse('https://www.reddit.com/r/BandRoadie/');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                transform: Matrix4.translationValues(0, _isHovered ? -2 : 0, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withValues(alpha: 0.85),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            blurRadius: 8,
                            spreadRadius: 0,
                          ),
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      AppIcons.message,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'r/BandRoadie',
                      style: AppTextStyles.headline.copyWith(
                        fontSize: AppFontSizes.title,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
