import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Wrapper for [FHeader] that provides consistent app bar structure.
///
/// Use this widget instead of [AppBar] to ensure consistent
/// header styling across the app using Forui design system.
///
/// **Note for preview cycle:** The `backgroundColor` prop is currently ignored
/// (no style override applied). Header uses theme default background.
class AppAppBar extends StatelessWidget {
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

  /// Optional background color override (ignored in Forui preview)
  final Color? backgroundColor;

  /// Whether to center the title
  final bool? centerTitle;

  @override
  Widget build(BuildContext context) {
    // Convert title to Widget if it's a String
    final Widget titleWidget = title == null
        ? const SizedBox.shrink()
        : (title is String ? Text(title as String) : title as Widget);

    // Use .nested() constructor if we have leading widget or need to center title
    if (leading != null || centerTitle == true) {
      return FHeader.nested(
        title: titleWidget,
        prefixes: leading != null ? [leading!] : const [],
        suffixes: actions ?? const [],
        titleAlignment:
            centerTitle == true ? Alignment.center : Alignment.centerLeft,
      );
    }

    // Use main constructor for simple case (no leading, left-aligned)
    return FHeader(
      title: titleWidget,
      suffixes: actions ?? const [],
    );
  }
}
