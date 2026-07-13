import 'package:as_grinta/core/design_system/foundations/grinta_iconography.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_spacing.dart';
import 'package:flutter/material.dart';

/// Compact loading indicator for controls and inline content.
class GrintaLoadingIndicator extends StatelessWidget {
  const GrintaLoadingIndicator({super.key, this.label, this.centered = true});

  final String? label;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: GrintaIconography.sizeXl,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        if (label != null) ...[
          const SizedBox(height: GrintaSpacing.contentGap),
          Text(
            label!,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (!centered) {
      return content;
    }

    return Center(child: content);
  }
}

/// Placeholder preserving layout while content is loading.
class GrintaSkeleton extends StatelessWidget {
  const GrintaSkeleton({
    super.key,
    this.width,
    this.height = GrintaSpacing.space4,
    this.borderRadius = 6,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Chargement',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}
