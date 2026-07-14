import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
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

part 'pronos_hub_history_section.dart';
part 'pronos_hub_ranking_sections.dart';
part 'pronos_hub_upcoming_section.dart';
part 'pronos_hub_components.dart';

enum _PronosCategory { matches, scorers, general }

enum _GeneralRankingView { general, matches, scorers }

class PronosHubPage extends ConsumerStatefulWidget {
  const PronosHubPage({super.key, this.initialCategory});

  final String? initialCategory;

  @override
  ConsumerState<PronosHubPage> createState() => _PronosHubPageState();
}

class _PronosHubPageState extends ConsumerState<PronosHubPage> {
  late _PronosCategory _category;

  @override
  void initState() {
    super.initState();
    _category = _categoryFrom(widget.initialCategory);
  }

  @override
  void didUpdateWidget(covariant PronosHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory) {
      _category = _categoryFrom(widget.initialCategory);
    }
  }

  _PronosCategory _categoryFrom(String? value) {
    return switch (value) {
      'scorers' => _PronosCategory.scorers,
      'general' => _PronosCategory.general,
      _ => _PronosCategory.matches,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(title: const SizedBox.shrink()),
      body: switch (_category) {
        _PronosCategory.matches => const _CalendarSection(),
        _PronosCategory.scorers => const ColorfulSeasonPredictionsPage(
            embedded: true,
            showRanking: false,
          ),
        _PronosCategory.general => const _GeneralRankingsSection(),
      },
    );
  }
}
