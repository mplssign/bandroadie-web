import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/responsive.dart';

/// Hero section with app name, tagline, and CTAs
class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveWidget(
      mobile: const _HeroMobile(),
      desktop: const _HeroDesktop(),
    );
  }
}

class _HeroMobile extends StatelessWidget {
  const _HeroMobile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.scaffoldBg,
            const Color(0xFF1a0a14),
            const Color(0xFF1a0505),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo with tagline
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
              );
            },
            child: SvgPicture.asset(
              'assets/images/band_roadie_logo_tagline.svg',
              height: 80,
            ),
          ),
          const SizedBox(height: 32),

          // Subtext - larger and bold
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 30 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: Text(
              'Manage Your Band\'s Setlists, Rehearsals, Gigs, and Calendars.\nAll In One Place.',
              textAlign: TextAlign.center,
              style: AppTextStyles.title3.copyWith(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 40),

          // Primary CTA
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 30 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [_AppStoreCTA(), _GooglePlayCTA(), _WebAppCTA()],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroDesktop extends StatelessWidget {
  const _HeroDesktop();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(80, 60, 80, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.scaffoldBg,
            const Color(0xFF1a0a14),
            const Color(0xFF1a0505),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Left: Content
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo with tagline
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: SvgPicture.asset(
                    'assets/images/band_roadie_logo_tagline.svg',
                    height: 120,
                  ),
                ),
                const SizedBox(height: 32),

                // Subtext - larger and bold
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(-30 * (1 - value), 0),
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                  child: Text(
                    'Manage Your Band\'s Setlists, Rehearsals, Gigs, and Calendars.\nAll In One Place.',
                    style: AppTextStyles.title3.copyWith(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(height: 48),

                // CTAs
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(-30 * (1 - value), 0),
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [_AppStoreCTA(), _GooglePlayCTA(), _WebAppCTA()],
                  ),
                ),
              ],
            ),
          ),

          // Right: Phone mockup with animation
          const SizedBox(width: 80),
          Flexible(
            flex: 1,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(30 * (1 - value), 0),
                    child: Opacity(opacity: value, child: child),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 40),
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          blurRadius: 60,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/phone_hands.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// App Store CTA button
class _AppStoreCTA extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _StoreBadge(
      icon: Icons.apple,
      topText: 'Download on the',
      mainText: 'App Store',
      onPressed: () =>
          _launchUrl('https://apps.apple.com/us/app/band-roadie/id6757283775'),
      isAvailable: true,
    );
  }
}

/// Google Play CTA button
class _GooglePlayCTA extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _StoreBadge(
      icon: Icons.play_arrow,
      topText: 'GET IT ON',
      mainText: 'Google Play',
      onPressed: () {},
      isAvailable: false,
    );
  }
}

/// Web App CTA button
class _WebAppCTA extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _StoreBadge(
      icon: Icons.web,
      topText: 'BandRoadie.com',
      mainText: 'Web App',
      onPressed: () => _launchUrl('https://app.bandroadie.com/'),
      isAvailable: true,
    );
  }
}

/// Reusable store badge matching official App Store / Google Play badge style
class _StoreBadge extends StatelessWidget {
  final IconData icon;
  final String topText;
  final String mainText;
  final VoidCallback onPressed;
  final bool isAvailable;

  const _StoreBadge({
    required this.icon,
    required this.topText,
    required this.mainText,
    required this.onPressed,
    required this.isAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
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
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isAvailable ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 28,
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
                        color: isAvailable
                            ? Colors.white.withValues(alpha: 0.9)
                            : AppColors.textSecondary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          mainText,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isAvailable
                                ? Colors.white
                                : AppColors.textSecondary,
                            height: 1.2,
                          ),
                        ),
                        if (!isAvailable) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
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
