import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';

/// Value proposition section - Why BandRoadie
class ValueSection extends StatelessWidget {
  const ValueSection({super.key});

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
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.scaffoldBg,
            const Color(0xFF14050a),
            const Color(0xFF1a0505),
            const Color(0xFF0a0505),
            AppColors.scaffoldBg,
          ],
          stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
        ),
      ),
      child: Column(
        children: [
          // Main headline
          Text(
            'Built by a Musician. For Musicians.',
            textAlign: TextAlign.center,
            style: AppTextStyles.title3.copyWith(fontSize: isMobile ? 32 : 40),
          ),
          const SizedBox(height: 12),
          Text(
            'Well, a Drummer, so kind of A Musician',
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              fontFamily: 'Caveat',
              fontSize: 20,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          SizedBox(height: isMobile ? 40 : 60),

          // Value points
          Wrap(
            spacing: isMobile ? 0 : 40,
            runSpacing: 40,
            alignment: WrapAlignment.center,
            children: [
              _ValuePoint(
                icon: Icons.speed_rounded,
                title: 'Easy to Set Up',
                description: 'Get your band organized in minutes, not hours.',
                isMobile: isMobile,
              ),
              _ValuePoint(
                icon: Icons.music_note_rounded,
                title: 'Built for Real Bands',
                description: 'Designed by musicians who know what bands need.',
                isMobile: isMobile,
              ),
              _ValuePoint(
                icon: Icons.phone_iphone_rounded,
                title: 'Mobile-First',
                description:
                    'Access everything from your phone, tablet, or computer.',
                isMobile: isMobile,
              ),
              _ValuePoint(
                icon: Icons.cloud_sync_rounded,
                title: 'Always in Sync',
                description:
                    'Real-time updates keep everyone on the same page.',
                isMobile: isMobile,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValuePoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isMobile;

  const _ValuePoint({
    required this.icon,
    required this.title,
    required this.description,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: isMobile ? double.infinity : 240,
      child: Column(
        children: [
          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: AppColors.accent),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.headline.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 12),

          // Description
          Text(
            description,
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              fontFamily: 'Caveat',
              fontSize: 20,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
