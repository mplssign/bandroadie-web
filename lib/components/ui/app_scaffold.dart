import 'package:flutter/material.dart';

/// Wrapper for [Scaffold] that respects app theme configuration.
///
/// Use this widget instead of [Scaffold] to ensure consistent
/// scaffold styling across the app. Delegates all props directly
/// to [Scaffold] while respecting theme's scaffoldBackgroundColor
/// unless explicitly overridden.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.backgroundColor,
  });

  /// Optional app bar widget
  final PreferredSizeWidget? appBar;

  /// Main content body
  final Widget body;

  /// Optional floating action button
  final Widget? floatingActionButton;

  /// Optional bottom navigation bar
  final Widget? bottomNavigationBar;

  /// Optional background color override
  /// If null, uses theme's scaffoldBackgroundColor
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      backgroundColor: backgroundColor,
    );
  }
}
