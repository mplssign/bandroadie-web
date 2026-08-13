import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Wrapper for [FScaffold] that provides consistent scaffold structure.
///
/// Use this widget instead of [Scaffold] to ensure consistent
/// scaffold styling across the app using Forui design system.
///
/// **Note for preview cycle:** The `backgroundColor` prop is currently ignored
/// (no style override applied). Scaffold uses theme default background.
/// The `floatingActionButton` prop is not supported by FScaffold.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
  });

  /// Optional app bar widget
  final Widget? appBar;

  /// Main content body
  final Widget body;

  /// Optional floating action button (not supported in Forui preview)
  final Widget? floatingActionButton;

  /// Optional bottom navigation bar
  final Widget? bottomNavigationBar;

  /// Optional background color override (ignored in Forui preview)
  final Color? backgroundColor;

  /// Whether to resize body when keyboard appears
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      header: appBar,
      footer: bottomNavigationBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset ?? true,
      child: body,
    );
  }
}
