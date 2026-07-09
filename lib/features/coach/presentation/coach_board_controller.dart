import 'dart:async';
import 'dart:math';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/coach/data/coach_live_repository.dart';
import 'package:as_grinta/features/coach/domain/coach_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoachBoardController extends StateNotifier<CoachBoardState> {
  CoachBoardController(
    this._client,
    this._repository, {
    required bool canEdit,
  }) : super(CoachBoardState.initial(canEdit: canEdit)) {
    _initialize();
  }

  final SupabaseClient _client;
  final CoachLiveRepository _repository;
  Timer? _ticker;
  StreamSubscription<CoachLiveSession?>? _sessionSubscription;
  StreamSubscription<List<CoachLiveEventRecord>>? _eventsSubscription;
  bool _persisting = false;

  static const _guestPrefix = 'guest|';

  Future<void> _initialize() async {
    try {
      final profilesResponse = await _client
          .from('profiles')
          .select()
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
        players.add(
          CoachPlayer(
            id: map['id'].toString(),
            name: name,
            surnom: map['surnom']?.toString(),
            isGoalkeeper: map['is_goalkeeper'] == true,
          ),
        );
      }

      final matchId = await _repository.findCurrentMatchId();
      if (matchId == null) {
        state = state.copyWith(
          players: players,
          bench: players.map((p) => p.id).toList(),
          isLoading: false,
          error: 'Aucun match à venir ou en cours.',
        );
        return;
      }

      state = state.copyWith(
        players: players,
        matchId: matchId,
        formationCode: '4-3-3',
        formationSlots: hardcodedFormationSlots('4-3-3'),
        lineup: const {},
        bench: players.map((p) => p.id).toList(),
        isLoading: false,
        clearError: true,
      );

      _sessionSubscription = _repository.watchSession(matchId).listen(
        (session) async {
          if (session == null) {
            if (state.canEdit) await _persistSession();
            return;
          }
          final ids = <String>{...session.lineup.values, ...session.bench};
          final regularPlayers = state.players.where((p) => !p.isGuest).toList();
          final guests = ids
              .where((id) => id.startsWith(_guestPrefix))
              .map(_guestFromId)
              .whereType<CoachPlayer>()
              .toList();
          state = state.copyWith(
            players: [...regularPlayers, ...guests],
            formationCode: session.formationCode,
            formationSlots: hardcodedFormationSlots(session.formationCode),
            lineup: session.lineup,
            bench: session.bench,
            scoreUs: session.scoreUs,
            scoreThem: session.scoreThem,
            elapsedSeconds: session.elapsedSeconds,
            plannedDurationMinutes: session.plannedDurationMinutes,
            isRunning: session.isRunning,
            clearError: true,
          );
          if (session.isRunning) {
            _startLocalTicker();
          } else {
            _stopLocalTicker();
          }
        },
        onError: (Object error) {
          state = state.copyWith(error: error.toString());
        },
      );

      _eventsSubscription = _repository.watchEvents(matchId).listen(
        (records) {
          final events = records.map(_mapEvent).toList(growable: false);
          final scoreUs =
              events.where((e) => e.type == CoachEventType.goalUs).length;
          final scoreThem =
              events.where((e) => e.type == CoachEventType.goalThem).length;
          state = state.copyWith(
            events: events,
            scoreUs: scoreUs,
            scoreThem: scoreThem,
          );
        },
        onError: (Object error) {
          state = state.copyWith(error: error.toString());
        },
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  CoachPlayer? _guestFromId(String id) {
    final parts = id.split('|');
    if (parts.length < 4 || parts.first != 'guest') return null;
    final name = Uri.decodeComponent(parts.sublist(3).join('|')).trim();
    if (name.isEmpty) return null;
    return CoachPlayer(
      id: id,
      name: name,
      isGoalkeeper: parts[1] == 'gk',
      isGuest: true,
    );
  }

  Future<void> addExceptionalPlayer({
    required String name,
    required bool isGoalkeeper,
    required String slotCode,
  }) async {
    if (!state.canEdit || name.trim().isEmpty) return;
    final id = 'guest|${isGoalkeeper ? 'gk' : 'field'}|${DateTime.now().microsecondsSinceEpoch}|${Uri.encodeComponent(name.trim())}';
    final guest = CoachPlayer(
      id: id,
      name: name.trim(),
      isGoalkeeper: isGoalkeeper,
      isGuest: true,
    );
    state = state.copyWith(players: [...state.players, guest]);
    await movePlayer(id, slotCode);
  }

  CoachEvent _mapEvent(CoachLiveEventRecord record) {
    final type = switch (record.type) {
      'goal_us' => CoachEventType.goalUs,
      'goal_them' => CoachEventType.goalThem,
      'substitution' => CoachEventType.substitution,
      _ => CoachEventType.note,
    };
    return CoachEvent(
      id: record.id,
      type: type,
      minute: record.minute,
      playerId: record.scorerId,
      assistPlayerId: record.assistId,
      playerInId: record.playerInId,
      playerOutId: record.playerOutId,
    );
  }

  Future<void> _persistSession() async {
    if (!state.canEdit || state.matchId == null || _persisting) return;
    _persisting = true;
    try {
      await _repository.saveSession(
        CoachLiveSession(
          matchId: state.matchId!,
          formationCode: state.formationCode,
          lineup: state.lineup,
          bench: state.bench,
          scoreUs: state.scoreUs,
          scoreThem: state.scoreThem,
          elapsedSeconds: state.elapsedSeconds,
          plannedDurationMinutes: state.plannedDurationMinutes,
          isRunning: state.isRunning,
        ),
      );
    } finally {
      _persisting = false;
    }
  }

  Future<void> setFormation(String code, List<String> slots) async {
    if (!state.canEdit || slots.isEmpty) return;
    final currentLineup = Map<String, String>.from(state.lineup);
    final newLineup = <String, String>{};
    final occupiedIds = <String>{};
    for (final slot in slots) {
      final playerId = currentLineup[slot];
      if (playerId != null && occupiedIds.add(playerId)) {
        newLineup[slot] = playerId;
      }
    }
    final allIds = state.players.map((p) => p.id).toSet();
    final benchSet = allIds.difference(occupiedIds);
    final orderedBench = [
      ...state.bench.where(benchSet.contains),
      ...benchSet.where((id) => !state.bench.contains(id)),
    ];
    state = state.copyWith(
      formationCode: code,
      formationSlots: slots,
      lineup: newLineup,
      bench: orderedBench,
    );
    await _persistSession();
  }

  Future<void> movePlayer(String playerId, String slotCode) async {
    if (!state.canEdit) return;
    if (slotCode == 'bench') {
      await sendToBench(playerId);
      return;
    }
    final lineup = Map<String, String>.from(state.lineup);
    final bench = List<String>.from(state.bench);
    final currentSlot =
        lineup.entries.where((e) => e.value == playerId).firstOrNull?.key;
    if (currentSlot == slotCode) return;
    final occupiedBy = lineup[slotCode];
    if (occupiedBy != null && occupiedBy != playerId) {
      if (currentSlot != null) {
        lineup[currentSlot] = occupiedBy;
      } else if (!bench.contains(occupiedBy)) {
        bench.add(occupiedBy);
      }
    } else if (currentSlot != null) {
      lineup.remove(currentSlot);
    }
    bench.remove(playerId);
    lineup[slotCode] = playerId;
    state = state.copyWith(lineup: lineup, bench: bench);
    await _persistSession();
  }

  Future<void> sendToBench(String playerId) async {
    if (!state.canEdit) return;
    final lineup = Map<String, String>.from(state.lineup)
      ..removeWhere((_, value) => value == playerId);
    final bench = List<String>.from(state.bench);
    if (!bench.contains(playerId)) bench.add(playerId);
    state = state.copyWith(lineup: lineup, bench: bench);
    await _persistSession();
  }

  void _startLocalTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !state.isRunning) return;
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
      if (state.canEdit && timer.tick % 5 == 0) {
        unawaited(_persistSession());
      }
    });
  }

  void _stopLocalTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> startTimer() async {
    if (!state.canEdit || state.isRunning || state.lineup.length != 11) return;
    state = state.copyWith(isRunning: true);
    _startLocalTicker();
    await _persistSession();
  }

  Future<void> pauseTimer() async {
    if (!state.canEdit) return;
    _stopLocalTicker();
    state = state.copyWith(isRunning: false);
    await _persistSession();
  }

  Future<void> resetTimer() async {
    if (!state.canEdit) return;
    _stopLocalTicker();
    state = state.copyWith(isRunning: false, elapsedSeconds: 0);
    await _persistSession();
  }

  Future<void> goToHalfTime() async {
    if (!state.canEdit) return;
    final half = (state.plannedDurationMinutes * 60 / 2).round();
    state = state.copyWith(isRunning: false, elapsedSeconds: half);
    _stopLocalTicker();
    await _persistSession();
  }

  Future<void> endMatch() async {
    if (!state.canEdit) return;
    _stopLocalTicker();
    state = state.copyWith(
      isRunning: false,
      elapsedSeconds: state.plannedDurationMinutes * 60,
    );
    await _persistSession();
  }

  Future<void> setDuration(int minutes) async {
    if (!state.canEdit) return;
    state = state.copyWith(plannedDurationMinutes: minutes.clamp(1, 200));
    await _persistSession();
  }

  int get _currentMinute => max(1, (state.elapsedSeconds / 60).floor() + 1);

  Future<void> addGoalUs({String? scorerId, String? assistId}) async {
    if (!state.canEdit || state.matchId == null) return;
    if (state.playerById(scorerId)?.isGuest == true) scorerId = null;
    if (state.playerById(assistId)?.isGuest == true) assistId = null;
    await _repository.addGoal(
      matchId: state.matchId!,
      minute: _currentMinute,
      isForUs: true,
      scorerId: scorerId,
      assistId: assistId,
    );
  }

  Future<void> addGoalThem() async {
    if (!state.canEdit || state.matchId == null) return;
    await _repository.addGoal(
      matchId: state.matchId!,
      minute: _currentMinute,
      isForUs: false,
    );
  }

  Future<void> addSubstitution({
    required String inPlayerId,
    required String outPlayerId,
  }) async {
    if (!state.canEdit || state.matchId == null || inPlayerId == outPlayerId) {
      return;
    }
    final lineup = Map<String, String>.from(state.lineup);
    final bench = List<String>.from(state.bench);
    final slot =
        lineup.entries.where((e) => e.value == outPlayerId).firstOrNull?.key;
    if (slot != null) {
      lineup[slot] = inPlayerId;
      bench.remove(inPlayerId);
      if (!bench.contains(outPlayerId)) bench.add(outPlayerId);
      state = state.copyWith(lineup: lineup, bench: bench);
      await _persistSession();
    }
    final hasGuest = state.playerById(inPlayerId)?.isGuest == true ||
        state.playerById(outPlayerId)?.isGuest == true;
    if (hasGuest) return;
    await _repository.addSubstitution(
      matchId: state.matchId!,
      minute: _currentMinute,
      playerInId: inPlayerId,
      playerOutId: outPlayerId,
    );
  }

  void addNote(String text) {}

  Future<void> removeEvent(String eventId) async {
    if (!state.canEdit) return;
    await _repository.deleteEvent(eventId);
  }

  Future<void> resetBoard() async {
    if (!state.canEdit) return;
    _stopLocalTicker();
    final regularPlayers = state.players.where((p) => !p.isGuest).toList();
    state = state.copyWith(
      players: regularPlayers,
      lineup: const {},
      bench: regularPlayers.map((p) => p.id).toList(),
      formationCode: '4-3-3',
      formationSlots: hardcodedFormationSlots('4-3-3'),
      isRunning: false,
      elapsedSeconds: 0,
      scoreUs: 0,
      scoreThem: 0,
      clearError: true,
    );
    for (final event in [...state.events]) {
      await _repository.deleteEvent(event.id);
    }
    await _persistSession();
  }

  @override
  void dispose() {
    _stopLocalTicker();
    _sessionSubscription?.cancel();
    _eventsSubscription?.cancel();
    super.dispose();
  }
}

extension _IterX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

final coachBoardControllerProvider =
    StateNotifierProvider.autoDispose<CoachBoardController, CoachBoardState>(
  (ref) {
    final canEdit = ref.watch(
      authControllerProvider.select((state) => state.profile?.role.isStaff == true),
    );
    return CoachBoardController(
      ref.watch(supabaseClientProvider),
      ref.watch(coachLiveRepositoryProvider),
      canEdit: canEdit,
    );
  },
);
