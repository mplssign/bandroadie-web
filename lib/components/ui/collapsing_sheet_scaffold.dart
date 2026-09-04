import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:bandroadie/app/theme/brand_colors.dart';

/// A sheet scaffold that collapses the [header] upward and the [footer]
/// downward while the user actively scrolls the [body], then reveals both
/// the moment scrolling pauses or reverses — giving the content maximum
/// vertical space mid-scroll while keeping primary actions reachable at rest.
///
/// Slots:
/// - [dragHandle] — always visible; never animated.
/// - [header] — optional; null on Pattern-A sheets (title lives in the scroll
///   body). When non-null, collapses upward via [SizeTransition].
/// - [body] — required; rendered in an [Expanded]. Should be a scrollable.
/// - [footer] — optional; typically a [SheetFooter]. Collapses downward.
///
/// Guards that pin chrome fully visible:
/// - Keyboard open (`MediaQuery.viewInsetsOf.bottom > 0`).
/// - Reduced motion (`MediaQuery.disableAnimationsOf`).
/// - Body has no scrollable overflow (detected via [ScrollMetricsNotification]).
class CollapsingSheetScaffold extends StatefulWidget {
  const CollapsingSheetScaffold({
    super.key,
    this.dragHandle,
    this.header,
    required this.body,
    this.footer,
  });

  final Widget? dragHandle;
  final Widget? header;
  final Widget body;
  final Widget? footer;

  @override
  State<CollapsingSheetScaffold> createState() =>
      _CollapsingSheetScaffoldState();
}

class _CollapsingSheetScaffoldState extends State<CollapsingSheetScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool _hasOverflow = false;
  double _accumulatedDelta = 0;
  ScrollDirection _lastDirection = ScrollDirection.idle;
  Timer? _debounceTimer;

  static const Duration _animDuration = Duration(milliseconds: 220);
  static const double _deltaThreshold = 6.0;
  static const Duration _debounceWindow = Duration(milliseconds: 50);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      value: 1.0,
      duration: _animDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.viewInsetsOf(context).bottom > 0 ||
        MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _collapse() {
    unawaited(_controller.animateTo(0.0, curve: Curves.easeIn));
  }

  void _reveal() {
    unawaited(_controller.animateTo(1.0, curve: Curves.easeOut));
  }

  /// Returns true if this direction change is accepted (not suppressed by the
  /// 50 ms debounce window).
  bool _acceptDirectionChange(ScrollDirection newDirection) {
    if (newDirection == _lastDirection) return false;
    if (_debounceTimer?.isActive ?? false) return false;
    _lastDirection = newDirection;
    _accumulatedDelta = 0;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceWindow, () {});
    return true;
  }

  bool _onNotification(BuildContext context, Notification notification) {
    // Only the depth-0 (primary) scrollable triggers collapse.
    if (notification is ScrollMetricsNotification) {
      if (notification.depth != 0) return false;
      _hasOverflow = notification.metrics.maxScrollExtent > 0;
      if (!_hasOverflow) _controller.value = 1.0;
      return false;
    }

    if (notification is! ScrollNotification) return false;
    if (notification.depth != 0) return false;

    // UX guards.
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      _controller.value = 1.0;
      return false;
    }
    if (MediaQuery.disableAnimationsOf(context)) return false;
    if (!_hasOverflow) return false;

    if (notification is UserScrollNotification) {
      switch (notification.direction) {
        case ScrollDirection.reverse:
          if (_acceptDirectionChange(ScrollDirection.reverse)) _collapse();
        case ScrollDirection.forward:
          if (_acceptDirectionChange(ScrollDirection.forward)) _reveal();
        case ScrollDirection.idle:
          break;
      }
    } else if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (delta == null) return false;
      final dir = delta > 0 ? ScrollDirection.reverse : ScrollDirection.forward;
      if (dir != _lastDirection) {
        _lastDirection = dir;
        _accumulatedDelta = 0;
      }
      _accumulatedDelta += delta.abs();
      if (_accumulatedDelta > _deltaThreshold) {
        if (dir == ScrollDirection.reverse) {
          _collapse();
        } else {
          _reveal();
        }
      }
    } else if (notification is ScrollEndNotification) {
      // Bypass debounce: always reveal on idle so primary actions stay reachable.
      _debounceTimer?.cancel();
      _lastDirection = ScrollDirection.idle;
      _accumulatedDelta = 0;
      _reveal();
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final dragHandle = widget.dragHandle ??
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        dragHandle,
        if (widget.header != null)
          SizeTransition(
            alignment: Alignment.bottomCenter,
            sizeFactor: _controller,
            child: widget.header,
          ),
        Expanded(
          child: NotificationListener<Notification>(
            onNotification: (n) => _onNotification(context, n),
            child: widget.body,
          ),
        ),
        if (widget.footer != null)
          SizeTransition(
            alignment: Alignment.topCenter,
            sizeFactor: _controller,
            child: widget.footer,
          ),
      ],
    );
  }
}
