from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"{path}: expected one occurrence, found {count}: {old[:120]!r}"
        )
    file.write_text(text.replace(old, new, 1))


# Match model.
p = "lib/features/matches/domain/match_model.dart"
replace_once(
    p,
    "import 'package:as_grinta/core/utils/match_window.dart';\n",
    "import 'package:as_grinta/core/utils/match_window.dart';\n"
    "import 'package:as_grinta/features/matches/domain/match_meeting.dart';\n",
)
replace_once(
    p,
    "    this.address,\n    this.matchType = 'championnat',",
    "    this.address,\n    this.meetingAt,\n    this.matchType = 'championnat',",
)
replace_once(
    p,
    "  /// Adresse du lieu de la rencontre (facultative).\n"
    "  final String? address;\n\n"
    "  /// « amical »",
    "  /// Adresse du lieu de la rencontre (facultative).\n"
    "  final String? address;\n\n"
    "  /// Heure de rendez-vous explicite. NULL = 30 min avant le coup d’envoi.\n"
    "  final DateTime? meetingAt;\n\n"
    "  DateTime get effectiveMeetingAt => resolvedMatchMeetingAt(\n"
    "        kickoffAt: kickoffAt,\n"
    "        customMeetingAt: meetingAt,\n"
    "      );\n\n"
    "  /// « amical »",
)
replace_once(
    p,
    "      address: (json['address']?.toString().trim().isNotEmpty ?? false)\n"
    "          ? json['address'].toString()\n"
    "          : null,\n"
    "      matchType:",
    "      address: (json['address']?.toString().trim().isNotEmpty ?? false)\n"
    "          ? json['address'].toString()\n"
    "          : null,\n"
    "      meetingAt: DateTime.tryParse(\n"
    "        '${json['meeting_at'] ?? ''}',\n"
    "      )?.toLocal(),\n"
    "      matchType:",
)

# Calendar cache.
p = "lib/features/matches/data/calendar_matches_local_cache.dart"
replace_once(
    p,
    "      'kickoff_at': match.kickoffAt.toUtc().toIso8601String(),\n"
    "      'location':",
    "      'kickoff_at': match.kickoffAt.toUtc().toIso8601String(),\n"
    "      'meeting_at': match.meetingAt?.toUtc().toIso8601String(),\n"
    "      'location':",
)

# Scheduled creation repository.
p = "lib/features/matches/data/scheduled_match_creation_repository.dart"
replace_once(
    p,
    "    DateTime? customLaunchAt,\n    int? squadSizeLimit,",
    "    DateTime? customLaunchAt,\n    DateTime? meetingAt,\n    int? squadSizeLimit,",
)
replace_once(p, "      'admin_create_match_complete_v2',", "      'admin_create_match_complete_v3',")
replace_once(
    p,
    "        'p_availability_opens_at': launchMode == ConvocationLaunchMode.custom\n"
    "            ? customLaunchAt?.toUtc().toIso8601String()\n"
    "            : null,\n"
    "      },\n"
    "    );\n"
    "    if (result == null || result.toString().isEmpty) {\n"
    "      throw StateError('Le match n’a pas pu être créé.');\n"
    "    }\n"
    "    return result.toString();\n"
    "  }\n\n"
    "  Future<String> createInternalMatch({",
    "        'p_availability_opens_at': launchMode == ConvocationLaunchMode.custom\n"
    "            ? customLaunchAt?.toUtc().toIso8601String()\n"
    "            : null,\n"
    "        'p_meeting_at': meetingAt?.toUtc().toIso8601String(),\n"
    "      },\n"
    "    );\n"
    "    if (result == null || result.toString().isEmpty) {\n"
    "      throw StateError('Le match n’a pas pu être créé.');\n"
    "    }\n"
    "    return result.toString();\n"
    "  }\n\n"
    "  Future<String> createInternalMatch({",
)
replace_once(
    p,
    "    DateTime? customLaunchAt,\n    String? address,\n  }) async {\n"
    "    final result = await _client.rpc(\n"
    "      'create_internal_match_v2',",
    "    DateTime? customLaunchAt,\n    DateTime? meetingAt,\n    String? address,\n  }) async {\n"
    "    final result = await _client.rpc(\n"
    "      'create_internal_match_v3',",
)
replace_once(
    p,
    "        'p_availability_opens_at': launchMode == ConvocationLaunchMode.custom\n"
    "            ? customLaunchAt?.toUtc().toIso8601String()\n"
    "            : null,\n"
    "      },\n"
    "    );\n"
    "    if (result == null || result.toString().isEmpty) {\n"
    "      throw StateError('Le match n’a pas pu être créé.');\n"
    "    }\n"
    "    return result.toString();\n"
    "  }\n\n"
    "  String _formatTime",
    "        'p_availability_opens_at': launchMode == ConvocationLaunchMode.custom\n"
    "            ? customLaunchAt?.toUtc().toIso8601String()\n"
    "            : null,\n"
    "        'p_meeting_at': meetingAt?.toUtc().toIso8601String(),\n"
    "      },\n"
    "    );\n"
    "    if (result == null || result.toString().isEmpty) {\n"
    "      throw StateError('Le match n’a pas pu être créé.');\n"
    "    }\n"
    "    return result.toString();\n"
    "  }\n\n"
    "  String _formatTime",
)

# Main match repository.
p = "lib/features/matches/data/matches_repository.dart"
replace_once(p, "      kickoff_at,\n      location,", "      kickoff_at,\n      meeting_at,\n      location,")
replace_once(
    p,
    "    String matchType = 'championnat',\n"
    "    String? jerseyNote,\n"
    "  }) async {\n"
    "    final result = await _client.rpc(\n"
    "      'admin_create_match_complete',",
    "    String matchType = 'championnat',\n"
    "    String? jerseyNote,\n"
    "    DateTime? meetingAt,\n"
    "  }) async {\n"
    "    final result = await _client.rpc(\n"
    "      'admin_create_match_complete_v3',",
)
replace_once(
    p,
    "        'p_match_type': matchType,\n"
    "        'p_jersey_note': jerseyNote,\n"
    "      },\n"
    "    );\n"
    "    if (result == null || result.toString().isEmpty)",
    "        'p_match_type': matchType,\n"
    "        'p_jersey_note': jerseyNote,\n"
    "        'p_availability_schedule_mode': 'automatic',\n"
    "        'p_availability_opens_at': null,\n"
    "        'p_meeting_at': meetingAt?.toUtc().toIso8601String(),\n"
    "      },\n"
    "    );\n"
    "    if (result == null || result.toString().isEmpty)",
)
replace_once(
    p,
    "  Future<String> createInternalMatch({\n"
    "    required String seasonId,\n"
    "    required DateTime kickoffAt,\n"
    "    String? address,\n"
    "  }) async {\n"
    "    final result = await _client.rpc(\n"
    "      'create_internal_match',",
    "  Future<String> createInternalMatch({\n"
    "    required String seasonId,\n"
    "    required DateTime kickoffAt,\n"
    "    String? address,\n"
    "    DateTime? meetingAt,\n"
    "  }) async {\n"
    "    final result = await _client.rpc(\n"
    "      'create_internal_match_v3',",
)
replace_once(
    p,
    "        'p_match_time': _formatTime(kickoffAt),\n"
    "        'p_address': address,\n"
    "      },\n"
    "    );\n"
    "    if (result == null || result.toString().isEmpty)",
    "        'p_match_time': _formatTime(kickoffAt),\n"
    "        'p_address': address,\n"
    "        'p_availability_schedule_mode': 'automatic',\n"
    "        'p_availability_opens_at': null,\n"
    "        'p_meeting_at': meetingAt?.toUtc().toIso8601String(),\n"
    "      },\n"
    "    );\n"
    "    if (result == null || result.toString().isEmpty)",
)
replace_once(
    p,
    "    required DateTime expectedUpdatedAt,\n"
    "    String? address,\n"
    "  }) async {\n"
    "    final result = await _client.rpc(\n"
    "      'update_internal_match',",
    "    required DateTime expectedUpdatedAt,\n"
    "    String? address,\n"
    "    DateTime? meetingAt,\n"
    "  }) async {\n"
    "    final result = await _client.rpc(\n"
    "      'update_internal_match_v2',",
)
replace_once(
    p,
    "        'p_address': address,\n"
    "        'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),\n"
    "      },\n"
    "    );\n"
    "    if (result != true) {",
    "        'p_address': address,\n"
    "        'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),\n"
    "        'p_meeting_at': meetingAt?.toUtc().toIso8601String(),\n"
    "      },\n"
    "    );\n"
    "    if (result != true) {",
)
replace_once(
    p,
    "    String matchType = 'championnat',\n"
    "    String? jerseyNote,\n"
    "  }) async {\n"
    "    final result = await _client.rpc(\n"
    "      'admin_update_match_complete',",
    "    String matchType = 'championnat',\n"
    "    String? jerseyNote,\n"
    "    DateTime? meetingAt,\n"
    "  }) async {\n"
    "    final result = await _client.rpc(\n"
    "      'admin_update_match_complete_v2',",
)
replace_once(
    p,
    "        'p_match_type': matchType,\n"
    "        'p_jersey_note': jerseyNote,\n"
    "      },\n"
    "    );\n"
    "    if (result != true) {",
    "        'p_match_type': matchType,\n"
    "        'p_jersey_note': jerseyNote,\n"
    "        'p_meeting_at': meetingAt?.toUtc().toIso8601String(),\n"
    "      },\n"
    "    );\n"
    "    if (result != true) {",
)

# Controller plumbing.
p = "lib/features/matches/presentation/matches_controller.dart"
replace_once(
    p,
    "    String matchType = 'championnat',\n"
    "    String? jerseyNote,\n"
    "  }) async {\n"
    "    if (!_canManageMatches) {\n"
    "      state = state.copyWith(isLoading: false, error: 'Droits insuffisants.');\n"
    "      return;\n"
    "    }\n"
    "    if (seasonId.isEmpty || opponentId.isEmpty)",
    "    String matchType = 'championnat',\n"
    "    String? jerseyNote,\n"
    "    DateTime? meetingAt,\n"
    "  }) async {\n"
    "    if (!_canManageMatches) {\n"
    "      state = state.copyWith(isLoading: false, error: 'Droits insuffisants.');\n"
    "      return;\n"
    "    }\n"
    "    if (seasonId.isEmpty || opponentId.isEmpty)",
)
replace_once(
    p,
    "        matchType: matchType,\n"
    "        jerseyNote: jerseyNote,\n"
    "      );\n"
    "      await load(\n"
    "        seasonId: state.selectedSeasonId,",
    "        matchType: matchType,\n"
    "        jerseyNote: jerseyNote,\n"
    "        meetingAt: meetingAt,\n"
    "      );\n"
    "      await load(\n"
    "        seasonId: state.selectedSeasonId,",
)
replace_once(
    p,
    "    String matchType = 'championnat',\n"
    "    String? jerseyNote,\n"
    "  }) async {\n"
    "    if (!_canManageMatches) {\n"
    "      state = state.copyWith(isLoading: false, error: 'Droits insuffisants.');\n"
    "      return;\n"
    "    }\n"
    "    if (id.isEmpty || seasonId.isEmpty || opponentId.isEmpty)",
    "    String matchType = 'championnat',\n"
    "    String? jerseyNote,\n"
    "    DateTime? meetingAt,\n"
    "  }) async {\n"
    "    if (!_canManageMatches) {\n"
    "      state = state.copyWith(isLoading: false, error: 'Droits insuffisants.');\n"
    "      return;\n"
    "    }\n"
    "    if (id.isEmpty || seasonId.isEmpty || opponentId.isEmpty)",
)
replace_once(
    p,
    "        matchType: matchType,\n"
    "        jerseyNote: jerseyNote,\n"
    "      );\n"
    "      await load(\n"
    "        seasonId: state.selectedSeasonId,\n"
    "        allSeasons: state.includesAllSeasons,\n"
    "        forceRefresh: true,\n"
    "      );\n"
    "      _ref.invalidate(matchInfoProvider(id));",
    "        matchType: matchType,\n"
    "        jerseyNote: jerseyNote,\n"
    "        meetingAt: meetingAt,\n"
    "      );\n"
    "      await load(\n"
    "        seasonId: state.selectedSeasonId,\n"
    "        allSeasons: state.includesAllSeasons,\n"
    "        forceRefresh: true,\n"
    "      );\n"
    "      _ref.invalidate(matchInfoProvider(id));",
)
replace_once(
    p,
    "  Future<void> createInternalMatch({\n"
    "    required String seasonId,\n"
    "    required DateTime kickoffAt,\n"
    "    String? address,\n"
    "  }) async {",
    "  Future<void> createInternalMatch({\n"
    "    required String seasonId,\n"
    "    required DateTime kickoffAt,\n"
    "    String? address,\n"
    "    DateTime? meetingAt,\n"
    "  }) async {",
)
replace_once(
    p,
    "        seasonId: seasonId,\n"
    "        kickoffAt: kickoffAt,\n"
    "        address: address,\n"
    "      );\n"
    "      await load(\n"
    "        seasonId: state.selectedSeasonId,",
    "        seasonId: seasonId,\n"
    "        kickoffAt: kickoffAt,\n"
    "        address: address,\n"
    "        meetingAt: meetingAt,\n"
    "      );\n"
    "      await load(\n"
    "        seasonId: state.selectedSeasonId,",
)
replace_once(
    p,
    "    required DateTime? expectedUpdatedAt,\n"
    "    String? address,\n"
    "    bool rememberAddressAsDefault = false,\n"
    "  }) async {",
    "    required DateTime? expectedUpdatedAt,\n"
    "    String? address,\n"
    "    bool rememberAddressAsDefault = false,\n"
    "    DateTime? meetingAt,\n"
    "  }) async {",
)
replace_once(
    p,
    "        expectedUpdatedAt: expectedUpdatedAt,\n"
    "        address: address,\n"
    "      );\n"
    "      if (rememberAddressAsDefault)",
    "        expectedUpdatedAt: expectedUpdatedAt,\n"
    "        address: address,\n"
    "        meetingAt: meetingAt,\n"
    "      );\n"
    "      if (rememberAddressAsDefault)",
)

# Match info data.
p = "lib/features/matches/data/match_info_repository.dart"
replace_once(
    p,
    "import 'package:as_grinta/core/providers/supabase_provider.dart';\n",
    "import 'package:as_grinta/core/providers/supabase_provider.dart';\n"
    "import 'package:as_grinta/features/matches/domain/match_meeting.dart';\n",
)
replace_once(
    p,
    "    required this.address,\n    required this.opponentId,",
    "    required this.address,\n    this.meetingAt,\n    required this.opponentId,",
)
replace_once(
    p,
    "  final DateTime? kickoffAt;\n  final String? address;\n  final String? opponentId;",
    "  final DateTime? kickoffAt;\n  final String? address;\n  final DateTime? meetingAt;\n  final String? opponentId;",
)
replace_once(
    p,
    "    required this.address,\n    required this.lastEncounters,",
    "    required this.address,\n    this.meetingAt,\n    required this.lastEncounters,",
)
replace_once(
    p,
    "  final DateTime? kickoffAt;\n  final String? address;\n  final List<MatchEncounter> lastEncounters;",
    "  final DateTime? kickoffAt;\n  final String? address;\n  final DateTime? meetingAt;\n  final List<MatchEncounter> lastEncounters;",
)
replace_once(
    p,
    "  bool get isFriendly => matchType == 'amical';",
    "  DateTime? get effectiveMeetingAt => kickoffAt == null\n"
    "      ? null\n"
    "      : resolvedMatchMeetingAt(\n"
    "          kickoffAt: kickoffAt!,\n"
    "          customMeetingAt: meetingAt,\n"
    "        );\n\n"
    "  bool get isFriendly => matchType == 'amical';",
)
replace_once(
    p,
    "    kickoffAt: core.kickoffAt,\n"
    "    address: core.address,\n"
    "    lastEncounters: encounters,",
    "    kickoffAt: core.kickoffAt,\n"
    "    address: core.address,\n"
    "    meetingAt: core.meetingAt,\n"
    "    lastEncounters: encounters,",
)
replace_once(
    p,
    "        'kickoff_at, match_date, match_time, status, location, address, '\n"
    "        'opponent_id, match_type, jersey_note, opponents(name, address)',",
    "        'kickoff_at, match_date, match_time, meeting_at, status, location, address, '\n"
    "        'opponent_id, match_type, jersey_note, opponents(name, address)',",
)
replace_once(
    p,
    "    kickoffAt: kickoffAt,\n"
    "    address: address,\n"
    "    opponentId:",
    "    kickoffAt: kickoffAt,\n"
    "    address: address,\n"
    "    meetingAt: DateTime.tryParse(\n"
    "      '${match['meeting_at'] ?? ''}',\n"
    "    )?.toLocal(),\n"
    "    opponentId:",
)
replace_once(
    p,
    "    kickoffAt: baseInfo.kickoffAt,\n"
    "    address: baseInfo.address,\n"
    "    lastEncounters: encounters,",
    "    kickoffAt: baseInfo.kickoffAt,\n"
    "    address: baseInfo.address,\n"
    "    meetingAt: baseInfo.meetingAt,\n"
    "    lastEncounters: encounters,",
)

# Match info UI uses the resolved meeting time instead of a hard-coded H-30.
p = "lib/features/matches/presentation/widgets/match_info_tab.dart"
replace_once(
    p,
    "                            text: AppFormats.time(\n"
    "                              info.kickoffAt!.subtract(\n"
    "                                const Duration(minutes: 30),\n"
    "                              ),\n"
    "                            ),",
    "                            text: AppFormats.time(\n"
    "                              info.effectiveMeetingAt!,\n"
    "                            ),",
)

# Main calendar add form.
p = "lib/features/matches/presentation/calendar_entry_form_page.dart"
replace_once(
    p,
    "import 'package:as_grinta/features/matches/domain/jersey_option.dart';\n",
    "import 'package:as_grinta/features/matches/domain/jersey_option.dart';\n"
    "import 'package:as_grinta/features/matches/domain/match_meeting.dart';\n",
)
replace_once(
    p,
    "import 'package:as_grinta/features/matches/presentation/widgets/convocation_launch_picker.dart';\n",
    "import 'package:as_grinta/features/matches/presentation/widgets/convocation_launch_picker.dart';\n"
    "import 'package:as_grinta/features/matches/presentation/widgets/match_meeting_time_picker.dart';\n",
)
replace_once(
    p,
    "  ConvocationLaunchMode _launchMode = ConvocationLaunchMode.automatic;\n"
    "  DateTime? _customLaunchAt;\n",
    "  ConvocationLaunchMode _launchMode = ConvocationLaunchMode.automatic;\n"
    "  DateTime? _customLaunchAt;\n"
    "  DateTime? _meetingAt;\n",
)
replace_once(
    p,
    "      _dateTile(),\n"
    "      _timeTile(),\n"
    "      if (widget.event == null) ...[",
    "      _dateTile(),\n"
    "      _timeTile(),\n"
    "      MatchMeetingTimePicker(\n"
    "        kickoffAt: _startsAt,\n"
    "        customMeetingAt: _meetingAt,\n"
    "        enabled: !busy,\n"
    "        onChanged: (value) => setState(() => _meetingAt = value),\n"
    "      ),\n"
    "      if (widget.event == null) ...[",
)
replace_once(
    p,
    "      if (_isEvent) {\n"
    "        _addressController.clear();\n"
    "      } else {",
    "      if (_isEvent) {\n"
    "        _addressController.clear();\n"
    "        _meetingAt = null;\n"
    "      } else {",
)
# Date and time each contain the same repair call; replace both occurrences intentionally.
text = Path(p).read_text()
old = "      _repairCustomLaunchIfNeeded();\n    });"
if text.count(old) != 2:
    raise RuntimeError(f"{p}: expected two kickoff repair blocks, found {text.count(old)}")
Path(p).write_text(
    text.replace(
        old,
        "      _repairCustomLaunchIfNeeded();\n      _repairMeetingAt();\n    });",
    )
)
replace_once(
    p,
    "  void _repairCustomLaunchIfNeeded() {",
    "  void _repairMeetingAt() {\n"
    "    _meetingAt = preserveCustomMeetingTime(\n"
    "      kickoffAt: _startsAt,\n"
    "      customMeetingAt: _meetingAt,\n"
    "    );\n"
    "  }\n\n"
    "  void _repairCustomLaunchIfNeeded() {",
)
replace_once(
    p,
    "              launchMode: _launchMode,\n"
    "              customLaunchAt: _customLaunchAt,\n"
    "              address:",
    "              launchMode: _launchMode,\n"
    "              customLaunchAt: _customLaunchAt,\n"
    "              meetingAt: _meetingAt,\n"
    "              address:",
)
replace_once(
    p,
    "              launchMode: _launchMode,\n"
    "              customLaunchAt: _customLaunchAt,\n"
    "              squadSizeLimit:",
    "              launchMode: _launchMode,\n"
    "              customLaunchAt: _customLaunchAt,\n"
    "              meetingAt: _meetingAt,\n"
    "              squadSizeLimit:",
)

# Secondary add/edit match form.
p = "lib/features/matches/presentation/match_form_page.dart"
replace_once(
    p,
    "import 'package:as_grinta/features/matches/domain/match_model.dart';\n",
    "import 'package:as_grinta/features/matches/domain/match_model.dart';\n"
    "import 'package:as_grinta/features/matches/domain/match_meeting.dart';\n",
)
replace_once(
    p,
    "import 'package:as_grinta/features/matches/presentation/widgets/convocation_launch_picker.dart';\n",
    "import 'package:as_grinta/features/matches/presentation/widgets/convocation_launch_picker.dart';\n"
    "import 'package:as_grinta/features/matches/presentation/widgets/match_meeting_time_picker.dart';\n",
)
replace_once(
    p,
    "  ConvocationLaunchMode _launchMode = ConvocationLaunchMode.automatic;\n"
    "  DateTime? _customLaunchAt;\n",
    "  ConvocationLaunchMode _launchMode = ConvocationLaunchMode.automatic;\n"
    "  DateTime? _customLaunchAt;\n"
    "  DateTime? _meetingAt;\n",
)
replace_once(
    p,
    "    _addressController.text = match?.address ?? '';\n"
    "    _selectedJersey",
    "    _addressController.text = match?.address ?? '';\n"
    "    _meetingAt = match?.meetingAt;\n"
    "    _selectedJersey",
)
replace_once(
    p,
    "              ListTile(\n"
    "                contentPadding: EdgeInsets.zero,\n"
    "                title: const Text('Heure'),\n"
    "                subtitle: Text(_formatTime(_kickoffAt)),\n"
    "                trailing: const Icon(Icons.schedule),\n"
    "                onTap: busy ? null : _pickTime,\n"
    "              ),\n"
    "              if (widget.match == null) ...[",
    "              ListTile(\n"
    "                contentPadding: EdgeInsets.zero,\n"
    "                title: const Text('Heure'),\n"
    "                subtitle: Text(_formatTime(_kickoffAt)),\n"
    "                trailing: const Icon(Icons.schedule),\n"
    "                onTap: busy ? null : _pickTime,\n"
    "              ),\n"
    "              MatchMeetingTimePicker(\n"
    "                kickoffAt: _kickoffAt,\n"
    "                customMeetingAt: _meetingAt,\n"
    "                enabled: !busy,\n"
    "                onChanged: (value) => setState(() => _meetingAt = value),\n"
    "              ),\n"
    "              if (widget.match == null) ...[",
)
text = Path(p).read_text()
old = "      _repairCustomLaunchIfNeeded();\n    });"
if text.count(old) != 2:
    raise RuntimeError(f"{p}: expected two kickoff repair blocks, found {text.count(old)}")
Path(p).write_text(
    text.replace(
        old,
        "      _repairCustomLaunchIfNeeded();\n      _repairMeetingAt();\n    });",
    )
)
replace_once(
    p,
    "  void _repairCustomLaunchIfNeeded() {",
    "  void _repairMeetingAt() {\n"
    "    _meetingAt = preserveCustomMeetingTime(\n"
    "      kickoffAt: _kickoffAt,\n"
    "      customMeetingAt: _meetingAt,\n"
    "    );\n"
    "  }\n\n"
    "  void _repairCustomLaunchIfNeeded() {",
)
replace_once(
    p,
    "        address: address.isEmpty ? null : address,\n"
    "        rememberAddressAsDefault: _rememberAddressAsDefault,",
    "        address: address.isEmpty ? null : address,\n"
    "        rememberAddressAsDefault: _rememberAddressAsDefault,\n"
    "        meetingAt: _meetingAt,",
)
replace_once(
    p,
    "      matchType: _matchType,\n"
    "      jerseyNote: _selectedJersey?.id,\n"
    "    );",
    "      matchType: _matchType,\n"
    "      jerseyNote: _selectedJersey?.id,\n"
    "      meetingAt: _meetingAt,\n"
    "    );",
)
replace_once(
    p,
    "          launchMode: _launchMode,\n"
    "          customLaunchAt: _customLaunchAt,\n"
    "          address: address.isEmpty ? null : address,",
    "          launchMode: _launchMode,\n"
    "          customLaunchAt: _customLaunchAt,\n"
    "          meetingAt: _meetingAt,\n"
    "          address: address.isEmpty ? null : address,",
)
replace_once(
    p,
    "          launchMode: _launchMode,\n"
    "          customLaunchAt: _customLaunchAt,\n"
    "          squadSizeLimit:",
    "          launchMode: _launchMode,\n"
    "          customLaunchAt: _customLaunchAt,\n"
    "          meetingAt: _meetingAt,\n"
    "          squadSizeLimit:",
)
