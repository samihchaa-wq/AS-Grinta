import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/coach/domain/coach_board.dart';
import 'package:as_grinta/features/coach/presentation/coach_board_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Formation provider local ─────────────────────────────────────────────────

class _FormationOption {
  const _FormationOption({
    required this.code,
    required this.label,
    required this.slots,
  });
  final String code;
  final String label;
  final List<String> slots;
}

final _formationsProvider =
    FutureProvider<List<_FormationOption>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  try {
    final result = await client
        .from('formations')
        .select('code, label, slots')
        .order('code');

    final options = <_FormationOption>[];
    for (final row in result as List) {
      final map = Map<String, dynamic>.from(row);
      final code = map['code'].toString();
      final label = map['label'].toString();
      final rawSlots = map['slots'];
      List<String> slots = const [];
      if (rawSlots is List) {
        slots = rawSlots
            .map((s) => Map<String, dynamic>.from(s as Map))
            .map((s) => s['code']?.toString())
            .whereType<String>()
            .where((c) => c.isNotEmpty)
            .toList();
      }
      if (slots.isEmpty) slots = hardcodedFormationSlots(code);
      options.add(_FormationOption(code: code, label: label, slots: slots));
    }
    if (options.isEmpty) throw StateError('no formations in Supabase');
    return options;
  } catch (_) {
    return ['4-4-2', '4-3-3', '3-5-2', '4-2-3-1', '5-3-2']
        .map((c) => _FormationOption(
              code: c,
              label: c,
              slots: hardcodedFormationSlots(c),
            ))
        .toList();
  }
});

// ─── Page principale ──────────────────────────────────────────────────────────

class CoachBoardPage extends ConsumerStatefulWidget {
  const CoachBoardPage({super.key});

  @override
  ConsumerState<CoachBoardPage> createState() => _CoachBoardPageState();
}

class _CoachBoardPageState extends ConsumerState<CoachBoardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  static String _formatTimer(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showFormationPicker(
    BuildContext ctx,
    CoachBoardState state,
    CoachBoardController ctrl,
    List<_FormationOption> formations,
  ) {
    showModalBottomSheet<void>(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _FormationSheet(
        formations: formations,
        currentCode: state.formationCode,
        onSelected: (opt) {
          ctrl.setFormation(opt.code, opt.slots);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _confirmReset(
      BuildContext ctx, CoachBoardController ctrl) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Réinitialiser le tableau ?'),
        content: const Text(
          'Le chronomètre, les événements et les positions seront remis à zéro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
    if (ok == true) ctrl.resetBoard();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coachBoardControllerProvider);
    final ctrl = ref.read(coachBoardControllerProvider.notifier);
    final formationsAsync = ref.watch(_formationsProvider);

    if (state.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tableau blanc')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tableau blanc')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text(state.error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: ctrl.resetBoard,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _formatTimer(state.elapsedSeconds),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.grass_rounded), text: 'Terrain'),
            Tab(icon: Icon(Icons.list_alt_rounded), text: 'Événements'),
          ],
        ),
        actions: [
          // Timer controls
          state.isRunning
              ? IconButton(
                  icon: const Icon(Icons.pause_circle_filled),
                  tooltip: 'Pause',
                  onPressed: ctrl.pauseTimer,
                )
              : IconButton(
                  icon: const Icon(Icons.play_circle_filled),
                  tooltip: 'Démarrer',
                  onPressed: ctrl.startTimer,
                ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: 'Remettre à zéro',
            onPressed: state.isRunning ? null : ctrl.resetTimer,
          ),
          // Formation
          formationsAsync.when(
            data: (formations) => TextButton.icon(
              onPressed: () =>
                  _showFormationPicker(context, state, ctrl, formations),
              icon: const Icon(Icons.layers_outlined, size: 16),
              label: Text(state.formationCode,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
            loading: () => const SizedBox(width: 8),
            error: (_, __) => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Réinitialiser le tableau',
            onPressed: () => _confirmReset(context, ctrl),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _TerrainTab(state: state, ctrl: ctrl),
          _EventsTab(state: state, ctrl: ctrl),
        ],
      ),
    );
  }
}

// ─── Onglet Terrain ───────────────────────────────────────────────────────────

class _TerrainTab extends StatelessWidget {
  const _TerrainTab({required this.state, required this.ctrl});
  final CoachBoardState state;
  final CoachBoardController ctrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ScoreBar(state: state, ctrl: ctrl),
        Expanded(child: _PitchView(state: state, ctrl: ctrl)),
        _BenchBar(state: state, ctrl: ctrl),
      ],
    );
  }
}

// ─── Barre de score ───────────────────────────────────────────────────────────

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.state, required this.ctrl});
  final CoachBoardState state;
  final CoachBoardController ctrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Score Grinta
          Row(
            children: [
              Text(
                'AS Grinta',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: cs.primary, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              _ScoreButton(
                score: state.scoreUs,
                onDecrement: state.scoreUs > 0
                    ? () => ctrl.removeEvent(state.events
                        .lastWhere((e) => e.type == CoachEventType.goalUs,
                            orElse: () => state.events.first)
                        .id)
                    : null,
                color: cs.primary,
              ),
            ],
          ),
          Text('-',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          // Score adversaire
          Row(
            children: [
              _ScoreButton(
                score: state.scoreThem,
                onDecrement: state.scoreThem > 0
                    ? () => ctrl.removeEvent(state.events
                        .lastWhere((e) => e.type == CoachEventType.goalThem,
                            orElse: () => state.events.first)
                        .id)
                    : null,
                color: cs.error,
              ),
              const SizedBox(width: 8),
              Text(
                'Adversaire',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: cs.error, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreButton extends StatelessWidget {
  const _ScoreButton({
    required this.score,
    required this.onDecrement,
    required this.color,
  });
  final int score;
  final VoidCallback? onDecrement;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onDecrement,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Center(
          child: Text(
            '$score',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Vue terrain ─────────────────────────────────────────────────────────────

class _PitchView extends StatelessWidget {
  const _PitchView({required this.state, required this.ctrl});
  final CoachBoardState state;
  final CoachBoardController ctrl;

  @override
  Widget build(BuildContext context) {
    final positions = computeFormationPositions(
      state.formationCode,
      state.formationSlots,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        const tokenR = 26.0; // half token size

        return Stack(
          children: [
            // Terrain (fond + lignes)
            Positioned.fill(child: CustomPaint(painter: _PitchPainter())),

            // Cibles de drop (slots)
            ...positions.entries.map((entry) {
              final pos = entry.value;
              final isOccupied = state.lineup.containsKey(entry.key);
              return Positioned(
                left: pos.dx * w - tokenR,
                top: pos.dy * h - tokenR,
                child: DragTarget<String>(
                  onAcceptWithDetails: (details) {
                    ctrl.movePlayer(details.data, entry.key);
                  },
                  builder: (_, candidates, rejected) {
                    final hover = candidates.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: tokenR * 2,
                      height: tokenR * 2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hover
                            ? Colors.white.withOpacity(0.35)
                            : isOccupied
                                ? Colors.transparent
                                : Colors.white.withOpacity(0.08),
                        border: Border.all(
                          color: hover
                              ? Colors.white
                              : isOccupied
                                  ? Colors.transparent
                                  : Colors.white.withOpacity(0.25),
                          width: hover ? 2 : 1,
                          strokeAlign: BorderSide.strokeAlignCenter,
                        ),
                      ),
                      child: isOccupied
                          ? const SizedBox.shrink()
                          : Center(
                              child: Text(
                                entry.key.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                    );
                  },
                ),
              );
            }),

            // Jetons joueurs
            ...state.lineup.entries.map((entry) {
              final slotKey = entry.key;
              final playerId = entry.value;
              final player = state.playerById(playerId);
              if (player == null) return const SizedBox.shrink();
              final pos = positions[slotKey];
              if (pos == null) return const SizedBox.shrink();
              return Positioned(
                left: pos.dx * w - tokenR,
                top: pos.dy * h - tokenR,
                child: Draggable<String>(
                  data: playerId,
                  feedback: _PlayerToken(player: player, floating: true),
                  childWhenDragging: Opacity(
                    opacity: 0.3,
                    child: _PlayerToken(player: player),
                  ),
                  child: _PlayerToken(player: player),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ─── Jeton joueur ─────────────────────────────────────────────────────────────

class _PlayerToken extends StatelessWidget {
  const _PlayerToken({required this.player, this.floating = false});
  final CoachPlayer player;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    const size = 52.0;
    final bgColor = player.isGoalkeeper
        ? const Color(0xFFFF6F00)
        : const Color(0xFF1B5E20);
    final borderColor = player.isGoalkeeper
        ? const Color(0xFFFFCA28)
        : const Color(0xFF4CAF50);

    return SizedBox(
      width: size,
      height: size + 14,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 2),
              boxShadow: floating
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      )
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
            ),
            child: Center(
              child: Text(
                player.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 52),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.72),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              player.firstName,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Banc ─────────────────────────────────────────────────────────────────────

class _BenchBar extends StatelessWidget {
  const _BenchBar({required this.state, required this.ctrl});
  final CoachBoardState state;
  final CoachBoardController ctrl;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onAcceptWithDetails: (details) => ctrl.sendToBench(details.data),
      builder: (_, candidates, __) {
        final hover = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 90,
          decoration: BoxDecoration(
            color: hover
                ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5)
                : Theme.of(context).colorScheme.surfaceContainerHigh,
            border: Border(
              top: BorderSide(
                color: hover
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4, bottom: 2),
                child: Text(
                  'Banc (${state.bench.length})',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              Expanded(
                child: state.bench.isEmpty
                    ? Center(
                        child: Text(
                          'Déposez un joueur ici pour le mettre sur le banc',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: state.bench.length,
                        itemBuilder: (ctx, i) {
                          final player = state.playerById(state.bench[i]);
                          if (player == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Draggable<String>(
                              data: player.id,
                              feedback:
                                  _PlayerToken(player: player, floating: true),
                              childWhenDragging: Opacity(
                                opacity: 0.3,
                                child: _PlayerToken(player: player),
                              ),
                              child: _PlayerToken(player: player),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Painter terrain ──────────────────────────────────────────────────────────

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Fond vert
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1B5E20),
    );

    // Bandes alternées (optionnel - plus réaliste)
    final stripePaint = Paint()..color = const Color(0xFF1A5C1E);
    const stripeCount = 8;
    final stripeH = h / stripeCount;
    for (var i = 0; i < stripeCount; i++) {
      if (i.isEven) {
        canvas.drawRect(
          Rect.fromLTWH(0, i * stripeH, w, stripeH),
          stripePaint,
        );
      }
    }

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..style = PaintingStyle.fill;

    final mx = w * 0.04; // marge horizontale
    final my = h * 0.025; // marge verticale
    final fw = w - mx * 2;
    final fh = h - my * 2;

    // Bordure extérieure
    canvas.drawRect(
      Rect.fromLTWH(mx, my, fw, fh),
      linePaint,
    );

    // Ligne médiane
    canvas.drawLine(
      Offset(mx, my + fh / 2),
      Offset(mx + fw, my + fh / 2),
      linePaint,
    );

    // Cercle central
    canvas.drawCircle(
      Offset(mx + fw / 2, my + fh / 2),
      fw * 0.14,
      linePaint,
    );

    // Point central
    canvas.drawCircle(
      Offset(mx + fw / 2, my + fh / 2),
      3,
      fillPaint,
    );

    // Surface de réparation (haut - adversaire)
    final penW = fw * 0.52;
    final penH = fh * 0.17;
    final penX = mx + (fw - penW) / 2;
    canvas.drawRect(
      Rect.fromLTWH(penX, my, penW, penH),
      linePaint,
    );

    // Surface de réparation (bas - notre équipe)
    canvas.drawRect(
      Rect.fromLTWH(penX, my + fh - penH, penW, penH),
      linePaint,
    );

    // Surface de but (haut)
    final goalAreaW = fw * 0.26;
    final goalAreaH = fh * 0.06;
    final goalAreaX = mx + (fw - goalAreaW) / 2;
    canvas.drawRect(
      Rect.fromLTWH(goalAreaX, my, goalAreaW, goalAreaH),
      linePaint,
    );

    // Surface de but (bas)
    canvas.drawRect(
      Rect.fromLTWH(goalAreaX, my + fh - goalAreaH, goalAreaW, goalAreaH),
      linePaint,
    );

    // But (haut)
    final goalNetW = fw * 0.14;
    final goalNetH = fh * 0.025;
    final goalNetX = mx + (fw - goalNetW) / 2;
    canvas.drawRect(
      Rect.fromLTWH(goalNetX, my - goalNetH, goalNetW, goalNetH),
      linePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(goalNetX, my + fh, goalNetW, goalNetH),
      linePaint,
    );

    // Point de penalty (haut)
    canvas.drawCircle(
      Offset(mx + fw / 2, my + fh * 0.12),
      3,
      fillPaint,
    );

    // Point de penalty (bas)
    canvas.drawCircle(
      Offset(mx + fw / 2, my + fh * 0.88),
      3,
      fillPaint,
    );

    // Arcs de coin
    final cornerRadius = fw * 0.04;
    for (final corner in [
      Offset(mx, my),
      Offset(mx + fw, my),
      Offset(mx, my + fh),
      Offset(mx + fw, my + fh),
    ]) {
      final sweepSign = (corner.dx == mx ? 1.0 : -1.0);
      final sweepStart = (corner.dy == my ? 0.0 : -1.5707963267948966);
      canvas.drawArc(
        Rect.fromCenter(
          center: corner,
          width: cornerRadius * 2,
          height: cornerRadius * 2,
        ),
        sweepStart,
        sweepSign * 1.5707963267948966,
        false,
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PitchPainter _) => false;
}

// ─── Onglet Événements ────────────────────────────────────────────────────────

class _EventsTab extends StatelessWidget {
  const _EventsTab({required this.state, required this.ctrl});
  final CoachBoardState state;
  final CoachBoardController ctrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Actions
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _ActionChip(
                icon: Icons.sports_soccer,
                label: 'But Grinta',
                color: const Color(0xFF1DB95F),
                onTap: () => _showGoalUsDialog(context),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: Icons.sports_soccer,
                label: 'But Adv.',
                color: Colors.red,
                onTap: () => ctrl.addGoalThem(),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: Icons.swap_horiz,
                label: 'Remplacement',
                color: Colors.blue,
                onTap: () => _showSubstitutionDialog(context),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: Icons.square_rounded,
                label: 'Carton',
                color: const Color(0xFFFFD600),
                onTap: () => _showCardDialog(context),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: Icons.sticky_note_2_outlined,
                label: 'Note',
                color: Colors.grey,
                onTap: () => _showNoteDialog(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Liste des événements
        Expanded(
          child: state.events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timeline,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Aucun événement enregistré',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: state.events.length,
                  itemBuilder: (_, i) {
                    final event =
                        state.events[state.events.length - 1 - i];
                    return _EventTile(
                      event: event,
                      state: state,
                      onDelete: () => ctrl.removeEvent(event.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showGoalUsDialog(BuildContext ctx) {
    final fieldPlayers = state.lineup.values
        .map(state.playerById)
        .whereType<CoachPlayer>()
        .toList();
    showDialog<void>(
      context: ctx,
      builder: (dCtx) {
        CoachPlayer? scorer;
        return StatefulBuilder(
          builder: (_, setState) => AlertDialog(
            title: const Text('But AS Grinta'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<CoachPlayer>(
                  decoration: const InputDecoration(labelText: 'Buteur (opt.)'),
                  value: scorer,
                  items: fieldPlayers
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.name),
                          ))
                      .toList(),
                  onChanged: (p) => setState(() => scorer = p),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dCtx).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () {
                  ctrl.addGoalUs(scorerId: scorer?.id);
                  Navigator.of(dCtx).pop();
                },
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSubstitutionDialog(BuildContext ctx) {
    if (state.bench.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Le banc est vide.')),
      );
      return;
    }
    final fieldPlayers = state.lineup.values
        .map(state.playerById)
        .whereType<CoachPlayer>()
        .toList();
    final benchPlayers =
        state.bench.map(state.playerById).whereType<CoachPlayer>().toList();

    showDialog<void>(
      context: ctx,
      builder: (dCtx) {
        CoachPlayer? playerIn;
        CoachPlayer? playerOut;
        return StatefulBuilder(
          builder: (_, setState) => AlertDialog(
            title: const Text('Remplacement'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<CoachPlayer>(
                  decoration:
                      const InputDecoration(labelText: 'Entrant (banc)'),
                  value: playerIn,
                  items: benchPlayers
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.name),
                          ))
                      .toList(),
                  onChanged: (p) => setState(() => playerIn = p),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<CoachPlayer>(
                  decoration:
                      const InputDecoration(labelText: 'Sortant (terrain)'),
                  value: playerOut,
                  items: fieldPlayers
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.name),
                          ))
                      .toList(),
                  onChanged: (p) => setState(() => playerOut = p),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dCtx).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: playerIn != null && playerOut != null
                    ? () {
                        ctrl.addSubstitution(
                          inPlayerId: playerIn!.id,
                          outPlayerId: playerOut!.id,
                        );
                        Navigator.of(dCtx).pop();
                      }
                    : null,
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCardDialog(BuildContext ctx) {
    final players = state.lineup.values
        .map(state.playerById)
        .whereType<CoachPlayer>()
        .toList();
    showDialog<void>(
      context: ctx,
      builder: (dCtx) {
        CoachPlayer? target;
        bool isRed = false;
        return StatefulBuilder(
          builder: (_, setState) => AlertDialog(
            title: const Text('Carton'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<CoachPlayer>(
                  decoration: const InputDecoration(labelText: 'Joueur'),
                  value: target,
                  items: players
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.name),
                          ))
                      .toList(),
                  onChanged: (p) => setState(() => target = p),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Jaune'),
                      icon: Icon(Icons.square_rounded, color: Color(0xFFFFD600)),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Rouge'),
                      icon: Icon(Icons.square_rounded, color: Colors.red),
                    ),
                  ],
                  selected: {isRed},
                  onSelectionChanged: (v) =>
                      setState(() => isRed = v.first),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dCtx).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: target != null
                    ? () {
                        ctrl.addCard(
                            playerId: target!.id, isRed: isRed);
                        Navigator.of(dCtx).pop();
                      }
                    : null,
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showNoteDialog(BuildContext ctx) {
    final controller = TextEditingController();
    showDialog<void>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Note tactique'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Consigne, observation…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              ctrl.addNote(controller.text);
              Navigator.of(dCtx).pop();
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        backgroundColor: color.withOpacity(0.15),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.state,
    required this.onDelete,
  });
  final CoachEvent event;
  final CoachBoardState state;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    String subtitle = '';
    if (event.type == CoachEventType.goalUs && event.playerId != null) {
      final scorer = state.playerById(event.playerId);
      if (scorer != null) subtitle = 'Buteur : ${scorer.name}';
    } else if (event.type == CoachEventType.substitution) {
      final playerIn = state.playerById(event.playerInId);
      final playerOut = state.playerById(event.playerOutId);
      subtitle =
          '↑ ${playerIn?.name ?? '?'}  ↓ ${playerOut?.name ?? '?'}';
    } else if ((event.type == CoachEventType.yellowCard ||
            event.type == CoachEventType.redCard) &&
        event.playerId != null) {
      final player = state.playerById(event.playerId);
      if (player != null) subtitle = player.name;
    } else if (event.type == CoachEventType.note && event.text != null) {
      subtitle = event.text!;
    }

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: event.type.color.withOpacity(0.2),
        child: Icon(event.type.icon, size: 16, color: event.type.color),
      ),
      title: Text(
        "${event.minute}' — ${event.type.label}",
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        tooltip: 'Supprimer',
        onPressed: onDelete,
      ),
    );
  }
}

// ─── Bottom sheet formation ───────────────────────────────────────────────────

class _FormationSheet extends StatelessWidget {
  const _FormationSheet({
    required this.formations,
    required this.currentCode,
    required this.onSelected,
  });
  final List<_FormationOption> formations;
  final String currentCode;
  final void Function(_FormationOption) onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Changer la formation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...formations.map(
            (opt) => ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  opt.code,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              title: Text(opt.label),
              trailing: currentCode == opt.code
                  ? Icon(Icons.check,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () => onSelected(opt),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
