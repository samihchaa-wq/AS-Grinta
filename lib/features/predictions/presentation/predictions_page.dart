import 'package:as_grinta/shared/widgets/feature_placeholder.dart';
import 'package:flutter/material.dart';

class PredictionsPage extends StatelessWidget {
  const PredictionsPage({super.key});

  @override
  Widget build(BuildContext context) => const FeaturePlaceholder(
        title: 'Pronostics',
        icon: Icons.tips_and_updates,
      );
}
