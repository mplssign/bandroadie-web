import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import 'add_to_setlist_overlay.dart';

// ============================================================================
// CATEGORY SCREEN
// Screen 1 of the Add to Setlist flow.
// Three stacked buttons: Cover Song, Original Song, Bulk Entry
// with staggered fade + slide-up entrance animations.
// ============================================================================

class CategoryScreen extends StatefulWidget {
  final void Function(AddToSetlistCategory category) onCategorySelected;
  final bool isCatalog;

  const CategoryScreen({
    super.key,
    required this.onCategorySelected,
    this.isCatalog = false,
  });

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Start the staggered entrance animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceController.forward();
      }
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.space24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - (Spacing.space24 * 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Subtitle
                _buildStaggeredChild(
                  index: 0,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.space32),
                    child: Text(
                      'What would you like to add?',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                // Cover Song
                _buildStaggeredChild(
                  index: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.space16),
                    child: _CategoryButton(
                      icon: Icons.search_rounded,
                      label: 'Cover Song',
                      subtitle: 'Search by song or artist',
                      onTap: () =>
                          widget.onCategorySelected(AddToSetlistCategory.cover),
                    ),
                  ),
                ),

                // Original Song
                _buildStaggeredChild(
                  index: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.space16),
                    child: _CategoryButton(
                      icon: Icons.edit_rounded,
                      label: 'Original Song',
                      subtitle: 'Add originals or hard to find covers',
                      onTap: () => widget.onCategorySelected(
                        AddToSetlistCategory.original,
                      ),
                    ),
                  ),
                ),

                // Bulk Entry
                _buildStaggeredChild(
                  index: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.space24),
                    child: _CategoryButton(
                      icon: Icons.list_rounded,
                      label: 'Bulk Entry',
                      subtitle: 'Paste from a spreadsheet',
                      onTap: () =>
                          widget.onCategorySelected(AddToSetlistCategory.bulk),
                    ),
                  ),
                ),

                // Breaks & Pauses (hidden for Catalog)
                if (!widget.isCatalog) ...[
                  // Divider
                  _buildStaggeredChild(
                    index: 4,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.space16),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Divider(
                              color: AppColors.borderMuted,
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'BREAKS & PAUSES',
                              style: AppTextStyles.label.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Divider(
                              color: AppColors.borderMuted,
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Set Break
                  _buildStaggeredChild(
                    index: 5,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.space16),
                      child: _CategoryButton(
                        icon: Icons.timer_outlined,
                        label: 'Set Break',
                        subtitle: 'Intermission between sets',
                        accentColor: const Color(0xFFBE123C),
                        onTap: () => widget.onCategorySelected(
                          AddToSetlistCategory.setBreak,
                        ),
                      ),
                    ),
                  ),

                  // Pause
                  _buildStaggeredChild(
                    index: 6,
                    child: _CategoryButton(
                      icon: Icons.pause_circle_outline_rounded,
                      label: 'Pause',
                      subtitle: 'Guitar change, tuning break, band intro, etc.',
                      accentColor: const Color(0xFFF59E0B),
                      onTap: () =>
                          widget.onCategorySelected(AddToSetlistCategory.pause),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStaggeredChild({required int index, required Widget child}) {
    final delay = (index * 0.12).clamp(0.0, 0.6);
    final end = (delay + 0.5).clamp(0.0, 1.0);

    final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(delay, end, curve: Curves.easeOutCubic),
      ),
    );

    final slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Interval(delay, end, curve: Curves.easeOutCubic),
          ),
        );

    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, _) {
        return FadeTransition(
          opacity: fadeAnimation,
          child: SlideTransition(position: slideAnimation, child: child),
        );
      },
    );
  }
}

// ============================================================================
// CATEGORY BUTTON
// Full-width button with icon, label, subtitle, and press animation.
// ============================================================================

class _CategoryButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color? accentColor;
  final VoidCallback onTap;

  const _CategoryButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.accentColor,
    required this.onTap,
  });

  @override
  State<_CategoryButton> createState() => _CategoryButtonState();
}

class _CategoryButtonState extends State<_CategoryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) => _pressController.forward();
  void _handleTapUp(TapUpDetails details) => _pressController.reverse();
  void _handleTapCancel() => _pressController.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space20,
            vertical: Spacing.space16,
          ),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            border: Border.all(color: AppColors.borderMuted, width: 1.5),
          ),
          child: Row(
            children: [
              // Icon container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (widget.accentColor ?? AppColors.accent).withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon,
                  size: 22,
                  color: widget.accentColor ?? AppColors.accent,
                ),
              ),

              const SizedBox(width: Spacing.space16),

              // Label + Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: AppTextStyles.headline.copyWith(fontSize: 17),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Chevron
              const Icon(
                Icons.chevron_right_rounded,
                size: 24,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
