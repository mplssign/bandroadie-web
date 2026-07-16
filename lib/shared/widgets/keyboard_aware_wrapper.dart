import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';

// ============================================================================
// KEYBOARD AWARE WRAPPER
//
// Two behaviours in one widget, applied globally via MaterialApp.builder:
//
// 1. SCROLL-INTO-VIEW — whenever the software keyboard appears or resizes,
//    the currently focused field is scrolled into the visible viewport so it
//    is never hidden behind the keyboard.
//
// 2. NUMERIC DONE BAR — a thin "Done" toolbar is overlaid just above the
//    keyboard whenever a numeric or phone keyboard is active.  Numeric pads
//    have no built-in return/done key, so this gives users a reliable way to
//    dismiss the keyboard and confirm their input.
//
// Both behaviours are driven by a single WidgetsBindingObserver.
// ============================================================================

/// Set of keyboard type indices that lack a built-in "Done" / return key on
/// iOS (numeric pad, phone pad) and therefore need the overlay toolbar.
/// We compare by index because TextInputType overrides == but is not a
/// primitive, so it can't be used in a `const Set`.
final _kNumericTypeIndices = {
  TextInputType.number.index,
  TextInputType.phone.index,
  TextInputType.datetime.index,
  TextInputType.visiblePassword.index,
};

/// Globally ensures focused text fields scroll above the keyboard and that
/// numeric keypads always show a "Done" button.
///
/// Place this in [MaterialApp.builder] — it wraps the entire navigator so
/// every route, bottom sheet, and dialog benefits automatically.
class KeyboardAwareWrapper extends StatefulWidget {
  const KeyboardAwareWrapper({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardAwareWrapper> createState() => _KeyboardAwareWrapperState();
}

class _KeyboardAwareWrapperState extends State<KeyboardAwareWrapper>
    with WidgetsBindingObserver {
  /// Current keyboard height (0 when keyboard is hidden).
  double _keyboardHeight = 0;

  /// Whether to show the Done bar above the keyboard.
  bool _showDoneBar = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called whenever screen metrics change — including when the software
  /// keyboard appears, resizes, or dismisses.
  @override
  void didChangeMetrics() {
    // Post-frame so the layout has settled after the metric change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateKeyboardState();
      _scrollFocusedFieldIntoView();
    });
  }

  void _updateKeyboardState() {
    // viewInsets is available on the root View, not via context inside builder.
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final insets = view.viewInsets;
    final pixelRatio = view.devicePixelRatio;
    final kbHeight = insets.bottom / pixelRatio;

    // Determine if a numeric/phone keyboard is showing by inspecting the
    // currently focused EditableText's keyboard type.
    bool showDone = false;
    if (kbHeight > 0) {
      final focus = FocusManager.instance.primaryFocus;
      if (focus != null) {
        // Walk up to find an EditableText to read its keyboard configuration.
        focus.context?.visitAncestorElements((element) {
          if (element.widget is EditableText) {
            final et = element.widget as EditableText;
            if (_kNumericTypeIndices.contains(et.keyboardType.index)) {
              showDone = true;
            }
            return false; // stop walking
          }
          return true;
        });
        // Also check the focused widget itself (EditableText is the focus scope)
        if (!showDone && focus.context?.widget is EditableText) {
          final et = focus.context!.widget as EditableText;
          if (_kNumericTypeIndices.contains(et.keyboardType.index)) {
            showDone = true;
          }
        }
      }
    }

    if (_keyboardHeight != kbHeight || _showDoneBar != showDone) {
      setState(() {
        _keyboardHeight = kbHeight;
        _showDoneBar = showDone;
      });
    }
  }

  void _scrollFocusedFieldIntoView() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return;

    // ensureVisible walks up the tree; if there is no Scrollable ancestor
    // it simply does nothing — safe to call unconditionally.
    Scrollable.ensureVisible(
      focusContext,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      // 0.5 centres the field in the visible area above the keyboard.
      alignment: 0.5,
    );
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // Numeric keyboard Done bar — floats just above the keyboard.
        if (_showDoneBar && _keyboardHeight > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: _keyboardHeight,
            child: _NumericDoneBar(onDone: _dismissKeyboard),
          ),
      ],
    );
  }
}

// ── Done bar widget ────────────────────────────────────────────────────────

class _NumericDoneBar extends StatelessWidget {
  const _NumericDoneBar({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final barColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFD1D3D9);
    final textColor = isDark ? Colors.white : Colors.black87;
    final buttonColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return Material(
      color: barColor,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: onDone,
                  style: TextButton.styleFrom(
                    backgroundColor: buttonColor,
                    foregroundColor: textColor,
                    minimumSize: const Size(64, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: TextStyle(
                      fontSize: AppFontSizes.subhead,
                      fontWeight: FontWeight.w600,
                      color: textColor,
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
