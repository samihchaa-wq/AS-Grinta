import 'dart:math' as math;

import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/predictions/data/season_predictions_repository.dart';
import 'package:as_grinta/features/predictions/presentation/season_predictions_page.dart'
    as legacy;
import 'package:as_grinta/features/predictions/presentation/widgets/premium_season_gauges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final premiumSeasonLockedProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).isLocked();
});

final premiumSeasonGaugesProvider =
    FutureProvider.autoDispose<List<PlayerGauge>>((ref) {
  return ref.watch(seasonPredictionsRepositoryProvider).fetchGauges();
});

enum _PremiumView { players, predictors }

class PremiumSeasonPredictionsPage extends ConsumerStatefulWidget {
  const PremiumSeasonPredictionsPage({super.key});

  @override
  ConsumerState<PremiumSeasonPredictionsPage> createState() =>
      _PremiumSeasonPredictionsPageState();
}

class _PremiumSeasonPredictionsPageState
    extends ConsumerState<PremiumSeasonPredictionsPage> {
  _PremiumView _view = _PremiumView.players;
  String? _selectedPredictorId;

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(premiumSeasonLockedProvider);
    return locked.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Pronos de saison')),
        body: Center(child: Text(humanizeError(error))),
      ),
      data: (isLocked) {
        if (!isLocked) return const legacy.SeasonPredictionsPage();
        return _buildPremiumPage();
      },
    );
  }

  Widget _buildPremiumPage() {
    final gaugesAsync = ref.watch(premiumSeasonGaugesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pronos de saison ✨'),
        centerTitle: false,
      ),
      body: gaugesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [Text(humanizeError(error))],
          ),
        ),
        data: (gauges) {
          if (gauges.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: const [Text('Aucun joueur dans l’effectif.')],
              ),
            );
          }

          final currentUserId =
              ref.read(seasonPredictionsRepositoryProvider).currentUserId;
          final predictors = _predictors(gauges);
          _selectedPredictorId ??= currentUserId != null &&
                  predictors.any((item) => item.id == currentUserId)
              ? currentUserId
              : predictors.firstOrNull?.id;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                Text(
                  '${predictors.length} pronostiqueurs',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white60,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 18),
                _PremiumSwitcher(
                  selected: _view,
                  onChanged: (value) => setState(() => _view = value),
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _view == _PremiumView.players
                      ? _playersView(gauges, currentUserId)
                      : _predictorView(
                          gauges,
                          predictors,
                          currentUserId,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _playersView(List<PlayerGauge> gauges, String? currentUserId) {
    final scorers = gauges.where((gauge) => !gauge.isGoalkeeper).toList();
    final keepers = gauges.where((gauge) => gauge.isGoalkeeper).toList();
    final scorerScale = _scale(scorers, 20);
    final keeperScale = _scale(keepers, 15);

    return Column(
      key: const ValueKey('premium-players'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scorers.isNotEmpty) ...[
          _SectionHeader(
            asset: 'assets/images/scorer_logo.png',
            title: 'Buteurs',
            subtitle: 'Échelle commune · 0 à $scorerScale buts',
          ),
          const SizedBox(height: 10),
          ...scorers.map(
            (gauge) => PremiumSeasonGaugeCard(
              gauge: gauge,
              scaleMax: scorerScale,
              onOpenAll: () => _openAll(gauge, currentUserId),
              onOpenPopular: (marker) => _openPopular(gauge, marker),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (keepers.isNotEmpty) ...[
          _SectionHeader(
            asset: 'assets/images/keeper_logo.png',
            title: 'Gardiens',
            subtitle: 'Clean sheets · 0 à $keeperScale',
          ),
          const SizedBox(height: 10),
          ...keepers.map(
            (gauge) => PremiumSeasonGaugeCard(
              gauge: gauge,
              scaleMax: keeperScale,
              onOpenAll: () => _openAll(gauge, currentUserId),
              onOpenPopular: (marker) => _openPopular(gauge, marker),
            ),
          ),
        ],
        const SizedBox(height: 8),
        const _MinimalLegend(),
      ],
    );
  }

  Widget _predictorView(
    List<PlayerGauge> gauges,
    List<({String id, String name})> predictors,
    String? currentUserId,
  ) {
    final selectedId = _selectedPredictorId;
    final selected = predictors.where((item) => item.id == selectedId).toList();
    final selectedName = selected.isEmpty ? 'Pronostiqueur' : selected.first.name;
    final scorers = gauges.where((gauge) => !gauge.isGoalkeeper).toList();
    final keepers = gauges.where((gauge) => gauge.isGoalkeeper).toList();

    return Column(
      key: const ValueKey('premium-predictors'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selectedId,
          decoration: InputDecoration(
            labelText: 'Consulter les pronostics de',
            prefixIcon: const Icon(Icons.person_search_outlined),
            filled: true,
            fillColor: const Color(0xFF0A1931),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
          ),
          items: [
            for (final predictor in predictors)
              DropdownMenuItem(
                value: predictor.id,
                child: Text(
                  predictor.id == currentUserId
                      ? '${predictor.name} (moi)'
                      : predictor.name,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _selectedPredictorId = value);
          },
        ),
        const SizedBox(height: 20),
        Text(
          selectedName,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        Text(
          'Sa fiche complète de pronostics',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white54,
              ),
        ),
        const SizedBox(height: 18),
        if (scorers.isNotEmpty) ...[
          const _SmallTitle('Buteurs'),
          _PredictorList(
            gauges: scorers,
            predictorId: selectedId,
            scaleMax: _scale(scorers, 20),
          ),
          const SizedBox(height: 20),
        ],
        if (keepers.isNotEmpty) ...[
          const _SmallTitle('Gardiens · clean sheets'),
          _PredictorList(
            gauges: keepers,
            predictorId: selectedId,
            scaleMax: _scale(keepers, 15),
          ),
        ],
      ],
    );
  }

  Future<void> _openAll(PlayerGauge gauge, String? currentUserId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .9,
        minChildSize: .62,
        maxChildSize: .98,
        builder: (context, controller) => PremiumPlayerDetailsSheet(
          gauge: gauge,
          currentUserId: currentUserId,
          scrollController: controller,
        ),
      ),
    );
  }

  Future<void> _openPopular(PlayerGauge gauge, GaugeMarker marker) async {
    final accent = gaugeAccentFor(gauge.playerId);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF07152B),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gauge.playerName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              '${marker.value} ${gauge.isGoalkeeper ? 'clean sheets' : 'buts'}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final prediction in marker.predictions)
                  Chip(
                    avatar: CircleAvatar(
                      backgroundColor: accent.withValues(alpha: .2),
                      child: Text(_initial(prediction.predictorName)),
                    ),
                    label: Text(prediction.predictorName),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(premiumSeasonLockedProvider);
    ref.invalidate(premiumSeasonGaugesProvider);
    await ref.read(premiumSeasonGaugesProvider.future);
  }

  int _scale(List<PlayerGauge> gauges, int fallback) {
    var observed = fallback;
    for (final gauge in gauges) {
      observed = math.max(observed, gauge.maxValue);
    }
    return ((observed + 4) ~/ 5) * 5;
  }

  List<({String id, String name})> _predictors(List<PlayerGauge> gauges) {
    final byId = <String, String>{};
    for (final gauge in gauges) {
      for (final prediction in gauge.predictions) {
        byId[prediction.predictorId] = prediction.predictorName;
      }
    }
    final result = byId.entries
        .map((entry) => (id: entry.key, name: entry.value))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }
}

class _PremiumSwitcher extends StatelessWidget {
  const _PremiumSwitcher({required this.selected, required this.onChanged});

  final _PremiumView selected;
  final ValueChanged<_PremiumView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF07152A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF315385)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SwitchItem(
              active: selected == _PremiumView.players,
              icon: Icons.sports_soccer,
              label: 'Par joueur',
              onTap: () => onChanged(_PremiumView.players),
            ),
          ),
          Expanded(
            child: _SwitchItem(
              active: selected == _PremiumView.predictors,
              icon: Icons.group_outlined,
              label: 'Par pronostiqueur',
              onTap: () => onChanged(_PremiumView.predictors),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchItem extends StatelessWidget {
  const _SwitchItem({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(21),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF2E6DF6), Color(0xFF6A32C7)],
                )
              : null,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFF6A32C7).withValues(alpha: .3),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 21),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                  color: active ? Colors.white : Colors.white60,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.asset,
    required this.title,
    required this.subtitle,
  });

  final String asset;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(asset, width: 46, height: 46, fit: BoxFit.contain),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Text(subtitle, style: const TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MinimalLegend extends StatelessWidget {
  const _MinimalLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF07152A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Legend(icon: Icons.sports_soccer, label: 'Score actuel'),
          _Legend(icon: Icons.circle_outlined, label: 'Score le plus pronostiqué'),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 7),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class _SmallTitle extends StatelessWidget {
  const _SmallTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _PredictorList extends StatelessWidget {
  const _PredictorList({
    required this.gauges,
    required this.predictorId,
    required this.scaleMax,
  });

  final List<PlayerGauge> gauges;
  final String? predictorId;
  final int scaleMax;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF08162C),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < gauges.length; index++) ...[
            _PredictorRow(
              gauge: gauges[index],
              prediction: gauges[index].predictionFor(predictorId),
              scaleMax: scaleMax,
            ),
            if (index != gauges.length - 1)
              Divider(height: 1, color: Colors.white.withValues(alpha: .05)),
          ],
        ],
      ),
    );
  }
}

class _PredictorRow extends StatelessWidget {
  const _PredictorRow({
    required this.gauge,
    required this.prediction,
    required this.scaleMax,
  });

  final PlayerGauge gauge;
  final GaugePrediction? prediction;
  final int scaleMax;

  @override
  Widget build(BuildContext context) {
    final accent = gaugeAccentFor(gauge.playerId);
    final progress = ((prediction?.value ?? 0) / math.max(1, scaleMax))
        .clamp(0.0, 1.0)
        .toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              gauge.playerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                color: accent,
                backgroundColor: Colors.white.withValues(alpha: .06),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            prediction?.value.toString() ?? '—',
            style: TextStyle(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

String _initial(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
