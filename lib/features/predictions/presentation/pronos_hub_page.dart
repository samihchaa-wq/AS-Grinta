import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:as_grinta/features/predictions/presentation/season_ranking_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'pronos_hub_matches_section.dart';
part 'pronos_hub_history_section.dart';
part 'pronos_hub_ranking_sections.dart';
part 'pronos_hub_upcoming_section.dart';
part 'pronos_hub_components.dart';

enum _PronosSection { upcoming, history, ranking }

enum _RankingView { matches, season, general }

class PronosHubPage extends ConsumerStatefulWidget {
  const PronosHubPage({super.key});

  @override
  ConsumerState<PronosHubPage> createState() => _PronosHubPageState();
}

class _PronosHubPageState extends ConsumerState<PronosHubPage> {
  _PronosSection _section = _PronosSection.upcoming;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pronos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_PronosSection>(
                segments: const [
                  ButtonSegment(
                    value: _PronosSection.upcoming,
                    label: Text('Prochain prono'),
                  ),
                  ButtonSegment(
                    value: _PronosSection.history,
                    label: Text('Historique'),
                  ),
                  ButtonSegment(
                    value: _PronosSection.ranking,
                    label: Text('Classement'),
                  ),
                ],
                selected: {_section},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _section = selection.first);
                },
              ),
            ),
          ),
          Expanded(
            child: switch (_section) {
              _PronosSection.upcoming => const _UpcomingMatchView(),
              _PronosSection.history => const _HistorySection(),
              _PronosSection.ranking => const _RankingsSection(),
            },
          ),
        ],
      ),
    );
  }
}
