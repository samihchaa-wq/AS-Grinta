import 'dart:async';

import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:flutter/material.dart';

/// Affiche le chrono du Tableau Blanc. Le décompte défile localement (Timer
/// d'1s) à partir de [MatchLiveSession.elapsedAt] : aucune donnée n'est
/// poussée seconde par seconde, seules les transitions d'état sont
/// synchronisées via Supabase Realtime.
class MatchLiveClock extends StatefulWidget {
  const MatchLiveClock({
    super.key,
    required this.session,
    this.compact = false,
  });

  final MatchLiveSession session;
  final bool compact;

  @override
  State<MatchLiveClock> createState() => _MatchLiveClockState();
}

class _MatchLiveClockState extends State<MatchLiveClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  @override
  void didUpdateWidget(covariant MatchLiveClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleTick();
  }

  void _scheduleTick() {
    _timer?.cancel();
    if (widget.session.state == MatchLiveState.running) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(Duration elapsed) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.session.elapsedAt(DateTime.now());
    final label = switch (widget.session.state) {
      MatchLiveState.notStarted => 'Pas commencé',
      MatchLiveState.running =>
        widget.session.half == 1 ? '1ʳᵉ mi-temps' : '2ᵉ mi-temps',
      MatchLiveState.paused => 'En pause',
      MatchLiveState.halftime => 'Mi-temps',
      MatchLiveState.finished => 'Terminé',
    };
    final timeStyle = TextStyle(
      fontSize: widget.compact ? 27 : 44,
      fontWeight: FontWeight.w900,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final labelStyle = (widget.compact
            ? Theme.of(context).textTheme.labelMedium
            : Theme.of(context).textTheme.labelLarge)
        ?.copyWith(fontWeight: FontWeight.w700);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          widget.compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(_format(elapsed), style: timeStyle),
        const SizedBox(height: 2),
        Text(label, style: labelStyle),
      ],
    );
  }
}
