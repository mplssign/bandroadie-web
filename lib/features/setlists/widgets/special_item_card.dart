import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/setlist_item_type.dart';
import '../models/special_item.dart';

// ============================================================================
// SPECIAL ITEM CARD
// Display card for set breaks and pauses in setlist view.
//
// SET BREAK:
//   - Red filled background (#BE123C)
//   - Centered title: "SET BREAK – 20 mins"
//   - Acts as visual divider in setlist
//
// PAUSE:
//   - Dark card with amber/yellow accent border
//   - Title: purposes joined by " - " (uppercase)
//   - Optional duration below title in smaller text
//
// Both are draggable, editable, and dismissible like song cards.
// ============================================================================

class SpecialItemCard extends StatefulWidget {
  final SpecialItem item;
  final int index;
  final bool isDraggable;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  const SpecialItemCard({
    super.key,
    required this.item,
    required this.index,
    this.isDraggable = true,
    this.onTap,
    this.onEdit,
  });

  @override
  State<SpecialItemCard> createState() => _SpecialItemCardState();
}

class _SpecialItemCardState extends State<SpecialItemCard>
    with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    if (widget.item.type == SetlistItemType.setBreak) {
      return _buildSetBreakCard();
    }
    return _buildPauseCard();
  }

  /// Red filled card for set breaks
  Widget _buildSetBreakCard() {
    return GestureDetector(
      onTapDown: (_) => _tapController.forward(),
      onTapUp: (_) {
        _tapController.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _tapController.reverse(),
      child: AnimatedBuilder(
        animation: _tapController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(opacity: _opacityAnimation.value, child: child),
          );
        },
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFBE123C),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFBE123C).withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Drag handle
              if (widget.isDraggable)
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: SongCardLayout.dragHandleLeft,
                    ),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 24,
                    ),
                  ),
                ),
              // Title centered
              Expanded(
                child: Center(
                  child: Text(
                    widget.item.displayTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              // Edit button
              if (widget.onEdit != null)
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  onPressed: widget.onEdit,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Dark card with amber accent for pauses
  Widget _buildPauseCard() {
    final subDuration = widget.item.formattedSubDuration;

    return GestureDetector(
      onTapDown: (_) => _tapController.forward(),
      onTapUp: (_) {
        _tapController.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _tapController.reverse(),
      child: AnimatedBuilder(
        animation: _tapController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(opacity: _opacityAnimation.value, child: child),
          );
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              // Drag handle
              if (widget.isDraggable)
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: SongCardLayout.dragHandleLeft,
                    ),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                      size: 24,
                    ),
                  ),
                ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Title (purposes)
                      Text(
                        widget.item.displayTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFF59E0B),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                      // Sub-duration if present
                      if (subDuration != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subDuration,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Edit button
              if (widget.onEdit != null)
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                  ),
                  onPressed: widget.onEdit,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
