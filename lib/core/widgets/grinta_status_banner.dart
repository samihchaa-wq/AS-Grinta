import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

enum GrintaStatusTone { info, success, warning, error }

class GrintaStatusBanner extends StatelessWidget {
  const GrintaStatusBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = GrintaStatusTone.info,
    this.action,
    this.compact = false,
  });

  final String? title;
  final String message;
  final GrintaStatusTone tone;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (accent, icon) = switch (tone) {
      GrintaStatusTone.info =>
        (AppTheme.primaryBright, Icons.info_outline_rounded),
      GrintaStatusTone.success =>
        (AppTheme.success, Icons.check_circle_outline_rounded),
      GrintaStatusTone.warning =>
        (AppTheme.warning, Icons.warning_amber_rounded),
      GrintaStatusTone.error =>
        (theme.colorScheme.error, Icons.error_outline_rounded),
    };

    return Semantics(
      container: true,
      liveRegion: tone == GrintaStatusTone.error,
      label: [if (title != null) title!, message].join('. '),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 16,
          vertical: compact ? 12 : 14,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: accent.withValues(alpha: .24)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 32 : 36,
              height: compact ? 32 : 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: compact ? 18 : 20, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title case final value? when value.trim().isNotEmpty) ...[
                    Text(
                      value,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 10),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
