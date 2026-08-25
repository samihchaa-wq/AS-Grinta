import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/club_events_repository.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/data/scheduled_match_creation_repository.dart';
import 'package:as_grinta/features/matches/domain/club_event.dart';
import 'package:as_grinta/features/matches/domain/convocation_launch.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/matches/domain/match_meeting.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/matches/presentation/widgets/convocation_launch_picker.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_meeting_time_picker.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_option_button.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_wheel_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _CalendarEntryKind { championnat, amical, internal, event }

class CalendarEntryFormPage extends ConsumerStatefulWidget {
  const CalendarEntryFormPage({super.key, this.event});

  final ClubEvent? event;

  @override
  ConsumerState<CalendarEntryFormPage> createState() =>
      _CalendarEntryFormPageState();
}

class _CalendarEntryFormPageState extends ConsumerState<CalendarEntryFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _eventTitleController = TextEditingController();
  final _addressController = TextEditingController();
  final _squadSizeController = TextEditingController(text: '14');

  late _CalendarEntryKind _kind;
  late DateTime _startsAt;
  String _seasonId = '';
  String _opponentId = '';
  bool _isHome = true;
  bool _rememberAddressAsDefault = true;
  bool _saving = false;
  bool _suggestingOdds = false;
  bool _squadDefaultApplied = false;
  String? _clubHomeAddress;
  JerseyOption? _selectedJersey;
  double? _oddsWin;
  double? _oddsDraw;
  double? _oddsLoss;
  int _oddsRequestToken = 0;

  ConvocationLaunchMode _launchMode = ConvocationLaunchMode.automatic;
  DateTime? _customLaunchAt;
  DateTime? _meetingAt;

  bool get _isEvent => _kind == _CalendarEntryKind.event;
  bool get _isInternal => _kind == _CalendarEntryKind.internal;
  bool get _isNormalMatch => !_isEvent && !_isInternal;
  String get _matchType =>
      _kind == _CalendarEntryKind.amical ? 'amical' : 'championnat';

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _kind = event == null
        ? _CalendarEntryKind.championnat
        : _CalendarEntryKind.event;
    _startsAt =
        event?.startsAt ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 21);
    _seasonId = event?.seasonId ?? '';
    _eventTitleController.text = event?.title ?? '';
    _addressController.text = event?.location ?? '';

    Future.microtask(() async {
      final controller = ref.read(matchesControllerProvider.notifier);
      if (ref.read(matchesControllerProvider).seasons.isEmpty) {
        await controller.load(allSeasons: true);
      }
      if (!mounted) return;
      final home = await ref
          .read(matchesRepositoryProvider)
          .fetchClubHomeAddress();
      if (!mounted) return;
      setState(() => _clubHomeAddress = home);
      if (widget.event == null && !_isEvent) _prefillAddress();
    });
  }

  @override
  void dispose() {
    _eventTitleController.dispose();
    _addressController.dispose();
    _squadSizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final isAdmin = ref.watch(isAdminViewProvider);
    final sportsEnabled = ref.watch(sportsManagementEnabledProvider);
    final feature = ref
        .watch(featureFlagsControllerProvider)
        .valueOrNull
        ?.sportsManagement;
    final seasons = widget.event == null
        ? state.seasons
              .where((season) => season['status']?.toString() == 'open')
              .toList(growable: false)
        : state.seasons;
    final opponents = [...state.opponents]
      ..sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));

    if (_seasonId.isEmpty && seasons.isNotEmpty) {
      _seasonId = seasons.first['id'].toString();
    }
    if (sportsEnabled && !_squadDefaultApplied) {
      _squadDefaultApplied = true;
      _squadSizeController.text = (feature?.usualSquadSize ?? 14).toString();
    }

    final busy = _saving || state.isLoading;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GrintaAppBar(
        title: Text(widget.event == null ? 'Ajouter' : 'Modifier l’événement'),
        admin: true,
        actions: [
          if (widget.event != null && isAdmin)
            IconButton(
              tooltip: 'Supprimer l’événement',
              onPressed: busy ? null : _confirmDeleteEvent,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (widget.event == null) ...[
                _typeSelector(busy: busy),
                const SizedBox(height: 14),
              ] else ...[
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.event_rounded),
                  title: Text('Événement'),
                  subtitle: Text(
                    'Rendez-vous du club, indépendant des matchs.',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _seasonId.isEmpty ? null : _seasonId,
                  decoration: const InputDecoration(labelText: 'Saison'),
                  items: seasons
                      .map(
                        (season) => DropdownMenuItem<String>(
                          value: season['id'].toString(),
                          child: Text(season['name'].toString()),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: busy
                      ? null
                      : (value) => setState(() => _seasonId = value ?? ''),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Sélectionnez une saison'
                      : null,
                ),
                const SizedBox(height: 18),
              ],
              if (_isEvent)
                ..._buildEventFields()
              else
                ..._buildMatchFields(
                  opponents: opponents,
                  sportsEnabled: sportsEnabled,
                  busy: busy,
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: isAdmin && !busy ? _submit : null,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: GrintaProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(widget.event == null ? 'Ajouter' : 'Enregistrer'),
              ),
              if (widget.event != null && isAdmin) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: busy ? null : _confirmDeleteEvent,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Supprimer définitivement l’événement'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildEventFields() {
    return [
      TextFormField(
        controller: _eventTitleController,
        autofocus: widget.event == null,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 120,
        decoration: const InputDecoration(
          labelText: 'Nom de l’événement',
          hintText: 'Ex. Soirée du club, repas, réunion…',
          prefixIcon: Icon(Icons.edit_calendar_outlined),
        ),
        validator: (raw) {
          final value = raw?.trim() ?? '';
          if (value.isEmpty) return 'Écris le nom de l’événement';
          if (value.length > 120) return '120 caractères maximum';
          return null;
        },
      ),
      const SizedBox(height: 8),
      _dateTimeFields(),
      const SizedBox(height: 12),
      TextFormField(
        controller: _addressController,
        textCapitalization: TextCapitalization.words,
        keyboardType: TextInputType.streetAddress,
        minLines: 2,
        maxLines: null,
        maxLength: 300,
        decoration: const InputDecoration(
          labelText: 'Lieu de rendez-vous',
          hintText: 'Terrain, adresse, salle, restaurant…',
          prefixIcon: Icon(Icons.place_outlined),
        ),
        validator: (raw) {
          final value = raw?.trim() ?? '';
          if (value.isEmpty) return 'Indique le lieu de rendez-vous';
          if (value.length > 300) return '300 caractères maximum';
          return null;
        },
      ),
      const SizedBox(height: 4),
      const Text(
        'Un événement est uniquement un rendez-vous dans le calendrier : aucun prono, effectif, composition, live ou statistique ne sera créé.',
      ),
    ];
  }

  List<Widget> _buildMatchFields({
    required List<Map<String, dynamic>> opponents,
    required bool sportsEnabled,
    required bool busy,
  }) {
    return [
      if (_isInternal)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.groups_outlined),
          title: Text('Match entre nous'),
          subtitle: Text('Sans adversaire et sans cotes.'),
        )
      else
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _opponentId.isEmpty ? null : _opponentId,
                decoration: const InputDecoration(labelText: 'Adversaire'),
                items: opponents
                    .map(
                      (opponent) => DropdownMenuItem<String>(
                        value: opponent['id'].toString(),
                        child: Text(opponent['name'].toString()),
                      ),
                    )
                    .toList(growable: false),
                onChanged: busy
                    ? null
                    : (value) {
                        setState(() {
                          _opponentId = value ?? '';
                          _refreshAddressForSelection();
                        });
                        _suggestOdds();
                      },
                validator: (value) =>
                    _isNormalMatch && (value == null || value.isEmpty)
                    ? 'Sélectionnez un adversaire'
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Ajouter un adversaire',
              onPressed: busy ? null : _createOpponent,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      if (_isNormalMatch) ...[
        const SizedBox(height: 12),
        _locationSelector(busy: busy),
      ],
      const SizedBox(height: 12),
      _dateTimeFields(enabled: !busy),
      const SizedBox(height: 12),
      MatchMeetingTimePicker(
        kickoffAt: _startsAt,
        customMeetingAt: _meetingAt,
        enabled: !busy,
        onChanged: (value) => setState(() => _meetingAt = value),
      ),
      if (widget.event == null) ...[
        const SizedBox(height: 18),
        ConvocationLaunchPicker(
          kickoffAt: _startsAt,
          mode: _launchMode,
          customAt: _customLaunchAt,
          enabled: !busy,
          onModeChanged: (mode) => setState(() => _launchMode = mode),
          onCustomAtChanged: (value) => setState(() => _customLaunchAt = value),
        ),
      ],
      const SizedBox(height: 12),
      TextFormField(
        controller: _addressController,
        textCapitalization: TextCapitalization.words,
        keyboardType: TextInputType.streetAddress,
        minLines: 2,
        maxLines: null,
        maxLength: 300,
        decoration: const InputDecoration(
          labelText: 'Adresse (facultatif)',
          hintText: 'Terrain, rue, ville…',
          prefixIcon: Icon(Icons.place_outlined),
        ),
      ),
      if (_isNormalMatch) ...[
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _rememberAddressAsDefault,
          onChanged: busy
              ? null
              : (value) =>
                    setState(() => _rememberAddressAsDefault = value ?? false),
          title: const Text('Garder cette adresse pour cette équipe'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 16),
        Text(
          'Maillot',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final option in JerseyOption.values)
              _JerseyOptionTile(
                option: option,
                selected: _selectedJersey == option,
                onTap: () => setState(() {
                  _selectedJersey = _selectedJersey == option ? null : option;
                }),
              ),
          ],
        ),
        if (sportsEnabled) ...[
          const SizedBox(height: 12),
          MatchValueButton(
            label: 'Nombre de joueurs convoqués',
            value: _squadSizeController.text,
            icon: Icons.groups_outlined,
            onPressed: busy ? null : _pickSquadSize,
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Text('Cotes', style: Theme.of(context).textTheme.titleMedium),
            if (_suggestingOdds) ...[
              const Spacer(),
              const SizedBox(
                width: 18,
                height: 18,
                child: GrintaProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _OddsDisplay(label: 'Victoire', value: _oddsWin),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OddsDisplay(label: 'Nul', value: _oddsDraw),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OddsDisplay(label: 'Défaite', value: _oddsLoss),
            ),
          ],
        ),
      ],
    ];
  }

  Widget _typeSelector({required bool busy}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Type',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: MatchOptionButton(
                label: 'Championnat',
                selected: _kind == _CalendarEntryKind.championnat,
                onPressed: busy
                    ? null
                    : () => _changeKind(_CalendarEntryKind.championnat),
                height: 50,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MatchOptionButton(
                label: 'Amical',
                selected: _kind == _CalendarEntryKind.amical,
                onPressed: busy
                    ? null
                    : () => _changeKind(_CalendarEntryKind.amical),
                height: 50,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: MatchOptionButton(
                label: 'Match entre nous',
                selected: _kind == _CalendarEntryKind.internal,
                onPressed: busy
                    ? null
                    : () => _changeKind(_CalendarEntryKind.internal),
                height: 50,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MatchOptionButton(
                label: 'Événement',
                selected: _kind == _CalendarEntryKind.event,
                onPressed: busy
                    ? null
                    : () => _changeKind(_CalendarEntryKind.event),
                height: 50,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _locationSelector({required bool busy}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Lieu',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: MatchOptionButton(
                label: 'Domicile',
                selected: _isHome,
                onPressed: busy ? null : () => _setLocation(true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MatchOptionButton(
                label: 'Extérieur',
                selected: !_isHome,
                onPressed: busy ? null : () => _setLocation(false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _setLocation(bool isHome) {
    if (_isHome == isHome) return;
    setState(() {
      _isHome = isHome;
      _refreshAddressForSelection();
    });
    _suggestOdds();
  }

  Widget _dateTimeFields({bool enabled = true}) {
    return Row(
      children: [
        Expanded(
          child: MatchValueButton(
            label: 'Date',
            value: _formatDate(_startsAt),
            icon: Icons.calendar_today_outlined,
            onPressed: enabled ? _pickDate : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MatchValueButton(
            label: 'Heure',
            value: _formatTime(_startsAt),
            icon: Icons.schedule_outlined,
            onPressed: enabled ? _pickTime : null,
          ),
        ),
      ],
    );
  }

  void _changeKind(_CalendarEntryKind? kind) {
    if (kind == null || kind == _kind) return;
    setState(() {
      _kind = kind;
      _rememberAddressAsDefault = false;
      if (_isInternal) {
        _opponentId = '';
        _isHome = true;
        _oddsWin = null;
        _oddsDraw = null;
        _oddsLoss = null;
      }
      if (_isEvent) {
        _addressController.clear();
        _meetingAt = null;
      } else {
        _applyRememberedAddress();
      }
    });
    if (_isNormalMatch && _opponentId.isNotEmpty) _suggestOdds();
  }

  Future<void> _suggestOdds() async {
    final token = ++_oddsRequestToken;
    if (!_isNormalMatch || _opponentId.isEmpty) {
      if (mounted) {
        setState(() {
          _oddsWin = null;
          _oddsDraw = null;
          _oddsLoss = null;
        });
      }
      return;
    }
    setState(() {
      _suggestingOdds = true;
      _oddsWin = null;
      _oddsDraw = null;
      _oddsLoss = null;
    });
    final odds = await ref
        .read(matchesRepositoryProvider)
        .previewMatchOdds(
          opponentId: _opponentId,
          isHome: _isHome,
          referenceDate: _startsAt,
        );
    if (!mounted || token != _oddsRequestToken) return;
    setState(() {
      _suggestingOdds = false;
      if (odds != null) {
        _oddsWin = odds.win;
        _oddsDraw = odds.draw;
        _oddsLoss = odds.loss;
      }
    });
  }

  void _prefillAddress() {
    if (_addressController.text.trim().isNotEmpty) return;
    _applyRememberedAddress();
  }

  void _refreshAddressForSelection() => _applyRememberedAddress();

  void _applyRememberedAddress() {
    if (_isEvent) return;
    String? remembered;
    if (_isHome) {
      remembered = _clubHomeAddress;
    } else if (_opponentId.isNotEmpty) {
      final opponent = ref
          .read(matchesControllerProvider)
          .opponents
          .firstWhere(
            (item) => item['id'].toString() == _opponentId,
            orElse: () => const <String, dynamic>{},
          );
      remembered = opponent['address']?.toString().trim();
    }
    _addressController.text = remembered ?? '';
  }

  Future<void> _createOpponent() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvel adversaire'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final id = await ref
        .read(matchesControllerProvider.notifier)
        .createOpponent(name.trim());
    if (!mounted || id == null) return;
    setState(() {
      _opponentId = id;
      _refreshAddressForSelection();
    });
    await _suggestOdds();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final previousStartsAt = _startsAt;
    final date = await showMatchDateWheelPicker(
      context: context,
      initialValue: _startsAt,
      minimumDate: widget.event == null
          ? today
          : DateUtils.dateOnly(_startsAt).isBefore(today)
          ? DateUtils.dateOnly(_startsAt)
          : today,
      maximumDate: DateTime.now().add(const Duration(days: 3650)),
      title: 'Date du match',
    );
    if (date == null) return;
    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        _startsAt.hour,
        _startsAt.minute,
      );
      _repairCustomLaunchIfNeeded();
      _repairMeetingAt(previousKickoffAt: previousStartsAt);
    });
    if (_isNormalMatch && _opponentId.isNotEmpty) {
      await _suggestOdds();
    }
  }

  Future<void> _pickTime() async {
    final previousStartsAt = _startsAt;
    final time = await showMatchTimeWheelPicker(
      context: context,
      initialValue: _startsAt,
      title: 'Heure du match',
    );
    if (time == null) return;
    setState(() {
      _startsAt = DateTime(
        _startsAt.year,
        _startsAt.month,
        _startsAt.day,
        time.hour,
        time.minute,
      );
      _repairCustomLaunchIfNeeded();
      _repairMeetingAt(previousKickoffAt: previousStartsAt);
    });
  }

  Future<void> _pickSquadSize() async {
    final current = int.tryParse(_squadSizeController.text.trim()) ?? 14;
    final picked = await showMatchNumberWheelPicker(
      context: context,
      initialValue: current,
      minimumValue: 1,
      maximumValue: 30,
      title: 'Nombre de joueurs convoqués',
    );
    if (picked == null || !mounted) return;
    setState(() => _squadSizeController.text = '$picked');
  }

  void _repairMeetingAt({DateTime? previousKickoffAt}) {
    _meetingAt = preserveCustomMeetingTime(
      kickoffAt: _startsAt,
      customMeetingAt: _meetingAt,
      previousKickoffAt: previousKickoffAt,
    );
  }

  void _repairCustomLaunchIfNeeded() {
    if (_launchMode != ConvocationLaunchMode.custom ||
        _customLaunchAt == null ||
        _customLaunchAt!.isBefore(_startsAt)) {
      return;
    }
    _customLaunchAt = suggestedCustomConvocationLaunchAt(kickoffAt: _startsAt);
  }

  Future<void> _submit() async {
    if (_seasonId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune saison ouverte disponible.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    if (widget.event == null) {
      final pastError = pastKickoffError(_startsAt);
      if (pastError != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(pastError)));
        return;
      }
      if (!_isEvent) {
        final launchError = validateConvocationLaunch(
          mode: _launchMode,
          kickoffAt: _startsAt,
          customAt: _customLaunchAt,
        );
        if (launchError != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(launchError)));
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      if (_isEvent) {
        final repository = ref.read(clubEventsRepositoryProvider);
        final title = _eventTitleController.text.trim();
        final location = _addressController.text.trim();
        final event = widget.event;
        if (event == null) {
          await repository.createEvent(
            seasonId: _seasonId,
            title: title,
            startsAt: _startsAt,
            location: location,
          );
        } else {
          await repository.updateEvent(
            id: event.id,
            seasonId: _seasonId,
            title: title,
            startsAt: _startsAt,
            location: location,
          );
        }
        ref.invalidate(clubEventsProvider);
      } else if (_isInternal) {
        await ref
            .read(scheduledMatchCreationRepositoryProvider)
            .createInternalMatch(
              seasonId: _seasonId,
              kickoffAt: _startsAt,
              launchMode: _launchMode,
              customLaunchAt: _customLaunchAt,
              meetingAt: _meetingAt,
              address: _addressController.text.trim().isEmpty
                  ? null
                  : _addressController.text.trim(),
            );
        await ref
            .read(matchesControllerProvider.notifier)
            .load(allSeasons: true, forceRefresh: true);
      } else {
        final win = _oddsWin;
        final draw = _oddsDraw;
        final loss = _oddsLoss;
        if (win == null || draw == null || loss == null) {
          throw StateError(
            'Sélectionne un adversaire pour calculer les cotes.',
          );
        }
        final sportsEnabled = ref.read(sportsManagementEnabledProvider);
        final squadSizeLimit = sportsEnabled
            ? int.parse(_squadSizeController.text.trim())
            : null;
        await ref
            .read(scheduledMatchCreationRepositoryProvider)
            .createMatch(
              seasonId: _seasonId,
              opponentId: _opponentId,
              kickoffAt: _startsAt,
              isHome: _isHome,
              oddsWin: win,
              oddsDraw: draw,
              oddsLoss: loss,
              launchMode: _launchMode,
              customLaunchAt: _customLaunchAt,
              meetingAt: _meetingAt,
              squadSizeLimit: squadSizeLimit,
              address: _addressController.text.trim().isEmpty
                  ? null
                  : _addressController.text.trim(),
              rememberAddressAsDefault: _rememberAddressAsDefault,
              matchType: _matchType,
              jerseyNote: _selectedJersey?.id,
            );
        await ref
            .read(matchesControllerProvider.notifier)
            .load(allSeasons: true, forceRefresh: true);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(humanizeError(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDeleteEvent() async {
    final event = widget.event;
    if (event == null) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Supprimer cet événement ?'),
            content: const Text('Cette action est irréversible.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(clubEventsRepositoryProvider).deleteEvent(event.id);
      ref.invalidate(clubEventsProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(humanizeError(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _OddsDisplay extends StatelessWidget {
  const _OddsDisplay({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            value == null ? '—' : AppFormats.odds(value!),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _JerseyOptionTile extends StatelessWidget {
  const _JerseyOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final JerseyOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 84,
        height: 96,
        child: Stack(
          children: [
            Center(
              child: Image.asset(
                option.assetPath,
                fit: BoxFit.contain,
                semanticLabel: 'Maillot ${option.label}',
                errorBuilder: (context, _, __) =>
                    _JerseyFallback(label: option.label, selected: selected),
              ),
            ),
            if (selected)
              Positioned(
                right: 0,
                top: 0,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _JerseyFallback extends StatelessWidget {
  const _JerseyFallback({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checkroom_rounded, color: colors.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
