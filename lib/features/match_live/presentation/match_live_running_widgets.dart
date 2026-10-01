part of 'match_live_running_page.dart';

/// Bandeau du direct sur une seule ligne : chrono, commandes du match (en
/// icônes) et tableau d'affichage.
class _LiveHeaderBar extends ConsumerWidget {
  const _LiveHeaderBar({
    required this.bundle,
    required this.canEdit,
    required this.onPause,
    required this.onResume,
    required this.onResumeSecondHalf,
    required this.onHalftime,
    required this.onRestart,
    required this.onEndMatch,
    this.onlyClockAction = false,
    this.showClockAction = true,
    this.bottom,
  });

  final MatchLiveStateBundle bundle;
  final bool canEdit;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onResumeSecondHalf;
  final VoidCallback onHalftime;
  final VoidCallback onRestart;
  final VoidCallback onEndMatch;

  /// Mode match : seul le bouton pause / reprendre reste dans la ligne, les
  /// autres commandes passent sur la seconde ligne ([bottom]).
  final bool onlyClockAction;

  /// Mode match : pause / reprendre passe sur la seconde ligne.
  final bool showClockAction;

  /// Seconde ligne du bandeau (commandes occasionnelles du mode match).
  final Widget? bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = bundle.session;
    final matchId = session.matchId;
    final controller = ref.read(matchLiveStateProvider(matchId).notifier);
    final fixture =
        ref.watch(upcomingMatchFixtureProvider(matchId)).valueOrNull;
    final opponentName = fixture?.opponentName ?? 'Adversaire';
    final grintaIsHome = fixture?.grintaIsHome ?? true;

    _LiveScore team(bool grinta, {bool wide = false}) => _LiveScore(
          wide: wide,
          shortName: grinta ? 'ASG' : _shortName(opponentName),
          fullName: grinta ? 'AS Grinta' : opponentName,
          score: grinta ? session.scoreAsGrinta : session.scoreAdverse,
          canEdit: canEdit,
          onIncrement: () =>
              controller.adjustScore(team: grinta ? 'us' : 'them', delta: 1),
          onDecrement: () =>
              controller.adjustScore(team: grinta ? 'us' : 'them', delta: -1),
        );

    final firstAction = switch (session.state) {
      MatchLiveState.running => (
          tooltip: 'Pause',
          icon: Icons.pause_rounded,
          callback: onPause as VoidCallback?,
          filled: false,
        ),
      MatchLiveState.paused => (
          tooltip: 'Reprendre',
          icon: Icons.play_arrow_rounded,
          callback: onResume as VoidCallback?,
          filled: false,
        ),
      MatchLiveState.halftime => (
          tooltip: 'Reprendre la 2e mi-temps',
          icon: Icons.play_arrow_rounded,
          callback: onResumeSecondHalf as VoidCallback?,
          filled: true,
        ),
      _ => (
          tooltip: 'Pause',
          icon: Icons.pause_rounded,
          callback: null,
          filled: false,
        ),
    };
    final canGoHalftime =
        session.half == 1 && session.state != MatchLiveState.halftime;

    Widget action({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
      bool filled = false,
      bool danger = false,
    }) {
      final scheme = Theme.of(context).colorScheme;
      const size = BoxConstraints.tightFor(width: 36, height: 36);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: filled
            ? IconButton.filled(
                tooltip: tooltip,
                onPressed: onPressed,
                constraints: size,
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Icon(icon),
              )
            : IconButton.outlined(
                tooltip: tooltip,
                onPressed: onPressed,
                constraints: size,
                padding: EdgeInsets.zero,
                iconSize: 20,
                color: danger ? scheme.error : null,
                icon: Icon(icon),
              ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        // Sur un écran étroit, la ligne se réduit d'un bloc plutôt que de
        // passer sur deux lignes.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!showClockAction)
              // Mode match : la ligne ne porte plus que le chrono et le
              // score, étalés sur toute la largeur et agrandis.
              // La hauteur suit les noms d'équipe, qui peuvent passer sur
              // plusieurs lignes ; le score reste aligné en bas.
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Chrono : un cinquième de la ligne.
                  Expanded(
                    child: SizedBox(
                      height: 64,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        child: MatchLiveClock(session: session, compact: true),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Score : les quatre cinquièmes restants.
                  Expanded(
                    flex: 4,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: team(grintaIsHome, wide: true)),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _scoreDash(context),
                        ),
                        Expanded(child: team(!grintaIsHome, wide: true)),
                      ],
                    ),
                  ),
                ],
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 72,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: MatchLiveClock(session: session, compact: true),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (canEdit) ...[
                      if (showClockAction)
                        action(
                          tooltip: firstAction.tooltip,
                          icon: firstAction.icon,
                          onPressed: firstAction.callback,
                          filled: firstAction.filled,
                        ),
                      if (!onlyClockAction) ...[
                        action(
                          tooltip: 'Mi-temps',
                          icon: Icons.sports_rounded,
                          onPressed: canGoHalftime ? onHalftime : null,
                        ),
                        action(
                          tooltip: 'Recommencer',
                          icon: Icons.restart_alt_rounded,
                          onPressed: onRestart,
                        ),
                        action(
                          tooltip: 'Fin du match',
                          icon: Icons.flag_rounded,
                          onPressed: onEndMatch,
                          danger: true,
                        ),
                      ],
                      const SizedBox(width: 8),
                    ],
                    team(grintaIsHome),
                    _scoreDash(context),
                    team(!grintaIsHome),
                  ],
                ),
              ),
            if (bottom != null) ...[
              const Divider(height: 12),
              bottom!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Commande de la seconde ligne du mode match : icône et petit libellé.
class _MatchModeAction extends StatelessWidget {
  const _MatchModeAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.danger = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool danger;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final color = !enabled
        ? scheme.onSurface.withValues(alpha: .38)
        : danger
            ? scheme.error
            : scheme.onSurface;
    return Expanded(
      child: Tooltip(
        message: tooltip ?? label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge.count(
                  count: badgeCount,
                  isLabelVisible: badgeCount > 0,
                  child: Icon(icon, size: 22, color: color),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre du bas du mode match : un but d'AS Grinta attend son buteur.
class _GoalToAttributeBar extends StatelessWidget {
  const _GoalToAttributeBar({required this.event, required this.onChoose});

  final MatchLiveEvent event;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.sports_soccer_rounded),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'But à la ${AppFormats.ordinalFeminine(event.minute)} '
                'minute · buteur à désigner',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: onChoose, child: const Text('Choisir')),
          ],
        ),
      ),
    );
  }
}

/// Petit bouton du pied de la colonne du banc : icône et libellé.
class _BenchAction extends StatelessWidget {
  const _BenchAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = onPressed == null
        ? scheme.onSurface.withValues(alpha: .38)
        : scheme.onSurface;
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiret du tableau d'affichage, aligné sur les scores (sous les sigles).
Widget _scoreDash(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(' ', style: Theme.of(context).textTheme.labelSmall),
          Text('–', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    );

/// Trois premières lettres du nom, en capitales (« TOU » pour Toulouse).
String _shortName(String name) {
  final letters = name.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
  if (letters.isEmpty) return 'ADV';
  return letters
      .substring(0, letters.length < 3 ? letters.length : 3)
      .toUpperCase();
}

/// Score d'une équipe dans le bandeau : sigle, puis « − », score et « + ».
class _LiveScore extends StatelessWidget {
  const _LiveScore({
    required this.shortName,
    required this.fullName,
    required this.score,
    required this.canEdit,
    required this.onIncrement,
    required this.onDecrement,
    this.wide = false,
  });

  /// Mode match : « − », score et « + » répartis sur toute la largeur
  /// disponible, score en grand.
  final bool wide;

  final String shortName;
  final String fullName;
  final int score;
  final bool canEdit;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = Text(
      '$score',
      style:
          (wide ? theme.textTheme.displaySmall : theme.textTheme.headlineSmall)
              ?.copyWith(
        fontWeight: FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final buttonSize = wide ? 36.0 : 30.0;
    final iconSize = wide ? 28.0 : 22.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mode match : nom complet en blanc, sur toute la largeur de son bloc
        // (du « − » au « + »), réduit s'il est trop long.
        if (wide)
          // Même règle que le calendrier : taille et écriture fixes, retour
          // à la ligne équilibré si le nom ne tient pas.
          SizedBox(
            width: double.infinity,
            child: CalendarTeamName(name: fullName, color: Colors.white),
          )
        else
          Text(
            shortName,
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: .5),
          ),
        Row(
          mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment:
              wide ? MainAxisAlignment.spaceEvenly : MainAxisAlignment.center,
          children: [
            if (canEdit)
              IconButton(
                tooltip: 'Retirer un but à $fullName',
                onPressed: score > 0 ? onDecrement : null,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: buttonSize,
                  height: buttonSize,
                ),
                iconSize: iconSize,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
            // Le score rétrécit plutôt que de déborder si la place manque.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: number,
                ),
              ),
            ),
            if (canEdit)
              IconButton(
                tooltip: 'Ajouter un but à $fullName',
                onPressed: onIncrement,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: buttonSize,
                  height: buttonSize,
                ),
                iconSize: iconSize,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
          ],
        ),
      ],
    );
  }
}

const double _benchGap = AppSpacing.contentGap;
const double _benchColumnMargin = AppSpacing.compactCardPadding;

FormationMarkerMetrics benchAndPitchMetrics(double availableWidth) {
  final pitchWidth =
      (availableWidth - _benchGap - _benchColumnMargin) * 5.6 / 6.6;
  return FormationMarkerMetrics.forPitch(pitchWidth);
}

double benchColumnWidth(FormationMarkerMetrics metrics) =>
    metrics.width + _benchColumnMargin;

class _BenchColumn extends StatelessWidget {
  const _BenchColumn({
    required this.bench,
    required this.bundle,
    required this.canEdit,
    required this.metrics,
    required this.pendingOutIds,
    required this.onFieldPlayerDropped,
    this.footer,
  });

  /// Actions collées en bas de la colonne (Ajouter / Retirer en mode match).
  final Widget? footer;

  final List<MatchCompositionEntry> bench;
  final MatchLiveStateBundle bundle;
  final bool canEdit;
  final FormationMarkerMetrics metrics;
  final Set<String> pendingOutIds;
  final void Function(MatchCompositionEntry, MatchCompositionEntry)
      onFieldPlayerDropped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastExits = lastExitMarksByParticipant(bundle.events);
    return SizedBox(
      width: metrics.width + _benchColumnMargin,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _benchColumnMargin / 2,
            vertical: 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (bench.isEmpty)
                Text(
                  'Personne',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final entry in bench)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DragTarget<MatchCompositionEntry>(
                      onWillAcceptWithDetails: (details) =>
                          canEdit &&
                          details.data.zone == MatchCompositionZone.field,
                      onAcceptWithDetails: (details) =>
                          onFieldPlayerDropped(details.data, entry),
                      builder: (context, candidates, rejected) {
                        final isPendingOut = pendingOutIds.contains(
                          entry.participantId,
                        );
                        return LiveBenchTile(
                          outlineColor: candidates.isNotEmpty
                              ? theme.colorScheme.primary
                              : isPendingOut
                                  ? theme.colorScheme.error
                                  : Colors.transparent,
                          entry: entry,
                          draggable: canEdit,
                          metrics: metrics,
                          timesBenched: bundle.timesBenched(
                            entry.participantId,
                          ),
                          lastExit: lastExits[entry.participantId],
                          namesOnly: true,
                        );
                      },
                    ),
                  ),
              if (footer != null) ...[const Spacer(), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingSubstitutions extends StatelessWidget {
  const _PendingSubstitutions({
    required this.pending,
    required this.nameOf,
    required this.busy,
    required this.onRemove,
    required this.onClear,
    required this.onValidate,
  });

  final List<PendingSubstitution> pending;
  final String Function(String participantId) nameOf;
  final bool busy;
  final ValueChanged<PendingSubstitution> onRemove;
  final VoidCallback onClear;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.compactCardPadding,
          10,
          AppSpacing.compactCardPadding,
          10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.swap_horiz_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppSpacing.contentGap),
                Expanded(
                  child: Text(
                    pending.length == 1
                        ? 'Changement en attente'
                        : '${pending.length} changements en attente',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final pair in pending)
              Row(
                children: [
                  Expanded(
                    child: LiveSubstitutionLine(
                      playerInName: nameOf(pair.playerIn),
                      playerOutName: nameOf(pair.playerOut),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Annuler ce changement',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.undo_rounded),
                    onPressed: busy ? null : () => onRemove(pair),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.microGap),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onClear,
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: AppSpacing.contentGap),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onValidate,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: GrintaProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      pending.length == 1
                          ? 'Valider'
                          : 'Valider (${pending.length})',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _JournalAction { scorer, assist, delete }

class _LiveJournal extends StatelessWidget {
  const _LiveJournal({
    super.key,
    required this.events,
    required this.expanded,
    required this.canEdit,
    required this.onExpandedChanged,
    required this.onEditScorer,
    required this.onEditAssist,
    required this.onDelete,
    this.plain = false,
    this.title = 'Journal du match',
    this.emptyText = 'Aucun événement pour le moment.',
  });

  /// Vue spectateur : ni encadrés de salve ni repères « passage.série ».
  final bool plain;
  final String title;
  final String emptyText;

  final List<MatchLiveEvent> events;
  final bool expanded;
  final bool canEdit;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<MatchLiveEvent> onEditScorer;
  final ValueChanged<MatchLiveEvent> onEditAssist;
  final ValueChanged<MatchLiveEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final ordered = events.reversed.toList();
    final latest = ordered.isEmpty ? null : ordered.first;
    final salvos = plain
        ? <MatchLiveEvent, SubstitutionSalvo>{}
        : substitutionSalvosByEvent(events);
    final marks = plain
        ? <MatchLiveEvent, SubstitutionExitMark>{}
        : substitutionExitMarksByEvent(events);

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => onExpandedChanged(!expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.cardPadding,
                vertical: AppSpacing.compactCardPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.receipt_long_rounded),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                          ),
                    ),
                  ),
                  if (events.isNotEmpty)
                    Text(
                      '${events.length}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  const SizedBox(width: AppSpacing.microGap),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                ],
              ),
            ),
          ),
          if (latest == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                0,
                AppSpacing.cardPadding,
                AppSpacing.cardPadding,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(emptyText),
              ),
            )
          else if (!expanded) ...[
            const Divider(height: 1),
            _framed(
              salvos[latest],
              _JournalEventRow(
                event: latest,
                mark: marks[latest],
                canEdit: false,
                canEditScorer: canEdit,
                onEditScorer: onEditScorer,
                onEditAssist: onEditAssist,
                onDelete: onDelete,
              ),
            ),
          ] else ...[
            const Divider(height: 1),
            ..._expandedRows(ordered, salvos, marks),
          ],
        ],
      ),
    );
  }

  Widget _framed(SubstitutionSalvo? salvo, Widget child) => salvo == null
      ? child
      : SubstitutionSalvoFrame(
          salvo: salvo,
          margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: child,
        );

  /// Liste dépliée : les remplacements consécutifs d'une même salve partagent
  /// un encadré coloré, les autres lignes restent séparées par un trait.
  List<Widget> _expandedRows(
    List<MatchLiveEvent> ordered,
    Map<MatchLiveEvent, SubstitutionSalvo> salvos,
    Map<MatchLiveEvent, SubstitutionExitMark> marks,
  ) {
    Widget row(MatchLiveEvent event) => _JournalEventRow(
          event: event,
          mark: marks[event],
          canEdit: canEdit,
          canEditScorer: canEdit,
          onEditScorer: onEditScorer,
          onEditAssist: onEditAssist,
          onDelete: onDelete,
        );

    final widgets = <Widget>[];
    var index = 0;
    while (index < ordered.length) {
      if (widgets.isNotEmpty) {
        widgets.add(const Divider(height: 1, indent: 48));
      }
      final salvo = salvos[ordered[index]];
      if (salvo == null) {
        widgets.add(row(ordered[index]));
        index += 1;
        continue;
      }
      final group = <Widget>[];
      while (
          index < ordered.length && identical(salvos[ordered[index]], salvo)) {
        group.add(row(ordered[index]));
        index += 1;
      }
      widgets.add(_framed(salvo, Column(children: group)));
    }
    return widgets;
  }
}

class _JournalEventRow extends StatelessWidget {
  const _JournalEventRow({
    required this.event,
    this.mark,
    required this.canEdit,
    required this.canEditScorer,
    required this.onEditScorer,
    required this.onEditAssist,
    required this.onDelete,
  });

  final MatchLiveEvent event;

  /// Repère du joueur qui sort : il remplace l'icône. `null` sur un but.
  final SubstitutionExitMark? mark;
  final bool canEdit;
  final bool canEditScorer;
  final ValueChanged<MatchLiveEvent> onEditScorer;
  final ValueChanged<MatchLiveEvent> onEditAssist;
  final ValueChanged<MatchLiveEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = switch (event.type) {
      MatchLiveEventType.goalUs => (
          Icons.sports_soccer_rounded,
          theme.colorScheme.onSurface,
          event.isOpponentOwnGoal
              ? 'But AS Grinta · CSC adverse'
              : 'But AS Grinta · ${event.scorerName ?? 'Buteur à désigner'}'
                  '${event.assistName == null ? '' : ' · passe ${event.assistName}'}',
        ),
      MatchLiveEventType.goalThem => (
          Icons.sports_soccer_outlined,
          theme.colorScheme.error,
          'But adverse',
        ),
      MatchLiveEventType.substitution => (
          Icons.swap_horiz_rounded,
          theme.colorScheme.secondary,
          '${event.playerInName ?? '?'} entre · '
              '${event.playerOutName ?? '?'} sort',
        ),
    };
    final hasScore =
        event.scoreAsGrintaAfter != null && event.scoreAdverseAfter != null;
    final canChooseScorer = canEditScorer &&
        event.type == MatchLiveEventType.goalUs &&
        event.needsScorer;
    final isSubstitution = event.type == MatchLiveEventType.substitution;
    final isOpponentGoal = event.type == MatchLiveEventType.goalThem;
    final goalIndent =
        (MediaQuery.sizeOf(context).width * .12).clamp(36.0, 64.0).toDouble();

    Widget actions() => PopupMenuButton<_JournalAction>(
          tooltip: 'Corriger',
          onSelected: (action) {
            switch (action) {
              case _JournalAction.scorer:
                onEditScorer(event);
              case _JournalAction.assist:
                onEditAssist(event);
              case _JournalAction.delete:
                onDelete(event);
            }
          },
          itemBuilder: (context) => [
            if (event.type == MatchLiveEventType.goalUs)
              PopupMenuItem(
                value: _JournalAction.scorer,
                child: Row(
                  children: [
                    const Icon(Icons.person_search_rounded),
                    const SizedBox(width: AppSpacing.contentGap),
                    Text(
                      event.needsScorer
                          ? 'Choisir le buteur'
                          : 'Corriger le buteur',
                    ),
                  ],
                ),
              ),
            if (event.type == MatchLiveEventType.goalUs &&
                event.scorerParticipantId != null)
              PopupMenuItem(
                value: _JournalAction.assist,
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined),
                    const SizedBox(width: AppSpacing.contentGap),
                    Text(
                      event.assistName == null
                          ? 'Ajouter la passe décisive'
                          : 'Corriger la passe décisive',
                    ),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: _JournalAction.delete,
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded),
                  SizedBox(width: AppSpacing.contentGap),
                  Text('Retirer'),
                ],
              ),
            ),
          ],
        );

    if (isSubstitution) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              child: mark == null ? null : SubstitutionExitBadge(mark: mark!),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: LiveSubstitutionLine(
                playerInName: event.playerInName ?? '?',
                playerOutName: event.playerOutName ?? '?',
              ),
            ),
            const SizedBox(width: 4),
            Text(
              "${event.minute}'",
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
            if (canEdit) ...[
              const SizedBox(width: 2),
              actions(),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: isOpponentGoal
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: isOpponentGoal ? 0 : goalIndent,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: canChooseScorer ? () => onEditScorer(event) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(icon, size: 20, color: color),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * .52,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: isOpponentGoal
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: isOpponentGoal
                                        ? TextAlign.right
                                        : TextAlign.left,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  if (hasScore)
                                    Text(
                                      '${event.scoreAsGrintaAfter}-'
                                      '${event.scoreAdverseAfter}',
                                      textAlign: isOpponentGoal
                                          ? TextAlign.right
                                          : TextAlign.left,
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                "${event.minute}'",
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: 2),
                actions(),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

/// Vue spectateur du direct : pour tous ceux qui ne pilotent pas.
///
/// Chrono et score sur une ligne, composition en direct avec les ballons
/// (buts) et chaussures (passes décisives) comme sur la fiche d'après-match,
/// puis le journal, sans les repères réservés au pilote.
class MatchLiveSpectatorView extends ConsumerStatefulWidget {
  const MatchLiveSpectatorView({
    super.key,
    required this.bundle,
    this.header,
  });

  final MatchLiveStateBundle bundle;

  /// Bandeau au-dessus du direct (pour un coach : piloter / prendre la main).
  final Widget? header;

  @override
  ConsumerState<MatchLiveSpectatorView> createState() =>
      _MatchLiveSpectatorViewState();
}

class _MatchLiveSpectatorViewState
    extends ConsumerState<MatchLiveSpectatorView> {
  bool _journalExpanded = true;

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;
    final session = bundle.session;
    final fixture =
        ref.watch(upcomingMatchFixtureProvider(session.matchId)).valueOrNull;
    final opponentName = fixture?.opponentName ?? 'Adversaire';
    final grintaIsHome = fixture?.grintaIsHome ?? true;
    final lineup = bundle.lineup;

    _LiveScore team(bool grinta) => _LiveScore(
          shortName: grinta ? 'ASG' : _shortName(opponentName),
          fullName: grinta ? 'AS Grinta' : opponentName,
          score: grinta ? session.scoreAsGrinta : session.scoreAdverse,
          canEdit: false,
          wide: true,
          onIncrement: () {},
          onDecrement: () {},
        );

    // Buts et passes décisives de chaque joueur, pour les ballons et les
    // chaussures sur la composition.
    final goals = <String, int>{};
    final assists = <String, int>{};
    for (final event in bundle.events) {
      if (event.type != MatchLiveEventType.goalUs) continue;
      final scorer = event.scorerParticipantId;
      final assist = event.assistParticipantId;
      if (scorer != null) goals[scorer] = (goals[scorer] ?? 0) + 1;
      if (assist != null) assists[assist] = (assists[assist] ?? 0) + 1;
    }
    List<MatchCompositionEntry> withStats(MatchCompositionZone zone) => [
          for (final entry in lineup?.entriesFor(zone) ?? const [])
            entry.copyWith(
              goals: goals[entry.participantId] ?? 0,
              assists: assists[entry.participantId] ?? 0,
            ),
        ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.liveScreenGutter,
        AppSpacing.sectionGap,
        AppSpacing.liveScreenGutter,
        32,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        if (widget.header != null) ...[
          widget.header!,
          const SizedBox(height: 10),
        ],
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            // Même ligne que le pilote : chrono sur un cinquième, noms
            // complets des équipes et score sur le reste.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: SizedBox(
                    height: 64,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      child: MatchLiveClock(session: session, compact: true),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: team(grintaIsHome)),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _scoreDash(context),
                      ),
                      Expanded(child: team(!grintaIsHome)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        // Composition dessinée à taille fixe : sans ce plafond, le grossissement
        // de texte de l'application faisait déborder les prénoms d'un pixel.
        if (lineup != null)
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1,
            child: CompositionPitchWithBench(
              field: withStats(MatchCompositionZone.field),
              bench: withStats(MatchCompositionZone.bench),
            ),
          ),
        const SizedBox(height: AppSpacing.sectionGap),
        // Spectateur : seulement les buts.
        _LiveJournal(
          events: [
            for (final event in bundle.events)
              if (event.type != MatchLiveEventType.substitution) event,
          ],
          expanded: _journalExpanded,
          canEdit: false,
          plain: true,
          title: 'Faits de match',
          emptyText: 'Aucun but pour le moment.',
          onExpandedChanged: (value) =>
              setState(() => _journalExpanded = value),
          onEditScorer: (_) {},
          onEditAssist: (_) {},
          onDelete: (_) {},
        ),
      ],
    );
  }
}
