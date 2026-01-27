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
              children: [
                _AppStoreCTA(),
                _GooglePlayCTA(),
                _WebAppCTA(),
              ],
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
                      child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
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
                    children: [
                      _AppStoreCTA(),
                      _GooglePlayCTA(),
                      _WebAppCTA(),
                    ],
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
                    child: Opacity(
                      opacity: value,
                      child: child,
                    ),
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
    return _CTAButton(
      label: 'App Store',
      icon: Icons.apple,
      isPrimary: true,
      onPressed: () => _launchUrl('https://apps.apple.com/us/app/band-roadie/id6757283775'),
    );
  }
}

/// Google Play CTA button
class _GooglePlayCTA extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _CTAButton(
      label: 'Google Play',
      icon: Icons.android,
      isPrimary: true,
      isComingSoon: true,
      onPressed: () {},
    );
  }
}

/// Web App CTA button
class _WebAppCTA extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _CTAButton(
      label: 'Web App',
      icon: Icons.web,
      isPrimary: false,
      onPressed: () => Navigator.pushNamed(context, '/app'),
    );
  }
}

/// Reusable CTA button
class _CTAButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final bool isComingSoon;
  final VoidCallback onPressed;

  const _CTAButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    this.isComingSoon = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: isPrimary
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isComingSoon
                    ? [AppColors.cardBg, AppColors.surfaceDark]
                    : [Colors.black, const Color(0xFF1a1a1a)],
              )
            : null,
        color: isPrimary ? null : AppColors.cardBg,
        border: Border.all(
          color: isPrimary ? Colors.white.withValues(alpha: 0.2) : AppColors.borderMuted,
          width: 1,
        ),
        boxShadow: isPrimary && !isComingSoon
            ? [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isComingSoon ? null : onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: isPrimary ? Colors.white : AppColors.textPrimary,
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isComingSoon)
                      Text(
                        'Coming Soon',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                          height: 1,
                        ),
                      ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: isComingSoon ? 14 : 16,
                        fontWeight: FontWeight.w600,
                        color: isPrimary ? Colors.white : AppColors.textPrimary,
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
