import 'package:as_grinta/core/design_system/foundations/grinta_iconography.dart';
import 'package:flutter/material.dart';

/// Shared icon-only action with a consistent visual size and touch target.
class GrintaIconButton extends StatelessWidget {
  const GrintaIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
    this.isSelected = false,
    this.isLoading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isSelected;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      onPressed: isLoading ? null : onPressed,
      tooltip: tooltip,
      constraints: GrintaIconography.controlConstraints,
      style: IconButton.styleFrom(
        backgroundColor: isSelected
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        foregroundColor: isSelected
            ? colorScheme.onPrimary
            : colorScheme.onSurfaceVariant,
      ),
      icon: isLoading
          ? const SizedBox.square(
              dimension: GrintaIconography.inline,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: GrintaIconography.control),
    );
  }
}
