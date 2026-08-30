import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/club_events_repository.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/data/scheduled_match_creation_repository.dart';
import 'package:as_grinta/features/matches/domain/championship_round.dart';
import 'package:as_grinta/features/matches/domain/club_event.dart';
import 'package:as_grinta/features/matches/domain/convocation_launch.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/matches/domain/match_meeting.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
import 'package:as_grinta/features/matches/presentation/widgets/championship_round_tile.dart';
import 'package:as_grinta/features/matches/presentation/widgets/convocation_launch_picker.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_form_section.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_meeting_time_picker.dart';
import 'package:as_grinta/features/matches/presentation/widgets/match_wheel_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _CalendarEntryKind { championnat, amical, internal, event }

String _normalizeOpponentSearch(String value) {
  var normalized = value.toLowerCase().trim();
  const replacements = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
  };
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int? _opponentMatchScore(String name, String query) {
  final normalizedName = _normalizeOpponentSearch(name);
  final normalizedQuery = _normalizeOpponentSearch(query);
  if (normalizedQuery.isEmpty) return 0;
  if (normalizedName == normalizedQuery) return 0;
  if (normalizedName.startsWith(normalizedQuery)) {
    return 10 + (normalizedName.length - normalizedQuery.length);
  }

  final words = normalizedName.split(' ');
  for (var index = 0; index < words.length; index++) {
    if (words[index].startsWith(normalizedQuery)) return 20 + index;
  }

  final containsAt = normalizedName.indexOf(normalizedQuery);
  if (containsAt >= 0) return 40 + containsAt;

  var queryIndex = 0;
  var gaps = 0;
  var previousMatch = -1;
  var nameIndex = 0;
  while (nameIndex < normalizedName.length &&
      queryIndex < normalizedQuery.length) {
    if (normalizedName[nameIndex] == normalizedQuery[queryIndex]) {
      if (previousMatch >= 0) gaps += nameIndex - previousMatch - 1;
      previousMatch = nameIndex;
      queryIndex += 1;
    }
    nameIndex += 1;
  }
  if (queryIndex == normalizedQuery.length) return 80 + gaps;
  return null;
}

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
  bool _squadDefaultApplied = false;
  bool _championshipRoundDefaultApplied = false;
  int? _championshipRound;
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
  bool get _isChampionship => _kind == _CalendarEntryKind.championnat;
  String get _matchType =>
      _kind == _CalendarEntryKind.amical ? 'amical' : 'championnat';

  Iterable<int?> _championshipRoundsOfSeason(List<MatchModel> matches) {
    return matches
        .where((match) =>
            match.seasonId == _seasonId && match.matchType == 'championnat')
        .map((match) => match.championshipRound);
  }

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _kind = event == null
        ? _CalendarEntryKind.championnat
        : _CalendarEntryKind.event;
    _startsAt = event?.startsAt ??
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
      final home =
          await ref.read(matchesRepositoryProvider).fetchClubHomeAddress();
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
    final feature =
        ref.watch(featureFlagsControllerProvider).valueOrNull?.sportsManagement;
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
    final seasonRounds =
        _championshipRoundsOfSeason(state.matches).toList(growable: false);
    if (!_championshipRoundDefaultApplied &&
        _seasonId.isNotEmpty &&
        !state.isLoading) {
      _championshipRoundDefaultApplied = true;
      _championshipRound = suggestedChampionshipRound(seasonRounds);
    }

    final busy = _saving || state.isLoading;

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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            if (widget.event == null && _isEvent) ...[
              _CriterionCard(
                lighter: false,
                child: _EntryKindPicker(
                  value: _kind,
                  enabled: !busy,
                  onChanged: _changeKind,
                ),
              ),
              const SizedBox(height: 18),
            ] else if (widget.event != null) ...[
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.event_rounded),
                title: Text('Événement'),
                subtitle: Text('Rendez-vous du club, indépendant des matchs.'),
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
              ..._buildEventFields(busy: busy)
            else
              ..._buildMatchFields(
                opponents: opponents,
                seasonRounds: seasonRounds,
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
    );
  }

  List<Widget> _buildEventFields({required bool busy}) {
    return [
      TextFormField(
        controller: _eventTitleController,
        enabled: !busy,
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
      _dateTile(busy: busy),
      _timeTile(busy: busy),
      const SizedBox(height: 12),
      TextFormField(
        controller: _addressController,
        enabled: !busy,
        textCapitalization: TextCapitalization.words,
        keyboardType: TextInputType.multiline,
        minLines: 2,
        maxLines: null,
        maxLength: 300,
        decoration: const InputDecoration(
          labelText: 'Lieu de rendez-vous',
          hintText: 'Terrain, adresse, salle, restaurant…',
          prefixIcon: Icon(Icons.place_outlined),
          alignLabelWithHint: true,
        ),
        validator: (raw) {
          final value = raw?.trim() ?? '';
          if (value.isEmpty) return 'Indique le lieu de rendez-vous';
          if (value.length > 300) return '300 caractères maximum';
          return null;
        },
      ),
    ];
  }

  List<Widget> _buildMatchFields({
    required List<Map<String, dynamic>> opponents,
    required List<int?> seasonRounds,
    required bool sportsEnabled,
    required bool busy,
  }) {
    final fields = <Widget>[];
    var cardIndex = 0;
    var selectedOpponentName = '';
    if (_opponentId.isNotEmpty) {
      for (final opponent in opponents) {
        if (opponent['id'].toString() == _opponentId) {
          selectedOpponentName = opponent['name'].toString();
          break;
        }
      }
    }

    void addCard(Widget child) {
      if (fields.isNotEmpty) fields.add(const SizedBox(height: 10));
      fields.add(_CriterionCard(lighter: cardIndex.isOdd, child: child));
      cardIndex += 1;
    }

    if (widget.event == null) {
      addCard(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EntryKindPicker(
              value: _kind,
              enabled: !busy,
              onChanged: _changeKind,
            ),
            if (_isChampionship) ...[
              const SizedBox(height: 10),
              ChampionshipRoundTile(
                round: _championshipRound,
                roundsOfSeason: seasonRounds,
                enabled: !busy,
                onTap: _pickChampionshipRound,
              ),
            ],
          ],
        ),
      );
    }

    if (!_isInternal) {
      addCard(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Adversaire',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Autocomplete<Map<String, dynamic>>(
                    initialValue: TextEditingValue(text: selectedOpponentName),
                    displayStringForOption: (opponent) =>
                        opponent['name'].toString(),
                    optionsBuilder: (textEditingValue) {
                      final query = textEditingValue.text.trim();
                      if (query.isEmpty) return opponents.take(8);

                      final ranked = <MapEntry<int, Map<String, dynamic>>>[];
                      for (final opponent in opponents) {
                        final score = _opponentMatchScore(
                          opponent['name'].toString(),
                          query,
                        );
                        if (score != null) {
                          ranked.add(MapEntry(score, opponent));
                        }
                      }
                      ranked.sort((a, b) {
                        final byScore = a.key.compareTo(b.key);
                        if (byScore != 0) return byScore;
                        return a.value['name'].toString().compareTo(
                              b.value['name'].toString(),
                            );
                      });
                      return ranked.take(8).map((entry) => entry.value);
                    },
                    fieldViewBuilder:
                        (context, textController, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: textController,
                        focusNode: focusNode,
                        enabled: !busy,
                        textAlign: TextAlign.start,
                        textAlignVertical: TextAlignVertical.center,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          hintText: 'Rechercher...',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                        onFieldSubmitted: (_) => onFieldSubmitted(),
                        onChanged: (value) {
                          if (_opponentId.isEmpty) return;
                          if (_normalizeOpponentSearch(value) ==
                              _normalizeOpponentSearch(
                                selectedOpponentName,
                              )) {
                            return;
                          }
                          setState(() {
                            _opponentId = '';
                            _oddsWin = null;
                            _oddsDraw = null;
                            _oddsLoss = null;
                          });
                        },
                        validator: (_) => _isNormalMatch && _opponentId.isEmpty
                            ? 'Sélectionnez un adversaire'
                            : null,
                      );
                    },
                    onSelected: (opponent) {
                      setState(() {
                        _opponentId = opponent['id'].toString();
                        _refreshAddressForSelection();
                      });
                      _suggestOdds();
                    },
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
          ],
        ),
      );
    }

    if (_isNormalMatch) {
      addCard(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
          ],
        ),
      );

      addCard(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                              _selectedJersey =
                                  _selectedJersey == option ? null : option;
                            }),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    addCard(
      Row(
        children: [
          Expanded(
            child: MatchFormPickerTile(
              label: 'Date',
              value: _formatDate(_startsAt),
              enabled: !busy,
              onTap: _pickDate,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MatchFormPickerTile(
              label: 'Heure',
              value: _formatTime(_startsAt),
              enabled: !busy,
              onTap: _pickTime,
            ),
          ),
        ],
      ),
    );

    addCard(
      MatchMeetingTimePicker(
        kickoffAt: _startsAt,
        customMeetingAt: _meetingAt,
        enabled: !busy,
        onChanged: (value) => setState(() => _meetingAt = value),
      ),
    );

    if (widget.event == null) {
      addCard(
        ConvocationLaunchPicker(
          kickoffAt: _startsAt,
          mode: _launchMode,
          customAt: _customLaunchAt,
          enabled: !busy,
          onModeChanged: (mode) => setState(() => _launchMode = mode),
          onCustomAtChanged: (value) => setState(() => _customLaunchAt = value),
        ),
      );
    }

    addCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
              alignLabelWithHint: true,
            ),
          ),
          if (_isNormalMatch)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: const VisualDensity(vertical: -4),
              value: _rememberAddressAsDefault,
              onChanged: busy
                  ? null
                  : (value) => setState(
                        () => _rememberAddressAsDefault = value ?? false,
                      ),
              title: Text(
                'Mémorise cette adresse',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ),
    );

    if (_isNormalMatch && sportsEnabled) {
      addCard(
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Nombre de joueurs convoqués ${_squadSizeController.text} joueur${_squadSizeController.text == '1' ? '' : 's'}',
              maxLines: 1,
            ),
          ),
          trailing: const Icon(Icons.unfold_more_rounded),
          onTap: busy ? null : _pickSquadSize,
        ),
      );
    }

    return fields;
  }

  Widget _dateTile({required bool busy}) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Date'),
        subtitle: Text(_formatDate(_startsAt)),
        trailing: const Icon(Icons.unfold_more_rounded),
        onTap: busy ? null : _pickDate,
      );

  Widget _timeTile({required bool busy}) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Heure'),
        subtitle: Text(_formatTime(_startsAt)),
        trailing: const Icon(Icons.unfold_more_rounded),
        onTap: busy ? null : _pickTime,
      );

  void _changeKind(_CalendarEntryKind? kind) {
    if (kind == null || kind == _kind) return;
    setState(() {
      _kind = kind;
      _rememberAddressAsDefault = _isNormalMatch;
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

  void _changeVenue(bool isHome) {
    if (_isHome == isHome) return;
    setState(() {
      _isHome = isHome;
      _refreshAddressForSelection();
    });
    _suggestOdds();
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
      _oddsWin = null;
      _oddsDraw = null;
      _oddsLoss = null;
    });
    final odds = await ref.read(matchesRepositoryProvider).previewMatchOdds(
          opponentId: _opponentId,
          isHome: _isHome,
          referenceDate: _startsAt,
        );
    if (!mounted || token != _oddsRequestToken) return;
    setState(() {
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
      final opponent = ref.read(matchesControllerProvider).opponents.firstWhere(
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
    if (name == null || name.trim().isEmpty || !mounted) return;
    final trimmedName = name.trim();
    final alreadyExists = ref
        .read(matchesControllerProvider)
        .opponents
        .any((opponent) => opponent['name']?.toString() == trimmedName);
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
      _opponentId = id;
      _refreshAddressForSelection();
    });
    await _suggestOdds();
  }

  Future<void> _pickDate() async {
    final previousKickoff = _startsAt;
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDate = widget.event == null
        ? today
        : DateUtils.dateOnly(_startsAt).isBefore(today)
            ? DateUtils.dateOnly(_startsAt)
            : today;
    final date = await MatchWheelPicker.pickDate(
      context: context,
      initialDate: _startsAt,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        _startsAt.hour,
        _startsAt.minute,
      );
      _repairCustomLaunchIfNeeded();
      _repairMeetingAt(previousKickoffAt: previousKickoff);
    });
    if (_isNormalMatch && _opponentId.isNotEmpty) {
      await _suggestOdds();
    }
  }

  Future<void> _pickTime() async {
    final previousKickoff = _startsAt;
    final time = await MatchWheelPicker.pickTime(
      context: context,
      initialDateTime: _startsAt,
    );
    if (time == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        _startsAt.year,
        _startsAt.month,
        _startsAt.day,
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

  Future<void> _pickChampionshipRound() async {
    final rounds = _championshipRoundsOfSeason(
      ref.read(matchesControllerProvider).matches,
    ).toList(growable: false);
    final value = await MatchWheelPicker.pickInt(
      context: context,
      initialValue: _championshipRound ?? suggestedChampionshipRound(rounds),
      minValue: 1,
      maxValue: maxChampionshipRound,
      title: 'Journée de championnat',
      labelBuilder: (number) => 'J$number',
    );
    if (value == null || !mounted) return;
    setState(() => _championshipRound = value);
  }

  void _repairMeetingAt({required DateTime previousKickoffAt}) {
    _meetingAt = preserveCustomMeetingTime(
      previousKickoffAt: previousKickoffAt,
      kickoffAt: _startsAt,
      customMeetingAt: _meetingAt,
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
        final meetingError = validateCustomMeetingAt(
          kickoffAt: _startsAt,
          customMeetingAt: _meetingAt,
        );
        if (meetingError != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(meetingError)));
          return;
        }
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
        final currentSportsEnabled = ref.read(sportsManagementEnabledProvider);
        final squadSizeLimit = currentSportsEnabled
            ? int.parse(_squadSizeController.text.trim())
            : null;
        final creation = ref.read(scheduledMatchCreationRepositoryProvider);
        final matchId = await creation.createMatch(
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
        final chosenRound = _championshipRound;
        if (_isChampionship && chosenRound != null) {
          final matches = ref.read(matchesRepositoryProvider);
          await matches.setMatchChampionshipRound(
            matchId: matchId,
            round: chosenRound,
          );
        }
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
    final confirmed = await showDialog<bool>(
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

class _EntryKindPicker extends StatelessWidget {
  const _EntryKindPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final _CalendarEntryKind value;
  final bool enabled;
  final ValueChanged<_CalendarEntryKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                selected: value == _CalendarEntryKind.championnat,
                enabled: enabled,
                onPressed: () => onChanged(_CalendarEntryKind.championnat),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactChoiceButton(
                label: 'Amical',
                selected: value == _CalendarEntryKind.amical,
                enabled: enabled,
                onPressed: () => onChanged(_CalendarEntryKind.amical),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _CompactChoiceButton(
                label: 'Match entre nous',
                selected: value == _CalendarEntryKind.internal,
                enabled: enabled,
                onPressed: () => onChanged(_CalendarEntryKind.internal),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactChoiceButton(
                label: 'Événement',
                selected: value == _CalendarEntryKind.event,
                enabled: enabled,
                onPressed: () => onChanged(_CalendarEntryKind.event),
              ),
            ),
          ],
        ),
      ],
    );
  }
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
    final child = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    if (selected) {
      return FilledButton(
        style: style.copyWith(
          foregroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.secondary,
          ),
        ),
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

class _CriterionCard extends StatelessWidget {
  const _CriterionCard({required this.child, required this.lighter});

  final Widget child;
  final bool lighter;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = Color.alphaBlend(
      colors.primary.withValues(alpha: lighter ? 0.14 : 0.06),
      colors.surface,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.primary.withValues(alpha: lighter ? 0.28 : 0.18),
        ),
      ),
      child: child,
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
    final accent = Theme.of(context).colorScheme.secondary;
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
