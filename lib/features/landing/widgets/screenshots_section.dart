import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/design_tokens.dart';

/// Download section with app store buttons
class ScreenshotsSection extends StatelessWidget {
  const ScreenshotsSection({super.key});

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
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.scaffoldBg,
            const Color(0xFF0a0505),
            const Color(0xFF1a0a00),
            AppColors.scaffoldBg,
          ],
          stops: const [0.0, 0.4, 0.6, 1.0],
        ),
      ),
      child: Column(
        children: [
          // Section title
          Text(
            'Get BandRoadie',
            textAlign: TextAlign.center,
            style: AppTextStyles.title3.copyWith(
              fontSize: isMobile ? 36 : 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Available now on iOS and Web, coming soon to Android',
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              fontSize: 18,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: isMobile ? 40 : 60),
          
          // Download buttons
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              _AppStoreButton(),
              _GooglePlayButton(),
              _WebAppButton(),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppStoreButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _OfficialBadge(
      icon: Icons.apple,
      topText: 'Download on the',
      mainText: 'App Store',
      onPressed: () => _launchUrl('https://apps.apple.com/us/app/band-roadie/id6757283775'),
      isAvailable: true,
    );
  }
}

class _GooglePlayButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _OfficialBadge(
      icon: Icons.shop,
      topText: 'Get it on',
      mainText: 'Google Play',
      onPressed: null, // Not available yet
      isAvailable: false,
    );
  }
}

class _WebAppButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _launchUrl('https://bandroadie.com/app'),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: AppColors.accent, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.language, color: AppColors.accent, size: 24),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Open',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Web App',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfficialBadge extends StatelessWidget {
  final IconData icon;
  final String topText;
  final String mainText;
  final VoidCallback? onPressed;
  final bool isAvailable;

  const _OfficialBadge({
    required this.icon,
    required this.topText,
    required this.mainText,
    required this.onPressed,
    required this.isAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: isAvailable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onPressed,
        child: Stack(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF000000),
                    const Color(0xFF1a1a1a),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: isAvailable
                    ? [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Opacity(
                opacity: isAvailable ? 1.0 : 0.5,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topText,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          mainText,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!isAvailable)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'SOON',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void _launchUrl(String urlString) async {
  final uri = Uri.parse(urlString);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}
