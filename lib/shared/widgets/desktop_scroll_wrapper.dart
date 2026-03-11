import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/utils/layout_constants.dart';

class DesktopScrollWrapper extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  final double scrollAmount;
  final Future<void> Function()? onScrollLeft;
  final Future<void> Function()? onScrollRight;

  /// Whether to show navigation buttons. If null, defaults to true on desktop platforms.
  final bool? showButtons;

  const DesktopScrollWrapper({
    super.key,
    required this.child,
    required this.controller,
    this.scrollAmount = 300.0,
    this.onScrollLeft,
    this.onScrollRight,
    this.showButtons,
  });

  @override
  State<DesktopScrollWrapper> createState() => _DesktopScrollWrapperState();
}

class _DesktopScrollWrapperState extends State<DesktopScrollWrapper> {
  bool _showLeft = false;
  bool _showRight = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateArrows);
    // Initial check after build
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateArrows);
    super.dispose();
  }

  void _updateArrows() {
    if (!widget.controller.hasClients) return;

    final position = widget.controller.position;
    final showLeft = position.pixels > 0;
    final showRight = position.pixels < position.maxScrollExtent;

    if (showLeft != _showLeft || showRight != _showRight) {
      if (mounted) {
        setState(() {
          _showLeft = showLeft;
          _showRight = showRight;
        });
      }
    }
  }

  void _scroll(bool right) {
    if (right && widget.onScrollRight != null) {
      widget.onScrollRight!();
      return;
    }
    if (!right && widget.onScrollLeft != null) {
      widget.onScrollLeft!();
      return;
    }

    if (!widget.controller.hasClients) return;

    final current = widget.controller.offset;
    final target = right
        ? current + widget.scrollAmount
        : current - widget.scrollAmount;

    widget.controller.animateTo(
      target.clamp(0.0, widget.controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  bool get _shouldShowButtons {
    // If explicitly set, use that value
    if (widget.showButtons != null) return widget.showButtons!;
    // Default: show on desktop platforms only
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  @override
  Widget build(BuildContext context) {
    // Only show buttons if enabled
    if (!_shouldShowButtons) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,

        // Left Button
        if (_showLeft)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: _ScrollButton(
                icon: Icons.chevron_left,
                onTap: () => _scroll(false),
              ),
            ),
          ),

        // Right Button
        if (_showRight)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: _ScrollButton(
                icon: Icons.chevron_right,
                onTap: () => _scroll(true),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScrollButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ScrollButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(LayoutConstants.spacingXs),
            child: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}
