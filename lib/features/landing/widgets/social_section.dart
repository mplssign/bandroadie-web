import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

/// Catalog → Setlist section explaining BandRoadie's core song library model
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
      color: context.colors.background,
      child: Column(
        children: [
          // Section headline
          Text(
            'Your Catalog is the heart of BandRoadie',
            textAlign: TextAlign.center,
            style: AppTextStyles.title3.copyWith(fontSize: isMobile ? 32 : 40),
          ),
          const SizedBox(height: 16),
          // Subheadline
          Text(
            'Every song your band knows lives in one place. Setlists are built from the Catalog, not copied from scratch.',
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              fontFamily: 'Caveat',
              fontSize: 20,
              color: context.colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          // Supporting copy
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(
              'Bands reuse songs constantly — across gigs, rehearsals, old favorites, new material, and songs still in progress. BandRoadie treats your Catalog as the source of truth, so every setlist stays connected to the same shared song library.',
              textAlign: TextAlign.center,
              style: AppTextStyles.callout.copyWith(
                fontSize: 16,
                color: context.colors.textSecondary,
                height: 1.6,
              ),
            ),
          ),
          SizedBox(height: isMobile ? 40 : 60),

          // Feature cards grid
          LayoutBuilder(
            builder: (context, constraints) {
              final int columns;
              final double spacing;

              if (constraints.maxWidth < 700) {
                columns = 1;
                spacing = 24.0;
              } else if (constraints.maxWidth < 1200) {
                columns = 2;
                spacing = 24.0;
              } else {
                columns = 4;
                spacing = 32.0;
              }

              final cardWidth =
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _CatalogCard(
                      icon: AppIcons.library,
                      title: 'One Song Library',
                      description:
                          'Store every song once with notes, lyrics, BPM, duration, tuning, and status.',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _CatalogCard(
                      icon: AppIcons.setlists,
                      title: 'Build Setlists Faster',
                      description:
                          'Create show-ready setlists by pulling songs directly from your Catalog.',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _CatalogCard(
                      icon: AppIcons.success,
                      title: 'No Lost Songs',
                      description:
                          'Remove a song from a setlist without deleting it from your band\'s library.',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _CatalogCard(
                      icon: AppIcons.refresh,
                      title: 'Reuse Every Night',
                      description:
                          'Bring songs back for future gigs, rehearsals, and special sets without re-entering anything.',
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

class _CatalogCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;

  const _CatalogCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  State<_CatalogCard> createState() => _CatalogCardState();
}

class _CatalogCardState extends State<_CatalogCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.translationValues(0, _isHovered ? -8 : 0, 0),
        constraints: const BoxConstraints(minHeight: 280),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? AppColors.primary.withValues(alpha: 0.4)
                : context.colors.border,
            width: 1,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, size: 32, color: AppColors.primary),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              widget.title,
              style: AppTextStyles.headline.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              widget.description,
              style: AppTextStyles.callout.copyWith(
                fontFamily: 'Caveat',
                fontSize: 20,
                color: context.colors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
