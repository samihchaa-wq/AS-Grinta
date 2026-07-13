import 'package:as_grinta/core/design_system/components/grinta_surface.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_colors.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_iconography.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_radii.dart';
import 'package:as_grinta/core/design_system/foundations/grinta_spacing.dart';
import 'package:flutter/material.dart';

/// Semantic feedback states available to the interface.
enum GrintaStatusTone { info, success, warning, danger }

/// Shared inline feedback message for forms and content sections.
class GrintaStatusMessage extends StatelessWidget {
  const GrintaStatusMessage({
    required this.message,
    super.key,
    this.title,
    this.tone = GrintaStatusTone.info,
    this.action,
  });

  final String message;
  final String? title;
  final GrintaStatusTone tone;
  final Widget? action;

  Color get _foregroundColor {
    return switch (tone) {
      GrintaStatusTone.info => GrintaColors.statusInfo,
      GrintaStatusTone.success => GrintaColors.statusSuccess,
      GrintaStatusTone.warning => GrintaColors.statusWarning,
      GrintaStatusTone.danger => GrintaColors.statusDanger,
    };
  }

  Color get _backgroundColor {
    return switch (tone) {
      GrintaStatusTone.info => GrintaColors.statusInfoSoft,
      GrintaStatusTone.success => GrintaColors.statusSuccessSoft,
      GrintaStatusTone.warning => GrintaColors.statusWarningSoft,
      GrintaStatusTone.danger => GrintaColors.statusDangerSoft,
    };
  }

  IconData get _icon {
    return switch (tone) {
      GrintaStatusTone.info => Icons.info_outline,
      GrintaStatusTone.success => Icons.check_circle_outline,
      GrintaStatusTone.warning => Icons.warning_amber_rounded,
      GrintaStatusTone.danger => Icons.error_outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return GrintaSurface(
      level: GrintaSurfaceLevel.raised,
      padding: GrintaSpacing.compactCardInsets,
      borderRadius: GrintaRadii.controlRadius,
      showBorder: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: GrintaRadii.controlRadius,
        ),
        child: Padding(
          padding: GrintaSpacing.compactCardInsets,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _icon,
                size: GrintaIconography.control,
                color: _foregroundColor,
              ),
              const SizedBox(width: GrintaSpacing.inlineGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(title!, style: textTheme.titleSmall),
                      const SizedBox(height: GrintaSpacing.space1),
                    ],
                    Text(message, style: textTheme.bodyMedium),
                    if (action != null) ...[
                      const SizedBox(height: GrintaSpacing.controlGap),
                      action!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
