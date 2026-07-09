import 'dart:async';
import 'dart:math';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/coach/domain/coach_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoachBoardController extends StateNotifier<CoachBoardState> {
  CoachBoardController(this._client) : super(CoachBoardState.initial()) {
    _initialize();
  }

  final SupabaseClient _client;
  Timer? _ticker;
  int _eventCounter = 0;

  String _nextEventId() => 'evt-${++_eventCounter}-${DateTime.now().millisecondsSinceEpoch}';

  Future<void> _initialize() async {
    try {
      // Charger les joueurs actifs
      final profilesResponse = await _client
          .from('profiles')
          .select('id, first_name, last_name, surnom, is_goalkeeper, status')
          .eq('status', 'active')
          .eq('role', 'pronostiqueur')
          .order('first_name')
          .order('last_name');

      final players = <CoachPlayer>[];
      for (final row in profilesResponse as List) {
        final map = Map<String, dynamic>.from(row);
        final firstName = (map['first_name'] ?? '').toString().trim();
        final lastName = (map['last_name'] ?? '').toString().trim();
        final name = '$firstName $lastName'.trim();
        if (name.isEmpty) continue;
        players.add(CoachPlayer(
          id: map['id'].toString(),
          name: name.isEmpty ? 'Joueur sans nom' : name,
          surnom: map['surnom']?.toString(),
          isGoalkeeper: map['is_goalkeeper'] == true,
        ));
      }

      // Charger les formations depuis Supabase
      var formationCode = '4-4-2';
      var formationSlots = hardcodedFormationSlots(formationCode);

      try {
        final formationsResponse = await _client
            .from('formations')
            .select('code, label, slots')
            .order('code');

        final formations = <Map<String, dynamic>>[];
        for (final row in formationsResponse as List) {
          formations.add(Map<String, dynamic>.from(row));
        }

        if (formations.isNotEmpty) {
          final first = formations.first;
          formationCode = first['code'].toString();
          final rawSlots = first['slots'];
          if (rawSlots is List) {
            formationSlots = rawSlots
                .map((s) => Map<String, dynamic>.from(s as Map))
                .map((s) => s['code']?.toString())
                .whereType<String>()
                .where((c) => c.isNotEmpty)
                .toList();
          }
        }
      } catch (_) {
        // La table formations peut être absente, utiliser le fallback
      }

      if (formationSlots.isEmpty) {
        formationSlots = hardcodedFormationSlots(formationCode);
      }

      // Remplir le terrain avec les joueurs (GK en premier si présent)
      final sorted = [...players]..sort((a, b) {
          if (a.isGoalkeeper && !b.isGoalkeeper) return -1;
          if (!a.isGoalkeeper && b.isGoalkeeper) return 1;
          return a.name.compareTo(b.name);
        });

      final lineup = <String, String>{};
      final remainingIds = sorted.map((p) => p.id).toList();

      for (final slot in formationSlots) {
        if (remainingIds.isEmpty) break;
        lineup[slot] = remainingIds.removeAt(0);
      }

      state = state.copyWith(
        players: players,
        lineup: lineup,
        bench: remainingIds,
        formationCode: formationCode,
        formationSlots: formationSlots,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
      );
    }
  }

  // ─── Formation ──────────────────────────────────────────────────────────────

  Future<void> setFormation(String code, List<String> slots) async {
    if (slots.isEmpty) return;

    final currentLineup = Map<String, String>.from(state.lineup);
    final newLineup = <String, String>{};
    final occupiedIds = <String>{};

    // Conserver les joueurs dans les slots qui existent dans la nouvelle formation
    for (final slot in slots) {
      final playerId = currentLineup[slot];
      if (playerId != null && !occupiedIds.contains(playerId)) {
        newLineup[slot] = playerId;
        occupiedIds.add(playerId);
      }
    }

    // Tous les joueurs non placés vont au banc
    final allIds = state.players.map((p) => p.id).toSet();
    final newBenchSet = allIds.difference(occupiedIds);

    final currentBench = List<String>.from(state.bench);
    final orderedBench = [
      ...currentBench.where(newBenchSet.contains),
      ...newBenchSet.where((id) => !currentBench.contains(id)),
    ];

    state = state.copyWith(
      formationCode: code,
      formationSlots: slots,
      lineup: newLineup,
      bench: orderedBench,
    );
  }

  // ─── Déplacements ────────────────────────────────────────────────────────────

  void movePlayer(String playerId, String slotCode) {
    if (slotCode == 'bench') {
      sendToBench(playerId);
      return;
    }

    final lineup = Map<String, String>.from(state.lineup);
    final bench = List<String>.from(state.bench);

    final currentSlot =
        lineup.entries.where((e) => e.value == playerId).firstOrNull?.key;
    if (currentSlot == slotCode) return; // Pas de changement

    final occupiedBy = lineup[slotCode];

    if (occupiedBy != null && occupiedBy != playerId) {
      // Échange avec le joueur en place
      if (currentSlot != null) {
        lineup[currentSlot] = occupiedBy;
      } else {
        // Le joueur vient du banc, envoyer l'occupant au banc
        if (!bench.contains(occupiedBy)) bench.add(occupiedBy);
      }
    } else if (currentSlot != null) {
      lineup.remove(currentSlot);
    }

    bench.remove(playerId);
    lineup[slotCode] = playerId;

    state = state.copyWith(lineup: lineup, bench: bench);
  }

  void sendToBench(String playerId) {
    final lineup = Map<String, String>.from(state.lineup);
    final bench = List<String>.from(state.bench);
    lineup.removeWhere((_, v) => v == playerId);
    if (!bench.contains(playerId)) bench.add(playerId);
    state = state.copyWith(lineup: lineup, bench: bench);
  }

  // ─── Chronomètre ─────────────────────────────────────────────────────────────

  void startTimer() {
    if (state.isRunning) return;
    state = state.copyWith(isRunning: true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
      }
    });
  }

  void pauseTimer() {
    _ticker?.cancel();
    _ticker = null;
    state = state.copyWith(isRunning: false);
  }

  void resetTimer() {
    _ticker?.cancel();
    _ticker = null;
    state = state.copyWith(isRunning: false, elapsedSeconds: 0);
  }

  void setDuration(int minutes) {
    state = state.copyWith(
      plannedDurationMinutes: minutes.clamp(1, 200),
    );
  }

  int get _currentMinute => max(1, (state.elapsedSeconds / 60).floor() + 1);

  // ─── Événements ──────────────────────────────────────────────────────────────

  void addGoalUs({String? scorerId}) {
    final events = List<CoachEvent>.from(state.events)
      ..add(CoachEvent(
        id: _nextEventId(),
        type: CoachEventType.goalUs,
        minute: _currentMinute,
        playerId: scorerId,
      ));
    state = state.copyWith(
      events: events,
      scoreUs: state.scoreUs + 1,
    );
  }

  void addGoalThem() {
    final events = List<CoachEvent>.from(state.events)
      ..add(CoachEvent(
        id: _nextEventId(),
        type: CoachEventType.goalThem,
        minute: _currentMinute,
      ));
    state = state.copyWith(
      events: events,
      scoreThem: state.scoreThem + 1,
    );
  }

  void addSubstitution({
    required String inPlayerId,
    required String outPlayerId,
  }) {
    if (inPlayerId == outPlayerId) return;

    final events = List<CoachEvent>.from(state.events)
      ..add(CoachEvent(
        id: _nextEventId(),
        type: CoachEventType.substitution,
        minute: _currentMinute,
        playerInId: inPlayerId,
        playerOutId: outPlayerId,
      ));

    // Mettre à jour le terrain
    final lineup = Map<String, String>.from(state.lineup);
    final bench = List<String>.from(state.bench);

    final slot = lineup.entries
        .where((e) => e.value == outPlayerId)
        .firstOrNull
        ?.key;
    if (slot != null) {
      lineup[slot] = inPlayerId;
      bench.remove(inPlayerId);
      if (!bench.contains(outPlayerId)) bench.add(outPlayerId);
    }

    state = state.copyWith(events: events, lineup: lineup, bench: bench);
  }

  void addCard({required String playerId, required bool isRed}) {
    final events = List<CoachEvent>.from(state.events)
      ..add(CoachEvent(
        id: _nextEventId(),
        type: isRed ? CoachEventType.redCard : CoachEventType.yellowCard,
        minute: _currentMinute,
        playerId: playerId,
      ));
    state = state.copyWith(events: events);
  }

  void addNote(String text) {
    if (text.trim().isEmpty) return;
    final events = List<CoachEvent>.from(state.events)
      ..add(CoachEvent(
        id: _nextEventId(),
        type: CoachEventType.note,
        minute: _currentMinute,
        text: text.trim(),
      ));
    state = state.copyWith(events: events);
  }

  void removeEvent(String eventId) {
    final events = List<CoachEvent>.from(state.events)
      ..removeWhere((e) => e.id == eventId);

    var scoreUs = 0;
    var scoreThem = 0;
    for (final event in events) {
      if (event.type == CoachEventType.goalUs) scoreUs++;
      if (event.type == CoachEventType.goalThem) scoreThem++;
    }

    state = state.copyWith(
      events: events,
      scoreUs: scoreUs,
      scoreThem: scoreThem,
    );
  }

  void resetBoard() {
    _ticker?.cancel();
    _ticker = null;

    // Remettre toutes les valeurs à zéro en conservant les joueurs/formation
    final sorted = [...state.players]..sort((a, b) {
        if (a.isGoalkeeper && !b.isGoalkeeper) return -1;
        if (!a.isGoalkeeper && b.isGoalkeeper) return 1;
        return a.name.compareTo(b.name);
      });

    final lineup = <String, String>{};
    final remaining = sorted.map((p) => p.id).toList();
    for (final slot in state.formationSlots) {
      if (remaining.isEmpty) break;
      lineup[slot] = remaining.removeAt(0);
    }

    state = CoachBoardState(
      players: state.players,
      lineup: lineup,
      bench: remaining,
      formationCode: state.formationCode,
      formationSlots: state.formationSlots,
      events: const [],
      isRunning: false,
      elapsedSeconds: 0,
      plannedDurationMinutes: state.plannedDurationMinutes,
      scoreUs: 0,
      scoreThem: 0,
      isLoading: false,
      error: null,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

extension _IterX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// autoDispose garantit que le Timer.periodic est annulé dès que
/// la page /coach est quittée et que plus aucun listener n'est actif.
final coachBoardControllerProvider =
    StateNotifierProvider.autoDispose<CoachBoardController, CoachBoardState>(
        (ref) {
  return CoachBoardController(ref.watch(supabaseClientProvider));
});
