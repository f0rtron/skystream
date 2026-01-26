import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A Slider widget that handles D-pad navigation properly on TV.
/// Left/Right D-pad adjusts the value, Up/Down D-pad navigates to other focusable elements.
class TvSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final double step;

  const TvSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.onChanged,
    this.step = 1.0,
  });

  @override
  State<TvSlider> createState() => _TvSliderState();
}

class _TvSliderState extends State<TvSlider> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }

        final logicalKey = event.logicalKey;

        // Left arrow: decrease value
        if (logicalKey == LogicalKeyboardKey.arrowLeft) {
          final newValue = (widget.value - widget.step).clamp(
            widget.min,
            widget.max,
          );
          widget.onChanged?.call(newValue);
          return KeyEventResult.handled;
        }

        // Right arrow: increase value
        if (logicalKey == LogicalKeyboardKey.arrowRight) {
          final newValue = (widget.value + widget.step).clamp(
            widget.min,
            widget.max,
          );
          widget.onChanged?.call(newValue);
          return KeyEventResult.handled;
        }

        // Up arrow: move focus up
        if (logicalKey == LogicalKeyboardKey.arrowUp) {
          FocusScope.of(context).focusInDirection(TraversalDirection.up);
          return KeyEventResult.handled;
        }

        // Down arrow: move focus down
        if (logicalKey == LogicalKeyboardKey.arrowDown) {
          FocusScope.of(context).focusInDirection(TraversalDirection.down);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: _isFocused
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : Border.all(color: Colors.transparent, width: 2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ExcludeFocus(
          child: Slider(
            value: widget.value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );
  }
}

/// A TextField widget that allows D-pad navigation out of the text field.
/// Up/Down D-pad navigates to other focusable elements instead of being trapped.
/// When keyboard OK is pressed, focus automatically moves to the next element.
class TvTextField extends StatefulWidget {
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? hintText;

  const TvTextField({
    super.key,
    this.controller,
    this.decoration,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
    this.hintText,
  });

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final key = event.logicalKey;

        // Up arrow: move focus to previous element
        if (key == LogicalKeyboardKey.arrowUp) {
          _moveFocusPrevious();
          return KeyEventResult.handled;
        }

        // Down arrow: move focus to next element
        if (key == LogicalKeyboardKey.arrowDown) {
          _moveFocusNext();
          return KeyEventResult.handled;
        }

        // Let left/right pass through for text cursor navigation
        return KeyEventResult.ignored;
      },
    );
  }

  void _moveFocusNext() {
    // Temporarily make this node non-focusable to prevent cycling back
    _focusNode.unfocus();
    _focusNode.canRequestFocus = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).nextFocus();
        // Re-enable focus after a delay
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _focusNode.canRequestFocus = true;
        });
      }
    });
  }

  void _moveFocusPrevious() {
    // Temporarily make this node non-focusable to prevent cycling back
    _focusNode.unfocus();
    _focusNode.canRequestFocus = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).previousFocus();
        // Re-enable focus after a delay
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _focusNode.canRequestFocus = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      focusNode: _focusNode,
      controller: widget.controller,
      decoration:
          widget.decoration ??
          InputDecoration(
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
          ),
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction ?? TextInputAction.done,
      onSubmitted: (value) {
        // Call user callback first
        widget.onSubmitted?.call(value);
        // Then move focus to next element (the buttons)
        _moveFocusNext();
      },
    );
  }
}

/// A styled button for TV that shows focus state clearly with proper Material Design styling.
class TvButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool autofocus;
  final bool isPrimary;
  final bool isOutlined;
  final FocusNode? focusNode;
  final Color? backgroundColor;
  final bool showFocusHighlight;

  const TvButton({
    super.key,
    required this.child,
    this.onPressed,
    this.autofocus = false,
    this.isPrimary = false,
    this.isOutlined = false,
    this.focusNode,
    this.backgroundColor,
    this.showFocusHighlight = true,
  });

  @override
  State<TvButton> createState() => _TvButtonState();
}

class _TvButtonState extends State<TvButton> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final showHighlight = _isFocused && widget.showFocusHighlight;

    // Use Material 3 button with custom focus highlight
    if (widget.isPrimary) {
      return FilledButton(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onPressed: widget.onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: showHighlight
              ? primaryColor.withValues(alpha: 0.8)
              : (widget.backgroundColor ?? primaryColor),
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          side: showHighlight
              ? const BorderSide(color: Colors.white, width: 3)
              : BorderSide.none,
          elevation: showHighlight ? 8 : 2,
          shadowColor: primaryColor.withValues(alpha: 0.5),
        ),
        child: widget.child,
      );
    }

    return TextButton(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onPressed: widget.onPressed,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: showHighlight
            ? primaryColor.withValues(alpha: 0.15)
            : null,
        side: showHighlight
            ? BorderSide(color: primaryColor, width: 2)
            : (widget.isOutlined
                  ? BorderSide(color: Theme.of(context).colorScheme.outline)
                  : BorderSide.none),
      ),
      child: widget.child,
    );
  }
}
