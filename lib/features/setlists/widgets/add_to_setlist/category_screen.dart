import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'add_to_setlist_overlay.dart';
import 'category_button.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

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
                        color: context.colors.textSecondary,
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
                    child: CategoryButton(
                      icon: AppIcons.search,
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
                    child: CategoryButton(
                      icon: AppIcons.edit,
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
                    child: CategoryButton(
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
                          Expanded(
                            child: Divider(
                              color: context.colors.border,
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'BREAKS & PAUSES',
                              style: AppTextStyles.label.copyWith(
                                color: context.colors.textMuted,
                                fontSize: 11,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: context.colors.border,
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
                      child: CategoryButton(
                        icon: AppIcons.timer,
                        label: 'Set Break',
                        subtitle: 'Break between sets',
                        accentColor: context.colors.primaryDim,
                        onTap: () => widget.onCategorySelected(
                          AddToSetlistCategory.setBreak,
                        ),
                      ),
                    ),
                  ),

                  // Pause
                  _buildStaggeredChild(
                    index: 6,
                    child: CategoryButton(
                      icon: Icons.pause_circle_outline_rounded,
                      label: 'Pause',
                      subtitle: 'Guitar change, tuning break, band intro, etc.',
                      accentColor: context.colors.warning,
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
