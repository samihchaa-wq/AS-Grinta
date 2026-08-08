import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/core/widgets/drag_auto_scroll.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_tab.dart';
import 'package:as_grinta/features/matches/data/match_info_repository.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_info_tab.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/inline_match_prediction_card.dart';
import 'package:as_grinta/features/sports_management/data/guest_players_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_availability_board_repository.dart';
import 'package:as_grinta/features/sports_management/data/match_composition_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_match_finalization_repository.dart';
import 'package:as_grinta/features/sports_management/data/sport_waitlist_repository.dart';
import 'package:as_grinta/features/sports_management/domain/availability_reminder_models.dart';
import 'package:as_grinta/features/sports_management/domain/composition_simulation.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';
import 'package:as_grinta/features/sports_management/domain/sport_waitlist_models.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/composition_pitch.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/internal_team_composition_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'admin_squad_plan_page_state.dart';
part 'admin_squad_plan_page_effectif.dart';
part 'admin_squad_plan_page_composition.dart';
part 'admin_squad_plan_page_widgets.dart';

enum _AdminStep { info, effectif, composition, live, prediction }

class AdminSquadPlanPage extends ConsumerStatefulWidget {
  const AdminSquadPlanPage({
    super.key,
    this.initialMatchId,
    this.initialStep,
    this.showPredictionStep = false,
  });

  final String? initialMatchId;
  final String? initialStep;
  final bool showPredictionStep;

  @override
  ConsumerState<AdminSquadPlanPage> createState() => _AdminSquadPlanPageState();
}
