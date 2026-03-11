import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
            style: AppTextStyles.title3.copyWith(fontSize: isMobile ? 36 : 48),
          ),
          const SizedBox(height: 16),
          Text(
            'Available now on iOS and Web, coming soon to Android',
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              fontFamily: 'Caveat',
              fontSize: 20,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          SizedBox(height: isMobile ? 40 : 60),

          // Download buttons
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [_AppStoreButton(), _GooglePlayButton(), _WebAppButton()],
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
      iconWidget: const Icon(Icons.apple, size: 36, color: Colors.white),
      topText: 'Download on the',
      mainText: 'App Store',
      onPressed: () =>
          _launchUrl('https://apps.apple.com/us/app/band-roadie/id6757283775'),
    );
  }
}

class _GooglePlayButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _OfficialBadge(
      iconWidget: SvgPicture.asset('assets/images/google_play_logo.svg',
          width: 36, height: 36),
      topText: 'GET IT ON',
      mainText: 'Google Play',
      onPressed: () => _launchUrl(
        'https://play.google.com/store/apps/details?id=com.bandroadie.app',
      ),
    );
  }
}

class _WebAppButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      width: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Color(0xFF1a1a1a)],
        ),
        border: Border.all(
          color: Colors.white,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _launchUrl('https://app.bandroadie.com/'),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.web, size: 36, color: Colors.white),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BandRoadie.com',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Web App',
                      style: TextStyle(
                        fontSize: 20,
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
      ),
    );
  }
}

class _OfficialBadge extends StatelessWidget {
  final Widget iconWidget;
  final String topText;
  final String mainText;
  final VoidCallback onPressed;

  const _OfficialBadge({
    required this.iconWidget,
    required this.topText,
    required this.mainText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      width: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.black,
        border: Border.all(
          color: Colors.white,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWidget,
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
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mainText,
                      style: const TextStyle(
                        fontSize: 20,
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
