import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Widget that animates into view when scrolled into viewport
class ScrollAnimatedWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final Offset offset;

  const ScrollAnimatedWidget({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeOut,
    this.offset = const Offset(0, 50),
  });

  @override
  State<ScrollAnimatedWidget> createState() => _ScrollAnimatedWidgetState();
}

class _ScrollAnimatedWidgetState extends State<ScrollAnimatedWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _offsetAnimation;
  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    _offsetAnimation = Tween<Offset>(
      begin: widget.offset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    // Start animation immediately to ensure all sections are visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _checkVisibility() {
    if (!mounted || _hasAnimated) return;

    try {
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.attached) {
        final position = renderBox.localToGlobal(Offset.zero);
        final screenHeight = MediaQuery.of(context).size.height;

        // Check if widget is in viewport or just below it
        // Using a more generous threshold to trigger animations earlier
        if (position.dy < screenHeight * 1.2) {
          _hasAnimated = true;
          _controller.forward();
        } else {
          // Schedule another check
          Future.delayed(const Duration(milliseconds: 100), _checkVisibility);
        }
      }
    } catch (e) {
      // If any error occurs, just show the widget
      _hasAnimated = true;
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!_hasAnimated) {
          _checkVisibility();
        }
        return false;
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: _offsetAnimation.value,
            child: Opacity(opacity: _opacityAnimation.value, child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}
