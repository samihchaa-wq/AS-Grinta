import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/features/matches/data/club_events_repository.dart';
import 'package:as_grinta/features/matches/domain/club_event.dart';
import 'package:as_grinta/features/matches/presentation/calendar_entry_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Carte événement dédiée au flux « Défilé » du calendrier.
class CalendarFeedEventCard extends ConsumerWidget {
  const CalendarFeedEventCard({
    super.key,
    required this.event,
    this.isAdmin = false,
  });

  final ClubEvent event;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> edit() async {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => CalendarEntryFormPage(event: event)),
      );
      if (changed == true) ref.invalidate(clubEventsProvider);
    }

    return Card(
      color: CalendarCardPalette.eventSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: const BorderSide(
          color: CalendarCardPalette.eventBorder,
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.cardPadding,
          12,
          AppSpacing.cardPadding,
          13,
        ),
        child: MatchDateHeader(
          kickoffAt: event.startsAt,
          foreground: AppTheme.textPrimary,
          secondary: AppTheme.textPrimary,
          dividerColor: CalendarCardPalette.eventBorder,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      textAlign: TextAlign.start,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontSize: 16,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 16,
                          color: CalendarCardPalette.eventBorder,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            event.location,
                            textAlign: TextAlign.start,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Événement',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: CalendarCardPalette.eventBorder,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: AppSpacing.microGap),
                SizedBox(
                  width: 36,
                  child: IconButton(
                    tooltip: 'Modifier l’événement',
                    onPressed: edit,
                    color: CalendarCardPalette.eventBorder,
                    icon: const Icon(Icons.edit_rounded),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
