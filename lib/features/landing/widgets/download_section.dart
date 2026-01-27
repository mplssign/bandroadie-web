import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/design_tokens.dart';

/// Download CTA section with app store buttons
class DownloadSection extends StatelessWidget {
  const DownloadSection({super.key});

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
            const Color(0xFF0a0505),
            AppColors.scaffoldBg,
            const Color(0xFF14050a),
          ],
        ),
      ),
      child: Column(
        children: [
          // Main headline
          Text(
            'Get BandRoadie',
            textAlign: TextAlign.center,
            style: AppTextStyles.title3.copyWith(
              fontSize: isMobile ? 36 : 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Available now on iOS, coming soon to Android',
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              fontSize: 18,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: isMobile ? 40 : 60),
          
          // Download buttons - all on same row
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
      icon: Icons.android,
      topText: 'GET IT ON',
      mainText: 'Google Play',
      onPressed: () => _launchUrl('https://play.google.com/store/apps/details?id=com.bandroadie.app'),
      isAvailable: false,
    );
  }
}

class _WebAppButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      constraints: const BoxConstraints(minWidth: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.accent,
          width: 2,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.1),
            AppColors.accent.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).pushNamed('/app'),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.web,
                  size: 36,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Open in browser',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Web App',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
  final VoidCallback onPressed;
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
    return Container(
      height: 60,
      constraints: const BoxConstraints(minWidth: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isAvailable
              ? [Colors.black, const Color(0xFF1a1a1a)]
              : [AppColors.cardBg, AppColors.surfaceDark],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isAvailable ? 0.2 : 0.1),
          width: 1,
        ),
        boxShadow: isAvailable
            ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isAvailable ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 36,
                  color: isAvailable ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: isAvailable ? Colors.white.withValues(alpha: 0.9) : AppColors.textSecondary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          mainText,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: isAvailable ? Colors.white : AppColors.textSecondary,
                            height: 1,
                          ),
                        ),
                        if (!isAvailable) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'SOON',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
