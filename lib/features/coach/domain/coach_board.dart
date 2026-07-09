import 'dart:math';

import 'package:flutter/material.dart';

class CoachPlayer {
  const CoachPlayer({
    required this.id,
    required this.name,
    this.surnom,
    this.isGoalkeeper = false,
  });

  final String id;
  final String name;
  final String? surnom;
  final bool isGoalkeeper;

  String get displayName {
    final s = surnom?.trim() ?? '';
    if (s.isNotEmpty) return s;
    final first = name.trim().split(RegExp(r'\s+')).firstOrNull ?? '';
    return first.isEmpty ? 'Joueur' : first;
  }

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String get firstName => displayName.split(' ').first;
}

enum CoachEventType {
  goalUs,
  goalThem,
  substitution,
  yellowCard,
  redCard,
  note,
}

extension CoachEventTypeX on CoachEventType {
  String get label => switch (this) {
        CoachEventType.goalUs => 'But AS Grinta',
        CoachEventType.goalThem => 'But adversaire',
        CoachEventType.substitution => 'Remplacement',
        CoachEventType.yellowCard => 'Carton jaune',
        CoachEventType.redCard => 'Carton rouge',
        CoachEventType.note => 'Note',
      };

  IconData get icon => switch (this) {
        CoachEventType.goalUs || CoachEventType.goalThem => Icons.sports_soccer,
        CoachEventType.substitution => Icons.swap_horiz,
        CoachEventType.yellowCard || CoachEventType.redCard => Icons.square_rounded,
        CoachEventType.note => Icons.sticky_note_2_outlined,
      };

  Color get color => switch (this) {
        CoachEventType.goalUs => const Color(0xFF1DB95F),
        CoachEventType.goalThem => const Color(0xFFEF5350),
        CoachEventType.substitution => const Color(0xFF42A5F5),
        CoachEventType.yellowCard => const Color(0xFFFFD600),
        CoachEventType.redCard => const Color(0xFFEF5350),
        CoachEventType.note => const Color(0xFF78909C),
      };
}

class CoachEvent {
  const CoachEvent({
    required this.id,
    required this.type,
    required this.minute,
    this.playerId,
    this.assistPlayerId,
    this.playerInId,
    this.playerOutId,
    this.text,
  });

  final String id;
  final CoachEventType type;
  final int minute;
  final String? playerId;
  final String? assistPlayerId;
  final String? playerInId;
  final String? playerOutId;
  final String? text;
}

class CoachBoardState {
  CoachBoardState({
    required this.players,
    required this.lineup,
    required this.bench,
    required this.formationCode,
    required this.formationSlots,
    required this.events,
    required this.isRunning,
    required this.elapsedSeconds,
    required this.plannedDurationMinutes,
    required this.scoreUs,
    required this.scoreThem,
    required this.isLoading,
    required this.canEdit,
    this.matchId,
    this.error,
  });

  final List<CoachPlayer> players;
  final Map<String, String> lineup;
  final List<String> bench;
  final String formationCode;
  final List<String> formationSlots;
  final List<CoachEvent> events;
  final bool isRunning;
  final int elapsedSeconds;
  final int plannedDurationMinutes;
  final int scoreUs;
  final int scoreThem;
  final bool isLoading;
  final bool canEdit;
  final String? matchId;
  final String? error;

  factory CoachBoardState.initial({bool canEdit = false}) => CoachBoardState(
        players: const [],
        lineup: const {},
        bench: const [],
        formationCode: '4-3-3',
        formationSlots: hardcodedFormationSlots('4-3-3'),
        events: const [],
        isRunning: false,
        elapsedSeconds: 0,
        plannedDurationMinutes: 90,
        scoreUs: 0,
        scoreThem: 0,
        isLoading: true,
        canEdit: canEdit,
      );

  CoachBoardState copyWith({
    List<CoachPlayer>? players,
    Map<String, String>? lineup,
    List<String>? bench,
    String? formationCode,
    List<String>? formationSlots,
    List<CoachEvent>? events,
    bool? isRunning,
    int? elapsedSeconds,
    int? plannedDurationMinutes,
    int? scoreUs,
    int? scoreThem,
    bool? isLoading,
    bool? canEdit,
    String? matchId,
    String? error,
    bool clearError = false,
  }) {
    return CoachBoardState(
      players: players ?? this.players,
      lineup: lineup ?? Map<String, String>.from(this.lineup),
      bench: bench ?? List<String>.from(this.bench),
      formationCode: formationCode ?? this.formationCode,
      formationSlots: formationSlots ?? List<String>.from(this.formationSlots),
      events: events ?? List<CoachEvent>.from(this.events),
      isRunning: isRunning ?? this.isRunning,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      plannedDurationMinutes:
          plannedDurationMinutes ?? this.plannedDurationMinutes,
      scoreUs: scoreUs ?? this.scoreUs,
      scoreThem: scoreThem ?? this.scoreThem,
      isLoading: isLoading ?? this.isLoading,
      canEdit: canEdit ?? this.canEdit,
      matchId: matchId ?? this.matchId,
      error: clearError ? null : (error ?? this.error),
    );
  }

  CoachPlayer? playerById(String? id) {
    if (id == null) return null;
    for (final player in players) {
      if (player.id == id) return player;
    }
    return null;
  }
}

Map<String, Offset> computeFormationPositions(
  String formationCode,
  List<String> slots,
) {
  final positions = <String, Offset>{};
  if (slots.isEmpty) return positions;

  final gkSlot = slots.firstWhere(
    (s) => s.toLowerCase().startsWith('gk'),
    orElse: () => '',
  );
  if (gkSlot.isNotEmpty) positions[gkSlot] = const Offset(0.5, 0.90);

  final outfield =
      slots.where((s) => !s.toLowerCase().startsWith('gk')).toList();
  if (outfield.isEmpty) return positions;

  final parts =
      formationCode.split('-').map(int.tryParse).whereType<int>().toList();
  if (parts.isEmpty) {
    for (var i = 0; i < outfield.length; i++) {
      positions[outfield[i]] = Offset((i + 1) / (outfield.length + 1.0), 0.5);
    }
    return positions;
  }

  final numRows = parts.length;
  var slotIdx = 0;
  for (var rowIdx = 0; rowIdx < numRows; rowIdx++) {
    final numInRow = parts[rowIdx];
    final dy = numRows == 1
        ? 0.48
        : 0.74 - rowIdx * (0.60 / max(1, numRows - 1));
    for (var colIdx = 0;
        colIdx < numInRow && slotIdx < outfield.length;
        colIdx++) {
      positions[outfield[slotIdx]] =
          Offset((colIdx + 1) / (numInRow + 1.0), dy);
      slotIdx++;
    }
  }
  while (slotIdx < outfield.length) {
    positions[outfield[slotIdx]] = Offset((slotIdx % 5 + 1) / 6.0, 0.08);
    slotIdx++;
  }
  return positions;
}

List<String> hardcodedFormationSlots(String formationCode) {
  return switch (formationCode) {
    '4-4-2' => [
        'gk', 'lb', 'cb1', 'cb2', 'rb',
        'lm', 'cm1', 'cm2', 'rm',
        'st1', 'st2',
      ],
    '4-3-3' => [
        'gk', 'lb', 'cb1', 'cb2', 'rb',
        'dm', 'cm1', 'cm2',
        'lw', 'st', 'rw',
      ],
    '3-5-2' => [
        'gk', 'cb1', 'cb2', 'cb3',
        'lwb', 'dm1', 'cm', 'dm2', 'rwb',
        'st1', 'st2',
      ],
    '4-2-3-1' => [
        'gk', 'lb', 'cb1', 'cb2', 'rb',
        'dm1', 'dm2', 'lw', 'am', 'rw', 'st',
      ],
    '5-3-2' => [
        'gk', 'lb', 'cb1', 'cb2', 'cb3', 'rb',
        'cm1', 'cm2', 'cm3', 'st1', 'st2',
      ],
    _ => ['gk', 'lb', 'cb1', 'cb2', 'rb', 'dm', 'cm1', 'cm2', 'lw', 'st', 'rw'],
  };
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
