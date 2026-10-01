import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_bench_tile.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:flutter/material.dart';

/// Terrain + dispositif + banc, en glisser-déposer.
///
/// C'est le bloc que le coach voit juste avant de lancer le Live ; le compte
/// rendu d'après-match réutilise exactement le même, pour que corriger un
/// effectif se fasse avec les gestes déjà connus. La différence est ailleurs :
/// avant le coup d'envoi chaque geste part au serveur, dans le compte rendu il
/// reste local jusqu'à la validation globale.
class MatchSquadEditor extends StatelessWidget {
  const MatchSquadEditor({
    super.key,
    required this.lineup,
    required this.editable,
    required this.onDroppedOnSlot,
    required this.onMoveToBench,
    this.onRemoveFromSquad,
    this.onFormationChanged,
    this.formationBusy = false,
    this.timesBenched = const {},
    this.header,
    this.benchLabel = 'Banc',
    this.namesOnly = false,
  });

  final MatchComposition lineup;
  final bool editable;
  final void Function(MatchCompositionEntry entry, FootballFormationSlot slot)
      onDroppedOnSlot;
  final ValueChanged<MatchCompositionEntry> onMoveToBench;

  /// Sortir un joueur du match. `null` masque l'action : avant le coup
  /// d'envoi, on ne « retire » pas, on renvoie sur le banc.
  final ValueChanged<MatchCompositionEntry>? onRemoveFromSquad;

  final ValueChanged<String>? onFormationChanged;
  final bool formationBusy;
  final Map<String, int> timesBenched;

  /// Bandeau libre inséré au-dessus du dispositif (consigne, alerte…).
  final Widget? header;
  final String benchLabel;

  /// Prénoms seuls, sans pastilles d'initiales ni photos (module Live).
  final bool namesOnly;

  static const double _benchGap = AppSpacing.contentGap;
  static const double _benchMargin = AppSpacing.compactCardPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Banc à gauche, terrain à droite, comme dans le direct : le terrain
        // prend la largeur restante et les vignettes du banc reprennent la
        // taille des joueurs du terrain.
        final pitchWidth =
            (constraints.maxWidth - _benchGap - _benchMargin) * 5.6 / 6.6;
        final metrics = FormationMarkerMetrics.forPitch(
          pitchWidth.clamp(0.0, 540.0).toDouble(),
        );
        return _buildContent(context, metrics);
      },
    );
  }

  Widget _buildContent(BuildContext context, FormationMarkerMetrics metrics) {
    final field = lineup.entriesFor(MatchCompositionZone.field);
    final bench = lineup.entriesFor(MatchCompositionZone.bench);
    final formation = formationForCode(lineup.formationCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) ...[header!, const SizedBox(height: 14)],
        if (editable && onFormationChanged != null) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('squad-formation-${lineup.formationCode}'),
            initialValue: formation.code,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Dispositif',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final item in footballFormations)
                DropdownMenuItem(value: item.code, child: Text(item.code)),
            ],
            onChanged: formationBusy
                ? null
                : (value) {
                    if (value != null) onFormationChanged!(value);
                  },
          ),
          const SizedBox(height: 14),
        ],
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: metrics.width + _benchMargin,
                child: DragTarget<MatchCompositionEntry>(
                  onWillAcceptWithDetails: (details) => editable,
                  onAcceptWithDetails: (details) => onMoveToBench(details.data),
                  builder: (context, candidates, rejected) => Card(
                    margin: EdgeInsets.zero,
                    color: candidates.isNotEmpty
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text(
                            '$benchLabel\n(${bench.length})',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          for (final entry in bench)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: LiveBenchTile(
                                entry: entry,
                                draggable: editable,
                                metrics: metrics,
                                namesOnly: namesOnly,
                                timesBenched:
                                    timesBenched[entry.participantId] ?? 0,
                                onTap: editable && onRemoveFromSquad != null
                                    ? () => _confirmRemoval(context, entry)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: _benchGap),
              Expanded(
                child: FormationPitchEditor(
                  slots: formation.slots,
                  entries: field,
                  editable: editable,
                  markerMetrics: metrics,
                  namesOnly: namesOnly,
                  onDroppedOnSlot: onDroppedOnSlot,
                  onRemoveFromField: onMoveToBench,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRemoval(
    BuildContext context,
    MatchCompositionEntry entry,
  ) async {
    final remove = onRemoveFromSquad;
    if (remove == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Retirer ${entry.displayName} ?'),
        content: const Text(
          'Ce joueur ne fera plus partie du compte rendu. Un but ou une passe '
          'qui lui était attribué redevient « non attribué » : le but reste '
          'compté au score.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed == true) remove(entry);
  }
}
