import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
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
            context.colors.background,
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
            child: Image.asset(
              'assets/images/bandroadie_logo_stacked.png',
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
            context.colors.background,
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
                  child: Image.asset(
                    'assets/images/bandroadie_logo_stacked.png',
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
                          color: AppColors.primary.withValues(alpha: 0.3),
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
      iconWidget: const Icon(Icons.apple, size: 28, color: Colors.white),
      topText: 'Download on the',
      mainText: 'App Store',
      onPressed: () =>
          _launchUrl('https://apps.apple.com/us/app/band-roadie/id6757283775'),
    );
  }
}

/// Google Play CTA button
class _GooglePlayCTA extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _StoreBadge(
      iconWidget: SvgPicture.asset('assets/images/google_play_logo.svg',
          width: 28, height: 28),
      topText: 'GET IT ON',
      mainText: 'Google Play',
      onPressed: () => _launchUrl(
        'https://play.google.com/store/apps/details?id=com.bandroadie.app',
      ),
    );
  }
}

/// Web App CTA button
class _WebAppCTA extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _StoreBadge(
      iconWidget: const Icon(Icons.web, size: 28, color: Colors.white),
      topText: 'BandRoadie.com',
      mainText: 'Web App',
      onPressed: () => _launchUrl('https://app.bandroadie.com/'),
    );
  }
}

/// Reusable store badge
class _StoreBadge extends StatelessWidget {
  final Widget iconWidget;
  final String topText;
  final String mainText;
  final VoidCallback onPressed;

  const _StoreBadge({
    required this.iconWidget,
    required this.topText,
    required this.mainText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: 200,
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWidget,
                const SizedBox(width: 10),
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
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.2,
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

void _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
