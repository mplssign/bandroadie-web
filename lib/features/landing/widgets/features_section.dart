import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';

/// Features grid section showcasing the 4 main features
class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    
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
            style: AppTextStyles.title3.copyWith(
              fontSize: isMobile ? 32 : 40,
            ),
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
              final spacing = isMobile ? 24.0 : 32.0;
              final cardWidth = isMobile ? double.infinity : (constraints.maxWidth - (spacing * 3)) / 4;
              
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
                      description: 'Schedule rehearsals, add notes, and keep everyone aligned.',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _FeatureCard(
                      icon: Icons.mic_rounded,
                      title: 'Gigs & Potential Gigs',
                      description: 'Track confirmed shows and "maybes" with venue details and notes.',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _FeatureCard(
                      icon: Icons.calendar_month_rounded,
                      title: 'Band Calendar',
                      description: 'A shared calendar for rehearsals, gigs, setlists, and blackout dates.',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _FeatureCard(
                      icon: Icons.queue_music_rounded,
                      title: 'Setlists',
                      description: 'Build setlists with song order, tempo, key, and performance notes.',
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
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered ? AppColors.accent.withValues(alpha: 0.4) : AppColors.borderMuted,
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
              child: Icon(
                widget.icon,
                size: 32,
                color: AppColors.accent,
              ),
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
                fontSize: 16,
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
