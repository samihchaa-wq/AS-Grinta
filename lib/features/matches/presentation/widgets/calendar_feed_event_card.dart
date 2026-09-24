import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/theme/calendar_card_palette.dart';
import 'package:as_grinta/core/widgets/calendar_scoreline.dart';
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
      if (changed != true) return;

      // CalendarEntryFormPage invalide déjà clubEventsProvider après une
      // mutation réussie. Attendre le snapshot rafraîchi suffit : la liste
      // conserve alors naturellement son viewport autour de la carte retirée.
      //
      // Ne surtout pas déclencher matchesFocusRequestProvider ici : ce signal
      // sert à un recentrage global du calendrier et peut envoyer l'utilisateur
      // loin de l'événement qu'il vient de supprimer.
      await ref.read(clubEventsProvider.future);
    }

    final editButton = isAdmin
        ? IconButton(
            tooltip: 'Modifier l’événement',
            onPressed: edit,
            color: CalendarCardPalette.eventBorder,
            icon: const Icon(Icons.edit_rounded),
          )
        : null;

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
      child: CalendarCardActionsOverlay(
        actions: editButton,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.cardPadding,
            CalendarCardSpacing.vertical,
            AppSpacing.cardPadding,
            CalendarCardSpacing.vertical,
          ),
          child: MatchDateHeader(
            gap: CalendarCardSpacing.line,
            kickoffAt: event.startsAt,
            foreground: AppTheme.textPrimary,
            secondary: AppTheme.textPrimary,
            dividerColor: CalendarCardPalette.eventBorder,
            dateEndInset:
                editButton != null ? CalendarCardActionsOverlay.dateInset : 0,
            label: 'Événement',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CalendarCenteredTitle(event.title),
                const SizedBox(height: CalendarCardSpacing.line),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        event.location,
                        textAlign: TextAlign.start,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w400,
                                ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
