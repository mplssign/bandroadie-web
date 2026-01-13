import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';

// ============================================================================
// FIELD HINT
// A subtle, inline field-level hint that appears below form fields.
// - Fades in on first focus
// - Fades out after user starts typing
// - Does not show if field already has content
// ============================================================================

/// Controller for managing field hint visibility state.
/// Attach to a TextEditingController and FocusNode to track state.
class FieldHintController extends ChangeNotifier {
  bool _hasFocused = false;
  bool _isTyping = false;
  bool _hasInitialValue = false;

  /// Whether the hint should be visible
  bool get isVisible => _hasFocused && !_isTyping && !_hasInitialValue;

  /// Initialize with whether the field already has content
  void initialize({required bool hasInitialValue}) {
    _hasInitialValue = hasInitialValue;
    notifyListeners();
  }

  /// Call when field receives focus
  void onFocus() {
    if (!_hasFocused && !_hasInitialValue) {
      _hasFocused = true;
      notifyListeners();
    }
  }

  /// Call when user starts typing (field content changes from empty to non-empty)
  void onTextChanged(String text) {
    final wasTyping = _isTyping;
    _isTyping = text.isNotEmpty;
    if (wasTyping != _isTyping) {
      notifyListeners();
    }
  }

  /// Reset the controller state
  void reset() {
    _hasFocused = false;
    _isTyping = false;
    _hasInitialValue = false;
    notifyListeners();
  }
}

/// A subtle inline hint that appears below form fields.
///
/// Usage:
/// ```dart
/// Column(
///   crossAxisAlignment: CrossAxisAlignment.start,
///   children: [
///     TextField(...),
///     FieldHint(
///       text: "This is how your band will appear everywhere.",
///       controller: hintController,
///     ),
///   ],
/// )
/// ```
class FieldHint extends StatelessWidget {
  /// The hint text to display
  final String text;

  /// Controller managing visibility state
  final FieldHintController controller;

  const FieldHint({super.key, required this.text, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return AnimatedOpacity(
          opacity: controller.isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: controller.isVisible
                ? Padding(
                    padding: const EdgeInsets.only(
                      top: Spacing.space4,
                      left: Spacing.space4,
                    ),
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

/// A convenience widget that wraps a TextField with an integrated hint.
/// Manages the focus and text change listeners automatically.
class TextFieldWithHint extends StatefulWidget {
  /// The text field widget
  final Widget child;

  /// The hint text to display below the field
  final String? hintText;

  /// The text controller for the field
  final TextEditingController? controller;

  /// The focus node for the field
  final FocusNode? focusNode;

  /// Optional initial value to check if hint should be hidden
  final String? initialValue;

  const TextFieldWithHint({
    super.key,
    required this.child,
    this.hintText,
    this.controller,
    this.focusNode,
    this.initialValue,
  });

  @override
  State<TextFieldWithHint> createState() => _TextFieldWithHintState();
}

class _TextFieldWithHintState extends State<TextFieldWithHint> {
  late final FieldHintController _hintController;
  FocusNode? _internalFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _hintController = FieldHintController();

    // Initialize with initial value state
    final hasInitial =
        (widget.initialValue?.isNotEmpty ?? false) ||
        (widget.controller?.text.isNotEmpty ?? false);
    _hintController.initialize(hasInitialValue: hasInitial);

    // Listen to focus changes
    _focusNode.addListener(_onFocusChange);

    // Listen to text changes
    widget.controller?.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    widget.controller?.removeListener(_onTextChange);
    _internalFocusNode?.dispose();
    _hintController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _hintController.onFocus();
    }
  }

  void _onTextChange() {
    _hintController.onTextChanged(widget.controller?.text ?? '');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hintText == null) {
      return widget.child;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.child,
        FieldHint(text: widget.hintText!, controller: _hintController),
      ],
    );
  }
}
