import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils/layout_constants.dart';

/// Wraps [child] inside a [Shortcuts] that remaps D-pad arrow keys (up/down)
/// to plain focus traversal intents.  Place this as the direct child of a
/// [RadioGroup] to prevent the group from auto-selecting the focused option
/// when the user navigates with a TV remote — selection still fires on Enter.
Widget tvRadioFocusShortcuts({required Widget child}) {
  return Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
      SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
    },
    child: child,
  );
}

/// A Slider widget that handles D-pad navigation properly on TV.
/// Left/Right D-pad adjusts the value, Up/Down D-pad navigates to other focusable elements.
class CustomSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final double step;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final Color? activeColor;
  final Color? inactiveColor;

  const CustomSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.step = 1.0,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  State<CustomSlider> createState() => _CustomSliderState();
}

class _CustomSliderState extends State<CustomSlider> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  bool _isDragging = false;
  Timer? _seekCommitTimer;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _seekCommitTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleDpadSeek(double newValue) {
    if (!_isDragging) {
      _isDragging = true;
      widget.onChangeStart?.call(newValue);
    }
    widget.onChanged?.call(newValue);

    _seekCommitTimer?.cancel();
    _seekCommitTimer = Timer(const Duration(milliseconds: 500), () {
      widget.onChangeEnd?.call(newValue);
      _isDragging = false;
    });
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
          if (newValue != widget.value) {
            _handleDpadSeek(newValue);
          }
          return KeyEventResult.handled;
        }

        // Right arrow: increase value
        if (logicalKey == LogicalKeyboardKey.arrowRight) {
          final newValue = (widget.value + widget.step).clamp(
            widget.min,
            widget.max,
          );
          if (newValue != widget.value) {
            _handleDpadSeek(newValue);
          }
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
        padding: const EdgeInsets.symmetric(
          horizontal: LayoutConstants.spacingXs,
          vertical: 4,
        ),
        child: ExcludeFocus(
          child: Slider(
            value: widget.value.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: widget.onChanged,
            onChangeStart: widget.onChangeStart,
            onChangeEnd: widget.onChangeEnd,
            activeColor:
                widget.activeColor ??
                (_isFocused ? Theme.of(context).colorScheme.primary : null),
            inactiveColor: widget.inactiveColor,
          ),
        ),
      ),
    );
  }
}

/// A TextField widget that allows D-pad navigation out of the text field.
/// Up/Down D-pad navigates to other focusable elements instead of being trapped.
/// When keyboard OK is pressed, focus automatically moves to the next element.
class CustomTextField extends StatefulWidget {
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;

  const CustomTextField({
    super.key,
    this.controller,
    this.decoration,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Define consistent premium borders for the project
    final enabledBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: colorScheme.outline.withValues(alpha: 0.5),
        width: 1,
      ),
    );

    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: colorScheme.primary,
        width: 2,
      ),
    );

    // Merge the provided decoration with our consistent styling
    final effectiveDecoration = (widget.decoration ?? const InputDecoration()).copyWith(
      hintText: widget.hintText ?? widget.decoration?.hintText,
      enabledBorder: widget.decoration?.enabledBorder ?? enabledBorder,
      focusedBorder: widget.decoration?.focusedBorder ?? focusedBorder,
      border: widget.decoration?.border ?? enabledBorder,
    );

    return TextField(
      focusNode: _focusNode,
      controller: widget.controller,
      decoration: effectiveDecoration,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction ?? TextInputAction.done,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
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
class CustomButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool autofocus;
  final bool isPrimary;
  final bool isOutlined;
  final FocusNode? focusNode;
  final Color? backgroundColor;
  final bool showFocusHighlight;
  final OutlinedBorder? shape;

  const CustomButton({
    super.key,
    required this.child,
    this.onPressed,
    this.autofocus = false,
    this.isPrimary = false,
    this.isOutlined = false,
    this.focusNode,
    this.backgroundColor,
    this.showFocusHighlight = true,
    this.shape,
  });

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
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
              ? primaryColor.withValues(alpha: 0.9)
              : (widget.backgroundColor ?? primaryColor),
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          disabledBackgroundColor: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.38),
          side: showHighlight
              ? const BorderSide(color: Colors.white, width: 3)
              : BorderSide.none,
          shadowColor: Colors.transparent,
          shape: widget.shape,
        ),
        child: widget.child,
      );
    }

    return TextButton(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onPressed: widget.onPressed,
      style: TextButton.styleFrom(
        backgroundColor: showHighlight
            ? primaryColor.withValues(alpha: 0.15)
            : null,
        foregroundColor: _isFocused
            ? primaryColor
            : Theme.of(context).colorScheme.onSurfaceVariant,
        disabledForegroundColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.38),
        side: showHighlight
            ? const BorderSide(color: Colors.white, width: 2)
            : (widget.isOutlined
                  ? BorderSide(color: Theme.of(context).colorScheme.outline)
                  : BorderSide.none),
        shape: widget.shape,
      ),
      child: widget.child,
    );
  }
}
