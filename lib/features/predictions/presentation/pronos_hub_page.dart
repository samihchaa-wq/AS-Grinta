import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/features/home/data/home_repository.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/predictions/data/leaderboard_repository.dart';
import 'package:as_grinta/features/predictions/presentation/colorful_season_predictions_page.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'pronos_hub_matches_section.dart';
part 'pronos_hub_ranking_sections.dart';
part 'pronos_hub_upcoming_section.dart';
part 'pronos_hub_components.dart';

enum _PronosSection { matches, season, general }

enum _MatchView { upcoming, ranking }

class PronosHubPage extends ConsumerStatefulWidget {
  const PronosHubPage({super.key});

  @override
  ConsumerState<PronosHubPage> createState() => _PronosHubPageState();
}

class _PronosHubPageState extends ConsumerState<PronosHubPage> {
  _PronosSection _section = _PronosSection.matches;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pronos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<_PronosSection>(
              segments: const [
                ButtonSegment(
                  value: _PronosSection.matches,
                  icon: Icon(Icons.sports_soccer_outlined),
                  label: Text('Matchs'),
                ),
                ButtonSegment(
                  value: _PronosSection.season,
                  icon: Icon(Icons.calendar_month_outlined),
                  label: Text('Buteur'),
                ),
                ButtonSegment(
                  value: _PronosSection.general,
                  icon: Icon(Icons.emoji_events_outlined),
                  label: Text('Général'),
                ),
              ],
              selected: {_section},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _section = selection.first);
              },
            ),
          ),
          Expanded(
            child: switch (_section) {
              _PronosSection.matches => const _MatchesSection(),
              _PronosSection.season =>
                const ColorfulSeasonPredictionsPage(embedded: true),
              _PronosSection.general => const _GeneralSection(),
            },
          ),
        ],
      ),
    );
  }
}
