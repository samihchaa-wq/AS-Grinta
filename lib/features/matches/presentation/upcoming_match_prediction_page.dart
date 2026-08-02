import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/inline_match_prediction_card.dart';
import 'package:flutter/material.dart';

class UpcomingMatchPredictionPage extends StatelessWidget {
  const UpcomingMatchPredictionPage({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Ton prono')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sectionGap,
          AppSpacing.screenGutter,
          40,
        ),
        children: [InlineMatchPredictionCard(matchId: matchId)],
      ),
    );
  }
}
