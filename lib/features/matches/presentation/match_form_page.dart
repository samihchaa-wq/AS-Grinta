import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/data/scheduled_match_creation_repository.dart';
import 'package:as_grinta/features/matches/domain/convocation_launch.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/domain/match_meeting.dart';
import 'package:as_grinta/features/matches/presentation/calendar_entry_form_page.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_form_section.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_meeting_time_picker.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_wheel_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MatchFormPage extends ConsumerStatefulWidget {
  const MatchFormPage({super.key, this.match});

  final MatchModel? match;

  @override
  ConsumerState<MatchFormPage> createState() => _MatchFormPageState();
}

class _MatchFormPageState extends ConsumerState<MatchFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _squadSizeController = TextEditingController(text: '14');
  final _addressController = TextEditingController();
  JerseyOption? _selectedJersey;

  double? _oddsWin;
  double? _oddsDraw;
  double? _oddsLoss;

  late String _seasonId;
  late String _opponentId;
  late DateTime _kickoffAt;
  late bool _isHome;
  late String _matchType;
  late bool _isInternal;

  bool _suggestingOdds = false;
  bool _squadDefaultApplied = false;
  bool _squadLimitLoading = false;
  bool _squadLimitLoaded = false;
  bool _rememberAddressAsDefault = true;
  bool _saving = false;
  final ConvocationLaunchMode _launchMode = ConvocationLaunchMode.automatic;
  DateTime? _customLaunchAt;
  DateTime? _meetingAt;

  int _oddsRequestToken = 0;
  String? _clubHomeAddress;

  Future<void> _suggestOdds() async {
    final token = ++_oddsRequestToken;
    if (_opponentId.isEmpty) {
      setState(() {
        _oddsWin = null;
        _oddsDraw = null;
        _oddsLoss = null;
      });
      return;
    }

    setState(() {
      _suggestingOdds = true;
      _oddsWin = null;
      _oddsDraw = null;
      _oddsLoss = null;
    });
    final odds = await ref.read(matchesRepositoryProvider).previewMatchOdds(
          opponentId: _opponentId,
          isHome: _isHome,
          referenceDate: _kickoffAt,
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

  @override
  void initState() {
    super.initState();
    final match = widget.match;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _seasonId = match?.seasonId ?? '';
    _opponentId = match?.opponentId ?? '';
    _kickoffAt = match?.kickoffAt ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 21);
    _isHome = match?.isHome ?? true;
    _matchType = match?.matchType ?? 'championnat';
    _isInternal = match?.isInternal ?? false;
    if (_isInternal) _isHome = true;
    _oddsWin = match?.oddsWin;
    _oddsDraw = match?.oddsDraw;
    _oddsLoss = match?.oddsLoss;
    _addressController.text = match?.address ?? '';
    _meetingAt = match?.meetingAt;
    _selectedJersey = JerseyOption.fromId(match?.jerseyNote);

    Future.microtask(() async {
      final home =
          await ref.read(matchesRepositoryProvider).fetchClubHomeAddress();
      if (!mounted) return;
      setState(() => _clubHomeAddress = home);
      _prefillAddress();
    });
  }

  @override
  void dispose() {
    _squadSizeController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _prefillAddress() {
    if (_addressController.text.trim().isNotEmpty) return;
    _applyRememberedAddress();
  }

  void _refreshAddressForSelection() => _applyRememberedAddress();

  void _applyRememberedAddress() {
    String? remembered;
    if (_isHome) {
      remembered = _clubHomeAddress;
    } else if (_opponentId.isNotEmpty) {
      final opponent = ref.read(matchesControllerProvider).opponents.firstWhere(
            (item) => item['id'].toString() == _opponentId,
            orElse: () => const <String, dynamic>{},
          );
      remembered = opponent['address']?.toString().trim();
    }
    _addressController.text = remembered ?? '';
  }

  Future<void> _loadSquadLimit() async {
    final match = widget.match;
    if (match == null || _squadLimitLoading || _squadLimitLoaded) return;
    setState(() => _squadLimitLoading = true);
    try {
      final limit = await ref
          .read(matchesRepositoryProvider)
          .fetchSportSquadLimit(match.id);
      if (!mounted) return;
      _squadSizeController.text = limit.toString();
      _squadLimitLoaded = true;
    } finally {
      if (mounted) setState(() => _squadLimitLoading = false);
    }
  }

  void _changeMatchKind(String? value) {
    if (value == null) return;
    if (widget.match?.isInternal ?? false) return;

    setState(() {
      if (value == 'entre_nous') {
        _isInternal = true;
        _matchType = 'entre_nous';
        _opponentId = '';
        _isHome = true;
        _oddsWin = null;
        _oddsDraw = null;
        _oddsLoss = null;
        _refreshAddressForSelection();
      } else {
        _isInternal = false;
        _matchType = value;
        _refreshAddressForSelection();
      }
    });

    if (!_isInternal && _opponentId.isNotEmpty) {
      _suggestOdds();
    }
  }

  void _changeVenue(bool isHome) {
    if (_isHome == isHome) return;
    setState(() {
      _isHome = isHome;
      _refreshAddressForSelection();
    });
    _suggestOdds();
  }

  @override
  Widget build(BuildContext context) {
    // All creation entry points now share the richer four-choice form so
    // Championnat / Amical / Match entre nous / Événement stay consistent.
    if (widget.match == null) return const CalendarEntryFormPage();

    final state = ref.watch(matchesControllerProvider);
    final role = ref.watch(authControllerProvider).profile?.role;
    final canManage = role?.isAdmin ?? false;
    final sportsEnabled = ref.watch(sportsManagementEnabledProvider);
    final feature =
        ref.watch(featureFlagsControllerProvider).valueOrNull?.sportsManagement;
    final openSeasons = state.seasons
        .where((season) => season['status']?.toString() == 'open')
        .toList(growable: false);
    final opponents = [...state.opponents]
      ..sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));

    if (_seasonId.isEmpty && openSeasons.isNotEmpty) {
      _seasonId = openSeasons.first['id'].toString();
    }
    if (sportsEnabled && !_squadDefaultApplied) {
      _squadDefaultApplied = true;
      if (widget.match == null) {
        _squadSizeController.text = (feature?.usualSquadSize ?? 14).toString();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadSquadLimit());
      }
    }

    final busy = state.isLoading || _squadLimitLoading || _saving;

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Modifier'), admin: true),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            MatchFormSection(
              title: 'Match',
              subtitle: 'Type, adversaire, terrain et maillot',
              icon: Icons.sports_soccer_rounded,
              children: [
                if (_isInternal)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.groups_outlined),
                    title: Text('Match entre nous'),
                    subtitle: Text('Le type ne peut pas être changé.'),
                  )
                else ...[
                  Text(
                    'Type',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _CompactChoiceButton(
                          label: 'Championnat',
                          selected: _matchType == 'championnat',
                          enabled: !busy,
                          onPressed: () => _changeMatchKind('championnat'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CompactChoiceButton(
                          label: 'Amical',
                          selected: _matchType == 'amical',
                          enabled: !busy,
                          onPressed: () => _changeMatchKind('amical'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              _opponentId.isEmpty ? null : _opponentId,
                          decoration: const InputDecoration(
                            labelText: 'Adversaire',
                          ),
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
                          validator: (value) => value == null || value.isEmpty
                              ? 'Sélectionnez un adversaire'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: busy ? null : _createOpponent,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text(
                            'Ajouter un adversaire',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Lieu',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _CompactChoiceButton(
                          label: 'Domicile',
                          selected: _isHome,
                          enabled: !busy,
                          onPressed: () => _changeVenue(true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CompactChoiceButton(
                          label: 'Extérieur',
                          selected: !_isHome,
                          enabled: !busy,
                          onPressed: () => _changeVenue(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Maillot',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
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
                          onTap: busy
                              ? null
                              : () => setState(() {
                                    _selectedJersey = _selectedJersey == option
                                        ? null
                                        : option;
                                  }),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            MatchFormSection(
              title: 'Organisation',
              subtitle: 'Date, heure et rendez-vous',
              icon: Icons.schedule_rounded,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MatchFormPickerTile(
                        label: 'Date',
                        value: _formatDate(_kickoffAt),
                        icon: Icons.calendar_today_outlined,
                        enabled: !busy,
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MatchFormPickerTile(
                        label: 'Heure',
                        value: _formatTime(_kickoffAt),
                        icon: Icons.schedule_outlined,
                        enabled: !busy,
                        onTap: _pickTime,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                MatchMeetingTimePicker(
                  kickoffAt: _kickoffAt,
                  customMeetingAt: _meetingAt,
                  enabled: !busy,
                  onChanged: (value) => setState(() => _meetingAt = value),
                ),
              ],
            ),
            const SizedBox(height: 14),
            MatchFormSection(
              title: 'Logistique',
              subtitle: 'Adresse et effectif convoqué',
              icon: Icons.location_on_outlined,
              children: [
                TextFormField(
                  controller: _addressController,
                  enabled: !busy,
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.multiline,
                  minLines: 2,
                  maxLines: null,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Adresse (facultatif)',
                    hintText: 'Terrain, rue, ville…',
                    prefixIcon: Icon(Icons.place_outlined),
                    alignLabelWithHint: true,
                  ),
                ),
                if (!_isInternal) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _rememberAddressAsDefault,
                    onChanged: busy
                        ? null
                        : (value) => setState(
                              () => _rememberAddressAsDefault = value ?? false,
                            ),
                    title: const Text('Garder cette adresse pour cette équipe'),
                    subtitle: Text(
                      _isHome
                          ? 'Met à jour le terrain par défaut d’AS Grinta.'
                          : 'Met à jour le terrain par défaut de l’adversaire.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (sportsEnabled) ...[
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.groups_2_outlined),
                      title: const Text('Nombre de joueurs convoqués'),
                      subtitle: Text(
                        '${_squadSizeController.text} joueur${_squadSizeController.text == '1' ? '' : 's'}',
                      ),
                      trailing: _squadLimitLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: GrintaProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.unfold_more_rounded),
                      onTap: busy ? null : _pickSquadSize,
                    ),
                  ],
                ],
              ],
            ),
            if (!_isInternal) ...[
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.analytics_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cotes calculées',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
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
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: canManage && !busy ? _submit : null,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: GrintaProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Enregistrer'),
            ),
            if (canManage) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: busy ? null : _confirmDelete,
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Supprimer définitivement le match'),
              ),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 12),
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
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
    final trimmedName = name.trim();
    final alreadyExists = ref.read(matchesControllerProvider).opponents.any(
          (opponent) => opponent['name']?.toString() == trimmedName,
        );
    if (alreadyExists) {
      final createAnyway = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Adversaire déjà existant'),
              content: Text(
                'Une équipe nommée « $trimmedName » existe déjà. '
                'Tu peux quand même créer un nouvel adversaire avec exactement le même nom.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Créer quand même'),
                ),
              ],
            ),
          ) ??
          false;
      if (!createAnyway || !mounted) return;
    }
    final id = await ref
        .read(matchesControllerProvider.notifier)
        .createOpponent(trimmedName);
    if (!mounted || id == null) return;
    setState(() {
      _isInternal = false;
      if (_matchType == 'entre_nous') _matchType = 'championnat';
      _opponentId = id;
    });
    await _suggestOdds();
  }

  Future<void> _confirmDelete() async {
    final match = widget.match;
    if (match == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Supprimer ce match ?'),
            content: const Text(
              'Cette action supprime aussi ses cotes et ses pronostics. Elle est irréversible.',
            ),
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
    if (!confirmed) return;
    await ref.read(matchesControllerProvider.notifier).deleteMatch(match.id);
    if (!mounted) return;
    if (ref.read(matchesControllerProvider).error == null) {
      Navigator.pop(context);
    }
  }

  Future<void> _pickDate() async {
    final previousKickoff = _kickoffAt;
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDate = DateUtils.dateOnly(_kickoffAt).isBefore(today)
        ? DateUtils.dateOnly(_kickoffAt)
        : today;
    final date = await MatchWheelPicker.pickDate(
      context: context,
      initialDate: _kickoffAt,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _kickoffAt = DateTime(
        date.year,
        date.month,
        date.day,
        _kickoffAt.hour,
        _kickoffAt.minute,
      );
      _repairCustomLaunchIfNeeded();
      _repairMeetingAt(previousKickoffAt: previousKickoff);
    });
    if (!_isInternal && _opponentId.isNotEmpty) {
      await _suggestOdds();
    }
  }

  Future<void> _pickTime() async {
    final previousKickoff = _kickoffAt;
    final time = await MatchWheelPicker.pickTime(
      context: context,
      initialDateTime: _kickoffAt,
    );
    if (time == null || !mounted) return;
    setState(() {
      _kickoffAt = DateTime(
        _kickoffAt.year,
        _kickoffAt.month,
        _kickoffAt.day,
        time.hour,
        time.minute,
      );
      _repairCustomLaunchIfNeeded();
      _repairMeetingAt(previousKickoffAt: previousKickoff);
    });
  }

  Future<void> _pickSquadSize() async {
    final current = int.tryParse(_squadSizeController.text.trim()) ?? 14;
    final value = await MatchWheelPicker.pickInt(
      context: context,
      initialValue: current,
      minValue: 1,
      maxValue: 30,
      title: 'Nombre de joueurs convoqués',
      labelBuilder: (number) => '$number joueur${number == 1 ? '' : 's'}',
    );
    if (value == null || !mounted) return;
    setState(() => _squadSizeController.text = value.toString());
  }

  void _repairMeetingAt({required DateTime previousKickoffAt}) {
    _meetingAt = preserveCustomMeetingTime(
      previousKickoffAt: previousKickoffAt,
      kickoffAt: _kickoffAt,
      customMeetingAt: _meetingAt,
    );
  }

  void _repairCustomLaunchIfNeeded() {
    if (_launchMode != ConvocationLaunchMode.custom ||
        _customLaunchAt == null ||
        _customLaunchAt!.isBefore(_kickoffAt)) {
      return;
    }
    _customLaunchAt = suggestedCustomConvocationLaunchAt(kickoffAt: _kickoffAt);
  }

  Future<void> _submit() async {
    if (_seasonId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune saison ouverte disponible.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final pastError = pastKickoffError(_kickoffAt);
    if (pastError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(pastError)));
      return;
    }

    final meetingError = validateCustomMeetingAt(
      kickoffAt: _kickoffAt,
      customMeetingAt: _meetingAt,
    );
    if (meetingError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(meetingError)));
      return;
    }

    if (widget.match == null) {
      final launchError = validateConvocationLaunch(
        mode: _launchMode,
        kickoffAt: _kickoffAt,
        customAt: _customLaunchAt,
      );
      if (launchError != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(launchError)));
        return;
      }
    }

    final notifier = ref.read(matchesControllerProvider.notifier);
    final address = _addressController.text.trim();

    if (widget.match == null) {
      await _createScheduledMatch(address: address);
      return;
    }

    if (_isInternal) {
      await notifier.updateInternalMatch(
        id: widget.match!.id,
        seasonId: _seasonId,
        kickoffAt: _kickoffAt,
        expectedUpdatedAt: widget.match!.updatedAt,
        address: address.isEmpty ? null : address,
        rememberAddressAsDefault: _rememberAddressAsDefault,
        meetingAt: _meetingAt,
      );
      if (!mounted) return;
      if (ref.read(matchesControllerProvider).error == null) {
        Navigator.pop(context);
      }
      return;
    }

    final oddsWin = _oddsWin;
    final oddsDraw = _oddsDraw;
    final oddsLoss = _oddsLoss;
    if (oddsWin == null || oddsDraw == null || oddsLoss == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionne un adversaire pour calculer les cotes.'),
        ),
      );
      return;
    }

    final sportsEnabled = ref.read(sportsManagementEnabledProvider);
    final squadSizeLimit =
        sportsEnabled ? int.parse(_squadSizeController.text.trim()) : null;
    await notifier.updateMatch(
      id: widget.match!.id,
      seasonId: _seasonId,
      opponentId: _opponentId,
      kickoffAt: _kickoffAt,
      isHome: _isHome,
      status: widget.match!.status,
      oddsWin: oddsWin,
      oddsDraw: oddsDraw,
      oddsLoss: oddsLoss,
      expectedUpdatedAt: widget.match!.updatedAt,
      squadSizeLimit: squadSizeLimit,
      address: address.isEmpty ? null : address,
      rememberAddressAsDefault: _rememberAddressAsDefault,
      matchType: _matchType,
      jerseyNote: _selectedJersey?.id,
      meetingAt: _meetingAt,
    );
    if (!mounted) return;
    if (ref.read(matchesControllerProvider).error == null) {
      Navigator.pop(context);
    }
  }

  Future<void> _createScheduledMatch({required String address}) async {
    setState(() => _saving = true);
    try {
      final repository = ref.read(scheduledMatchCreationRepositoryProvider);
      if (_isInternal) {
        await repository.createInternalMatch(
          seasonId: _seasonId,
          kickoffAt: _kickoffAt,
          launchMode: _launchMode,
          customLaunchAt: _customLaunchAt,
          meetingAt: _meetingAt,
          address: address.isEmpty ? null : address,
        );
      } else {
        final oddsWin = _oddsWin;
        final oddsDraw = _oddsDraw;
        final oddsLoss = _oddsLoss;
        if (oddsWin == null || oddsDraw == null || oddsLoss == null) {
          throw StateError(
            'Sélectionne un adversaire pour calculer les cotes.',
          );
        }
        final sportsEnabled = ref.read(sportsManagementEnabledProvider);
        final squadSizeLimit =
            sportsEnabled ? int.parse(_squadSizeController.text.trim()) : null;
        await repository.createMatch(
          seasonId: _seasonId,
          opponentId: _opponentId,
          kickoffAt: _kickoffAt,
          isHome: _isHome,
          oddsWin: oddsWin,
          oddsDraw: oddsDraw,
          oddsLoss: oddsLoss,
          launchMode: _launchMode,
          customLaunchAt: _customLaunchAt,
          meetingAt: _meetingAt,
          squadSizeLimit: squadSizeLimit,
          address: address.isEmpty ? null : address,
          rememberAddressAsDefault: _rememberAddressAsDefault,
          matchType: _matchType,
          jerseyNote: _selectedJersey?.id,
        );
      }
      await ref
          .read(matchesControllerProvider.notifier)
          .load(allSeasons: true, forceRefresh: true);
      if (!mounted) return;
      Navigator.pop(context);
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

class _CompactChoiceButton extends StatelessWidget {
  const _CompactChoiceButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size.fromHeight(48)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    final child = Text(label, textAlign: TextAlign.center, maxLines: 2);
    if (selected) {
      return FilledButton(
        style: style,
        onPressed: enabled ? onPressed : null,
        child: child,
      );
    }
    return OutlinedButton(
      style: style,
      onPressed: enabled ? onPressed : null,
      child: child,
    );
  }
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
  final VoidCallback? onTap;

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
