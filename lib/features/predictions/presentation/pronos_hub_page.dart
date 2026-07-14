import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/colorful_season_predictions_page.dart';
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

enum _PronosCategory { matches, scorers, general }

enum _MatchSection { upcoming, history, ranking }

class PronosHubPage extends ConsumerStatefulWidget {
  const PronosHubPage({super.key});

  @override
  ConsumerState<PronosHubPage> createState() => _PronosHubPageState();
}

class _PronosHubPageState extends ConsumerState<PronosHubPage> {
  _PronosCategory _category = _PronosCategory.matches;
  _MatchSection _matchSection = _MatchSection.upcoming;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(title: 'Pronos'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_PronosCategory>(
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size.fromHeight(54)),
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                expandedInsets: EdgeInsets.zero,
                segments: const [
                  ButtonSegment(
                    value: _PronosCategory.matches,
                    label: Text('Matchs'),
                  ),
                  ButtonSegment(
                    value: _PronosCategory.scorers,
                    label: Text('Buteur'),
                  ),
                  ButtonSegment(
                    value: _PronosCategory.general,
                    label: Text('Général'),
                  ),
                ],
                selected: {_category},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _category = selection.first);
                },
              ),
            ),
          ),
          if (_category == _PronosCategory.matches)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_MatchSection>(
                  expandedInsets: EdgeInsets.zero,
                  segments: const [
                    ButtonSegment(
                      value: _MatchSection.upcoming,
                      label: Text('Prochain prono'),
                    ),
                    ButtonSegment(
                      value: _MatchSection.history,
                      label: Text('Historique'),
                    ),
                    ButtonSegment(
                      value: _MatchSection.ranking,
                      label: Text('Classement'),
                    ),
                  ],
                  selected: {_matchSection},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    setState(() => _matchSection = selection.first);
                  },
                ),
              ),
            ),
          Expanded(
            child: switch (_category) {
              _PronosCategory.matches => switch (_matchSection) {
                  _MatchSection.upcoming => const _UpcomingMatchView(),
                  _MatchSection.history => const _HistorySection(),
                  _MatchSection.ranking => const _MatchRankingView(),
                },
              _PronosCategory.scorers =>
                const ColorfulSeasonPredictionsPage(embedded: true),
              _PronosCategory.general => const _GeneralSection(),
            },
          ),
        ],
      ),
    );
  }
}
