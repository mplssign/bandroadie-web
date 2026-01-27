import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/design_tokens.dart';

/// Footer section with legal links
class FooterSection extends StatelessWidget {
  const FooterSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: 40,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border(top: BorderSide(color: AppColors.borderMuted, width: 1)),
      ),
      child: Column(
        children: [
          // Social media links
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SocialIconButton(
                icon: Icons.camera_alt,
                label: 'Instagram',
                url: 'https://www.instagram.com/bandroadie26/',
              ),
              const SizedBox(width: 16),
              _SocialIconButton(
                icon: Icons.facebook,
                label: 'Facebook',
                url: 'https://www.facebook.com/BandRaodie',
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Links
          _FooterLink(
            label: 'Privacy Policy',
            onTap: () async {
              final uri = Uri.parse('https://bandroadie.com/privacy');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
          ),
          const SizedBox(height: 24),

          // Copyright
          Text(
            '© ${DateTime.now().year} BandRoadie. All rights reserved.',
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              fontSize: 14,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}

class _SocialIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;

  const _SocialIconButton({
    required this.icon,
    required this.label,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.borderMuted, width: 1),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 24),
        ),
      ),
    );
  }
}
