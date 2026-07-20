class SportsManagementFeature {
  const SportsManagementFeature({
    required this.enabled,
    required this.availabilityOpenHoursBefore,
    required this.reminderHoursBefore,
    required this.usualSquadSize,
    required this.voteDurationHours,
    required this.timezone,
    required this.updatedAt,
  });

  const SportsManagementFeature.disabled()
      : enabled = false,
        availabilityOpenHoursBefore = 144,
        reminderHoursBefore = const [72, 24],
        usualSquadSize = 14,
        voteDurationHours = 24,
        timezone = 'Europe/Paris',
        updatedAt = null;

  final bool enabled;
  final int availabilityOpenHoursBefore;
  final List<int> reminderHoursBefore;
  final int usualSquadSize;
  final int voteDurationHours;
  final String timezone;
  final DateTime? updatedAt;

  factory SportsManagementFeature.fromJson(Map<String, dynamic> json) {
    final config = _asStringMap(json['config']);

    return SportsManagementFeature(
      enabled: json['enabled'] == true,
      availabilityOpenHoursBefore: _positiveInt(
        config['availability_open_hours_before'],
        fallback: 144,
      ),
      reminderHoursBefore: _positiveIntList(
        config['reminder_hours_before'],
        fallback: const [72, 24],
      ),
      usualSquadSize: _positiveInt(config['usual_squad_size'], fallback: 14),
      voteDurationHours: _positiveInt(
        config['vote_duration_hours'],
        fallback: 24,
      ),
      timezone: _nonEmptyText(config['timezone'], fallback: 'Europe/Paris'),
      updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}'),
    );
  }
}

class FeatureFlagsSnapshot {
  const FeatureFlagsSnapshot({
    required this.sportsManagement,
    required this.sourceAvailable,
  });

  const FeatureFlagsSnapshot.unavailable()
      : sportsManagement = const SportsManagementFeature.disabled(),
        sourceAvailable = false;

  final SportsManagementFeature sportsManagement;

  /// False means that the server value could not be read. Consumers must fail
  /// closed and treat every optional feature as disabled.
  final bool sourceAvailable;

  factory FeatureFlagsSnapshot.fromRpc(Object? payload) {
    final root = _asStringMap(payload);
    if (root.isEmpty) {
      throw const FormatException('Feature flags response must be an object.');
    }

    final sportsManagement = _asStringMap(root['sports_management']);
    if (sportsManagement.isEmpty) {
      throw const FormatException('Sports-management feature flag is missing.');
    }

    return FeatureFlagsSnapshot(
      sportsManagement: SportsManagementFeature.fromJson(sportsManagement),
      sourceAvailable: true,
    );
  }
}

Map<String, dynamic> _asStringMap(Object? value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(value);
}

int _positiveInt(Object? value, {required int fallback}) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed > 0 ? parsed : fallback;
}

List<int> _positiveIntList(Object? value, {required List<int> fallback}) {
  if (value is! List) return List<int>.unmodifiable(fallback);

  final result = value
      .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
      .whereType<int>()
      .where((item) => item > 0)
      .toList(growable: false);

  return result.isEmpty
      ? List<int>.unmodifiable(fallback)
      : List<int>.unmodifiable(result);
}

String _nonEmptyText(Object? value, {required String fallback}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}
