import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import '../../members/member_vm.dart';

// ============================================================================
// REORDERABLE BAND MEMBER CARD
// Drag-enabled sibling of BandMemberCard (mirrors reorderable_song_card.dart's
// Stack + Positioned drag-handle-strip + pointer-absorbing Listener structure)
// so a left-edge drag handle can start a reorder while the rest of the card
// remains tappable/scrollable, not draggable.
//
// Renders the same name / crown / musical-roles content BandMemberCard does.
// ============================================================================

class ReorderableBandMemberCard extends StatefulWidget {
  final MemberVM member;
  final int index;
  final VoidCallback? onTap;

  const ReorderableBandMemberCard({
    super.key,
    required this.member,
    required this.index,
    this.onTap,
  });

  @override
  State<ReorderableBandMemberCard> createState() =>
      _ReorderableBandMemberCardState();
}

class _ReorderableBandMemberCardState extends State<ReorderableBandMemberCard>
    with SingleTickerProviderStateMixin {
  static const double _contentLeftPadding = 36.0;
  static const double _dragHandleLeft = 6.0;

  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      duration: AppDurations.instant,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.98,
    ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeInOut));
    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _tapController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _tapController.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _tapController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _tapController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(opacity: _opacityAnimation.value, child: child),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              // Content area — the Stack's only non-positioned child, so the
              // Stack sizes itself to the content's natural (variable) height
              // instead of requiring a bounded height from its sliver parent.
              // Wrapped in Listener to prevent drag events from bubbling, so
              // only the drag handle can initiate reordering.
              Listener(
                onPointerDown: (_) {}, // Absorb pointer events to prevent drag
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _contentLeftPadding,
                    16,
                    16,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              member.name,
                              style: TextStyle(
                                fontSize: AppFontSizes.title,
                                fontWeight: FontWeight.w700,
                                color: context.colors.textPrimary,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (member.isAdmin)
                            const Padding(
                              padding: EdgeInsets.only(top: 6, left: 10),
                              child: Icon(
                                AppIcons.crown,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        member.musicalRoles.join(', '),
                        style: TextStyle(
                          fontSize: AppFontSizes.body,
                          fontWeight: FontWeight.w400,
                          color: context.colors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Drag handle area — only the handle strip can start a drag
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _contentLeftPadding,
                child: ReorderableDragStartListener(
                  index: widget.index,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(left: _dragHandleLeft),
                      child: Icon(
                        AppIcons.drag,
                        size: 24,
                        color:
                            context.colors.textSecondary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
