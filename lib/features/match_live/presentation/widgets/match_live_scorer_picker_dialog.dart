import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter/material.dart';

/// Liste de joueurs à choisir : buteur, ou remplaçant qui entre.
/// Retourne le participantId choisi, ou `null` si annulé.
Future<String?> pickMatchLiveScorer(
  BuildContext context, {
  required List<MatchCompositionEntry> candidates,
  String title = 'Qui a marqué ?',
  IconData icon = Icons.sports_soccer,
}) {
  final sorted = [...candidates]
    ..sort((a, b) => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ));
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final entry = sorted[index];
                    return ListTile(
                      leading: Icon(icon),
                      title: Text(entry.displayName),
                      onTap: () =>
                          Navigator.of(context).pop(entry.participantId),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
