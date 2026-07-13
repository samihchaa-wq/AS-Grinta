import 'package:as_grinta/core/design_system/foundations/grinta_iconography.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_spacing.dart';
import 'package:flutter/material.dart';

/// Visual hierarchy available to application actions.
enum GrintaButtonVariant { primary, secondary, tertiary, destructive }

/// Shared action button for the Ma Petite Grinta interface.
///
/// Loading keeps the control dimensions stable and disables repeated actions.
class GrintaButton extends StatelessWidget {
  const GrintaButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = GrintaButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final GrintaButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool expand;

  VoidCallback? get _effectiveOnPressed {
    return isLoading ? null : onPressed;
  }

  Widget get _content {
    if (isLoading) {
      return const SizedBox.square(
        dimension: GrintaIconography.inline,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (icon == null) {
      return Text(label);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: GrintaIconography.inline),
        const SizedBox(width: GrintaSpacing.iconGap),
        Text(label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final button = switch (variant) {
      GrintaButtonVariant.primary => FilledButton(
        onPressed: _effectiveOnPressed,
        child: _content,
      ),
      GrintaButtonVariant.secondary => OutlinedButton(
        onPressed: _effectiveOnPressed,
        child: _content,
      ),
      GrintaButtonVariant.tertiary => TextButton(
        onPressed: _effectiveOnPressed,
        child: _content,
      ),
      GrintaButtonVariant.destructive => FilledButton(
        onPressed: _effectiveOnPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        child: _content,
      ),
    };

    if (!expand) {
      return button;
    }

    return SizedBox(width: double.infinity, child: button);
  }
}
