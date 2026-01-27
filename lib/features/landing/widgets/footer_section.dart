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
        border: Border(
          top: BorderSide(
            color: AppColors.borderMuted,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Links
          Wrap(
            spacing: isMobile ? 16 : 32,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              _FooterLink(
                label: 'Privacy Policy',
                onTap: () async {
                  final uri = Uri.parse('https://bandroadie.com/privacy');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
              _FooterLink(
                label: 'Terms of Service',
                onTap: () {
                  // TODO: Add terms of service page
                },
              ),
              _FooterLink(
                label: 'Support',
                onTap: () {
                  // TODO: Add support/contact page
                },
              ),
            ],
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

  const _FooterLink({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}
