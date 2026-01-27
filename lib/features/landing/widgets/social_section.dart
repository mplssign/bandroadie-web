import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/design_tokens.dart';

/// Social media section with Instagram and Facebook tiles
class SocialSection extends StatelessWidget {
  const SocialSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: isMobile ? 60 : 80,
      ),
      color: AppColors.scaffoldBg,
      child: Column(
        children: [
          // Section title
          Text(
            'Follow Us',
            textAlign: TextAlign.center,
            style: AppTextStyles.title3.copyWith(fontSize: isMobile ? 32 : 40),
          ),
          const SizedBox(height: 16),
          Text(
            'Stay updated with the latest news and features',
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              fontFamily: 'Caveat',
              fontSize: 20,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          SizedBox(height: isMobile ? 40 : 60),

          // Social media tiles
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = isMobile ? 16.0 : 24.0;
              final tileWidth = isMobile
                  ? constraints.maxWidth
                  : (constraints.maxWidth - spacing) / 2;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: tileWidth > 400 ? 400 : tileWidth,
                    child: _SocialTile(
                      icon: Icons.camera_alt,
                      platform: 'Instagram',
                      handle: '@bandroadie26',
                      url: 'https://www.instagram.com/bandroadie26/',
                      gradientColors: const [
                        Color(0xFFf09433),
                        Color(0xFFe6683c),
                        Color(0xFFdc2743),
                        Color(0xFFcc2366),
                        Color(0xFFbc1888),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: tileWidth > 400 ? 400 : tileWidth,
                    child: _SocialTile(
                      icon: Icons.facebook,
                      platform: 'Facebook',
                      handle: '@BandRaodie',
                      url: 'https://www.facebook.com/BandRaodie',
                      gradientColors: const [
                        Color(0xFF1877F2),
                        Color(0xFF0C63D4),
                      ],
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

class _SocialTile extends StatefulWidget {
  final IconData icon;
  final String platform;
  final String handle;
  final String url;
  final List<Color> gradientColors;

  const _SocialTile({
    required this.icon,
    required this.platform,
    required this.handle,
    required this.url,
    required this.gradientColors,
  });

  @override
  State<_SocialTile> createState() => _SocialTileState();
}

class _SocialTileState extends State<_SocialTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final uri = Uri.parse(widget.url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0, _isHovered ? -8 : 0, 0),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isHovered
                  ? widget.gradientColors
                  : [AppColors.cardBg, AppColors.cardBg],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered
                  ? widget.gradientColors.first.withValues(alpha: 0.5)
                  : AppColors.borderMuted,
              width: 2,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.gradientColors.first.withValues(alpha: 0.3),
                      blurRadius: 24,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _isHovered
                      ? Colors.white.withValues(alpha: 0.2)
                      : widget.gradientColors.first.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon,
                  size: 32,
                  color: _isHovered
                      ? Colors.white
                      : widget.gradientColors.first,
                ),
              ),
              const SizedBox(width: 20),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.platform,
                      style: AppTextStyles.title3.copyWith(
                        fontSize: 20,
                        color: _isHovered
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.handle,
                      style: AppTextStyles.callout.copyWith(
                        color: _isHovered
                            ? Colors.white.withValues(alpha: 0.9)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.arrow_forward,
                color: _isHovered ? Colors.white : AppColors.textSecondary,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
