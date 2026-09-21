import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/utils/name_validation.dart';
import 'package:as_grinta/core/utils/ranking.dart';
import 'package:as_grinta/core/widgets/admin_badge.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_empty_state.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/core/widgets/match_date_column.dart';
import 'package:as_grinta/core/widgets/match_fixture.dart';
import 'package:as_grinta/core/widgets/sticky_header_table.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/badges/presentation/badge_display_scope.dart';
import 'package:as_grinta/features/badges/presentation/name_with_badges.dart';
import 'package:as_grinta/features/matches/data/match_details_repository.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/calendar_matches_view.dart';
import 'package:as_grinta/features/matches/presentation/match_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/predictions/data/predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/predictions_controller.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/inline_match_prediction_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'pronos_hub_history_section.dart';
part 'pronos_hub_ranking_sections.dart';
part 'pronos_hub_components.dart';

enum _PronosCategory { matches, general }

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
      'general' => _PronosCategory.general,
      _ => _PronosCategory.matches,
    };
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final content = switch (_category) {
      _PronosCategory.matches => const CalendarMatchesView(),
      _PronosCategory.general => const _GeneralRankingsSection(),
    };

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GrintaAppBar(
        title: Text(switch (_category) {
          _PronosCategory.matches => 'Calendrier',
          _PronosCategory.general => 'Classements',
        }),
        actions: grintaHomeActions(context),
      ),
      body: Material(
        type: MaterialType.transparency,
        child: AnimatedSwitcher(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
          reverseDuration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final offset = Tween<Offset>(
              begin: const Offset(.025, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(_category),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Panneau de classement réutilisable dans l'onglet Stats.
class RankingsPanel extends StatelessWidget {
  const RankingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const _GeneralRankingsSection(badgeSize: statisticsBadgeSize);
  }
}
