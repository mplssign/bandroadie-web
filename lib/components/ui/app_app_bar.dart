import 'package:flutter/material.dart';

/// Wrapper for [AppBar] that respects app theme configuration.
///
/// Use this widget instead of [AppBar] to ensure consistent
/// app bar styling across the app. Delegates all props directly
/// to [AppBar] while respecting theme's appBarTheme unless
/// explicitly overridden.
class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.backgroundColor,
    this.centerTitle,
  });

  /// App bar title (can be String or Widget)
  final dynamic title;

  /// Optional leading widget (typically back button or menu)
  final Widget? leading;

  /// Optional action widgets (typically icon buttons)
  final List<Widget>? actions;

  /// Optional background color override
  /// If null, uses theme's appBarTheme.backgroundColor
  final Color? backgroundColor;

  /// Whether to center the title
  /// If null, uses theme's appBarTheme.centerTitle
  final bool? centerTitle;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title == null
          ? null
          : (title is String ? Text(title as String) : title as Widget),
      leading: leading,
      actions: actions,
      backgroundColor: backgroundColor,
      centerTitle: centerTitle,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
