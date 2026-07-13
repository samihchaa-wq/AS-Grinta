import 'package:as_grinta/core/design_system/components/grinta_surface.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_iconography.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_radii.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_spacing.dart';
import 'package:flutter/material.dart';

/// Reusable content card with a consistent internal hierarchy.
///
/// The card remains intentionally neutral. Feature-specific color, gradients
/// and decorative effects should not be added unless they encode information.
class GrintaCard extends StatelessWidget {
  const GrintaCard({
    required this.child,
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.level = GrintaSurfaceLevel.raised,
    this.padding = GrintaSpacing.cardInsets,
    this.margin,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final GrintaSurfaceLevel level;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  bool get _hasHeader {
    return title != null || subtitle != null || leading != null || trailing != null;
  }

  @override
  Widget build(BuildContext context) {
    final content = GrintaSurface(
      level: level,
      padding: padding,
      margin: margin,
      borderRadius: GrintaRadii.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasHeader) ...[
            _CardHeader(
              title: title,
              subtitle: subtitle,
              leading: leading,
              trailing: trailing,
            ),
            const SizedBox(height: GrintaSpacing.contentGap),
          ],
          child,
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: GrintaRadii.cardRadius,
          child: content,
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[
          SizedBox(
            width: GrintaIconography.touchTarget,
            height: GrintaIconography.touchTarget,
            child: Center(child: leading),
          ),
          const SizedBox(width: GrintaSpacing.inlineGap),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Text(
                  title!,
                  style: textTheme.titleMedium,
                ),
              if (subtitle != null) ...[
                const SizedBox(height: GrintaSpacing.space1),
                Text(
                  subtitle!,
                  style: textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: GrintaSpacing.inlineGap),
          trailing!,
        ],
      ],
    );
  }
}
