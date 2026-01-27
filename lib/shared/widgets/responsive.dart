import 'package:flutter/material.dart';

/// Simple responsive widget wrapper
class ResponsiveWidget extends StatelessWidget {
  final Widget mobile;
  final Widget desktop;
  final int breakpoint;

  const ResponsiveWidget({
    super.key,
    required this.mobile,
    required this.desktop,
    this.breakpoint = 900,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width < breakpoint ? mobile : desktop;
  }
}
