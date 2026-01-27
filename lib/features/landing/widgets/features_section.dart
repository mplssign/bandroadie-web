import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';

/// Features grid section showcasing the 4 main features
class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: isMobile ? 60 : 100,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            AppColors.scaffoldBg,
            const Color(0xFF1a0505),
            const Color(0xFF1a0a00),
          ],
        ),
      ),
      child: Column(
        children: [
          // Section title
          Text(
            'Everything Your Band Needs',
            textAlign: TextAlign.center,
            style: AppTextStyles.title3.copyWith(fontSize: isMobile ? 32 : 40),
          ),
          const SizedBox(height: 16),
          Text(
            'Powerful tools built for real bands',
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              fontSize: 18,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: isMobile ? 40 : 60),

          // Features grid
          LayoutBuilder(
            builder: (context, constraints) {
              // Determine number of columns based on width
              final int columns;
              final double spacing;

              if (constraints.maxWidth < 700) {
                columns = 1;
                spacing = 24.0;
              } else if (constraints.maxWidth < 1200) {
                columns = 2;
                spacing = 24.0;
              } else {
                columns = 4;
                spacing = 32.0;
              }

              final cardWidth =
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _FeatureCard(
                      icon: Icons.headset_rounded,
                      title: 'Rehearsals',
                      description:
                          'Schedule rehearsals, add notes, and keep everyone aligned.',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _FeatureCard(
                      icon: Icons.mic_rounded,
                      title: 'Gigs & Potential Gigs',
                      description:
                          'Track all the details of confirmed & potential shows',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _FeatureCard(
                      icon: Icons.calendar_month_rounded,
                      title: 'Band Calendar',
                      description:
                          'A shared calendar for rehearsals, gigs, setlists, and blackout dates.',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _FeatureCard(
                      icon: Icons.queue_music_rounded,
                      title: 'Setlists',
                      description:
                          'Build setlists with song order, tempo, key, and performance notes.',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.translationValues(0, _isHovered ? -8 : 0, 0),
        constraints: const BoxConstraints(minHeight: 280),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? AppColors.accent.withValues(alpha: 0.4)
                : AppColors.borderMuted,
            width: 1,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, size: 32, color: AppColors.accent),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              widget.title,
              style: AppTextStyles.headline.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              widget.description,
              style: AppTextStyles.callout.copyWith(
                fontFamily: 'Caveat',
                fontSize: 20,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
