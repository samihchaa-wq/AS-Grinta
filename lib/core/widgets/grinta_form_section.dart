import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class GrintaFormSection extends StatelessWidget {
  const GrintaFormSection({
    super.key,
    required this.children,
    this.title,
    this.description,
    this.trailing,
    this.padding = const EdgeInsets.all(AppTheme.spaceMd),
  });

  final String? title;
  final String? description;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: .34),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || trailing != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title case final value?)
                  Expanded(
                    child: Text(
                      value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
          if (description case final value? when value.trim().isNotEmpty) ...[
            if (title != null || trailing != null) const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.textFaint,
                height: 1.4,
              ),
            ),
          ],
          if (title != null || description != null || trailing != null)
            const SizedBox(height: AppTheme.spaceMd),
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const SizedBox(height: AppTheme.spaceMd),
          ],
        ],
      ),
    );
  }
}
