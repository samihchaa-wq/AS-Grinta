enum GoalType { openPlay, penalty, freeKick, ownGoal }

class LivePlayer {
  const LivePlayer({required this.id, required this.name});

  final String id;
  final String name;
}

class LiveGoal {
  const LiveGoal({
    required this.id,
    required this.team,
    required this.minute,
    required this.type,
    required this.scorerId,
    required this.assisterId,
  });

  final String id;
  final String team;
  final int minute;
  final GoalType type;
  final String? scorerId;
  final String? assisterId;
}

class LiveGameplayState {
  LiveGameplayState({
    required this.players,
    required this.formationKey,
    required this.lineup,
    required this.bench,
    required this.goals,
    required this.substitutions,
  });

  final List<LivePlayer> players;
  String formationKey;
  Map<String, String> lineup;
  List<String> bench;
  List<LiveGoal> goals;
  List<LiveSubstitution> substitutions;

  factory LiveGameplayState.initial({
    required List<LivePlayer> players,
    required String formationKey,
  }) {
    final slots = formationSlots(formationKey);
    final lineup = <String, String>{};
    final bench = players.map((player) => player.id).toList();

    for (final slot in slots) {
      if (bench.isNotEmpty) {
        lineup[slot] = bench.removeAt(0);
      }
    }

    return LiveGameplayState(
      players: players,
      formationKey: formationKey,
      lineup: lineup,
      bench: bench,
      goals: <LiveGoal>[],
      substitutions: <LiveSubstitution>[],
    );
  }

  static const List<String> supportedFormations = [
    '4-4-2',
    '4-3-3',
    '3-5-2',
    '4-2-3-1',
    '5-3-2'
  ];

  static List<String> formationSlots(String formationKey) {
    return switch (formationKey) {
      '4-4-2' => [
          'gk',
          'lb',
          'cb1',
          'cb2',
          'rb',
          'lm',
          'cm1',
          'cm2',
          'rm',
          'lw',
          'st1',
          'st2',
          'rw'
        ],
      '4-3-3' => [
          'gk',
          'lb',
          'cb1',
          'cb2',
          'rb',
          'dm',
          'cm1',
          'cm2',
          'lw',
          'st',
          'rw'
        ],
      '3-5-2' => [
          'gk',
          'cb1',
          'cb2',
          'cb3',
          'lwb',
          'dm1',
          'dm2',
          'rwb',
          'lw',
          'st1',
          'st2'
        ],
      '4-2-3-1' => [
          'gk',
          'lb',
          'cb1',
          'cb2',
          'rb',
          'dm1',
          'dm2',
          'am',
          'lw',
          'st',
          'rw'
        ],
      '5-3-2' => [
          'gk',
          'lb',
          'cb1',
          'cb2',
          'cb3',
          'rb',
          'dm1',
          'dm2',
          'dm3',
          'st1',
          'st2'
        ],
      _ => [
          'gk',
          'lb',
          'cb1',
          'cb2',
          'rb',
          'lm',
          'cm1',
          'cm2',
          'rm',
          'st1',
          'st2'
        ],
    };
  }

  void changeFormation(String newFormationKey) {
    final nextSlots = formationSlots(newFormationKey);
    final nextLineup = <String, String>{};
    final occupiedIds = <String>{};

    for (final slot in nextSlots) {
      final playerId = lineup[slot];
      if (playerId != null && !occupiedIds.contains(playerId)) {
        nextLineup[slot] = playerId;
        occupiedIds.add(playerId);
      }
    }

    final remainingPlayers = players
        .map((player) => player.id)
        .where((playerId) => !occupiedIds.contains(playerId))
        .toList();
    bench = remainingPlayers;
    lineup = nextLineup;
    formationKey = newFormationKey;
  }

  void movePlayer({required String playerId, required String slotKey}) {
    if (slotKey == 'bench') {
      lineup.removeWhere((_, value) => value == playerId);
      if (!bench.contains(playerId)) {
        bench.add(playerId);
      }
      return;
    }

    final currentSlot = lineup.entries
        .where((entry) => entry.value == playerId)
        .firstOrNull
        ?.key;
    if (currentSlot == slotKey) {
      return;
    }

    if (currentSlot != null) {
      lineup.remove(currentSlot);
      if (!bench.contains(playerId)) {
        bench.add(playerId);
      }
    }

    final occupiedBy = lineup[slotKey];
    if (occupiedBy != null && occupiedBy != playerId) {
      lineup.remove(slotKey);
      if (!bench.contains(occupiedBy)) {
        bench.add(occupiedBy);
      }
    }

    bench.remove(playerId);
    lineup[slotKey] = playerId;
  }

  LiveGoal addGoal({
    required String team,
    required int minute,
    required GoalType type,
    required String? scorerId,
    required String? assisterId,
  }) {
    final goal = LiveGoal(
      id: 'goal-${goals.length + 1}',
      team: team,
      minute: minute,
      type: type,
      scorerId: type == GoalType.ownGoal ? null : scorerId,
      assisterId: type == GoalType.ownGoal ? null : assisterId,
    );
    goals.add(goal);
    return goal;
  }

  void removeGoal(String goalId) {
    goals.removeWhere((goal) => goal.id == goalId);
  }

  void updateGoal({
    required String goalId,
    required String team,
    required int minute,
    required GoalType type,
    required String? scorerId,
    required String? assisterId,
  }) {
    final index = goals.indexWhere((goal) => goal.id == goalId);
    if (index == -1) return;

    final updatedGoal = LiveGoal(
      id: goalId,
      team: team,
      minute: minute,
      type: type,
      scorerId: type == GoalType.ownGoal ? null : scorerId,
      assisterId: type == GoalType.ownGoal ? null : assisterId,
    );
    goals[index] = updatedGoal;
  }

  void addSubstitution(
      {required int minute,
      required String inPlayerId,
      required String outPlayerId}) {
    substitutions.add(LiveSubstitution(
      id: 'sub-${substitutions.length + 1}',
      minute: minute,
      inPlayerId: inPlayerId,
      outPlayerId: outPlayerId,
    ));

    final slot = lineup.entries
        .where((entry) => entry.value == outPlayerId)
        .firstOrNull
        ?.key;
    if (slot != null) {
      lineup.remove(slot);
      lineup[slot] = inPlayerId;
      bench.remove(inPlayerId);
      if (!bench.contains(outPlayerId)) {
        bench.add(outPlayerId);
      }
    }
  }

  LiveGameplayState copyWith({
    List<LivePlayer>? players,
    String? formationKey,
    Map<String, String>? lineup,
    List<String>? bench,
    List<LiveGoal>? goals,
    List<LiveSubstitution>? substitutions,
  }) {
    return LiveGameplayState(
      players: players ?? this.players,
      formationKey: formationKey ?? this.formationKey,
      lineup: lineup ?? Map<String, String>.from(this.lineup),
      bench: bench ?? List<String>.from(this.bench),
      goals: goals ?? List<LiveGoal>.from(this.goals),
      substitutions:
          substitutions ?? List<LiveSubstitution>.from(this.substitutions),
    );
  }
}

class LiveSubstitution {
  const LiveSubstitution({
    required this.id,
    required this.minute,
    required this.inPlayerId,
    required this.outPlayerId,
  });

  final String id;
  final int minute;
  final String inPlayerId;
  final String outPlayerId;
}

extension IterableExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
