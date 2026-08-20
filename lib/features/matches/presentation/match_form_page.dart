import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/utils/match_window.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/feature_flags/presentation/feature_flags_controller.dart';
import 'package:as_grinta/features/matches/data/matches_repository.dart';
import 'package:as_grinta/features/matches/domain/jersey_option.dart';
import 'package:as_grinta/features/matches/domain/match_model.dart';
import 'package:as_grinta/features/matches/presentation/matches_controller.dart';
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
  bool _rememberAddressAsDefault = false;

  /// Incrémenté à chaque nouvelle demande de cotes : une réponse dont le
  /// jeton ne correspond plus à la dernière demande en cours est ignorée,
  /// pour qu'un changement rapide d'adversaire ne se fasse jamais écraser
  /// par la réponse d'un choix précédent arrivée en retard.
  int _oddsRequestToken = 0;

  /// Adresse du terrain d'AS Grinta (matchs à domicile), mémorisée globalement.
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
    final odds = await ref
        .read(matchesRepositoryProvider)
        .previewMatchOdds(opponentId: _opponentId, isHome: _isHome);
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

  @override
  Widget build(BuildContext context) {
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

    final busy = state.isLoading || _squadLimitLoading;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: GrintaAppBar(
        title: Text(widget.match == null ? 'Ajouter' : 'Modifier'),
        admin: true,
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
              DropdownButtonFormField<String>(
                initialValue: _isInternal ? 'entre_nous' : _matchType,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: [
                  if (!(widget.match?.isInternal ?? false)) ...const [
                    DropdownMenuItem(
                      value: 'championnat',
                      child: Text('Championnat'),
                    ),
                    DropdownMenuItem(value: 'amical', child: Text('Amical')),
                  ],
                  if (widget.match == null ||
                      (widget.match?.isInternal ?? false))
                    const DropdownMenuItem(
                      value: 'entre_nous',
                      child: Text('Match entre nous'),
                    ),
                ],
                onChanged: (widget.match?.isInternal ?? false) || busy
                    ? null
                    : _changeMatchKind,
              ),
              const SizedBox(height: 18),
              if (!_isInternal) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _opponentId.isEmpty ? null : _opponentId,
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
                    IconButton.filledTonal(
                      tooltip: 'Ajouter un adversaire',
                      onPressed: busy ? null : _createOpponent,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<bool>(
                  initialValue: _isHome,
                  decoration: const InputDecoration(labelText: 'Lieu'),
                  items: const [
                    DropdownMenuItem(value: true, child: Text('Domicile')),
                    DropdownMenuItem(value: false, child: Text('Extérieur')),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          setState(() {
                            _isHome = value ?? true;
                            _refreshAddressForSelection();
                          });
                          _suggestOdds();
                        },
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(_formatDate(_kickoffAt)),
                trailing: const Icon(Icons.calendar_today),
                onTap: busy ? null : _pickDate,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Heure'),
                subtitle: Text(_formatTime(_kickoffAt)),
                trailing: const Icon(Icons.schedule),
                onTap: busy ? null : _pickTime,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                enabled: !busy,
                textCapitalization: TextCapitalization.words,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Adresse (facultatif)',
                  hintText: 'Terrain, rue, ville…',
                  prefixIcon: Icon(Icons.place_outlined),
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
                  title: const Text(
                    'Utiliser cette adresse par défaut pour les prochains matchs',
                  ),
                  subtitle: Text(
                    _isHome
                        ? 'Met à jour le terrain par défaut d’AS Grinta.'
                        : 'Met à jour le terrain par défaut de l’adversaire.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
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
                                  _selectedJersey =
                                      _selectedJersey == option ? null : option;
                                }),
                      ),
                  ],
                ),
                if (sportsEnabled) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _squadSizeController,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Nombre de joueurs convoqués',
                      suffixIcon: _squadLimitLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: GrintaProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                    validator: (raw) {
                      final value = int.tryParse(raw?.trim() ?? '');
                      if (value == null || value < 1 || value > 30) {
                        return 'Choisissez un nombre entre 1 et 30';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Cotes',
                      style: Theme.of(context).textTheme.titleMedium,
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
                label: Text(widget.match == null ? 'Ajouter' : 'Enregistrer'),
              ),
              if (widget.match != null && canManage) ...[
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
    final id = await ref
        .read(matchesControllerProvider.notifier)
        .createOpponent(name.trim());
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
    final today = DateUtils.dateOnly(DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: _kickoffAt,
      firstDate: DateUtils.dateOnly(_kickoffAt).isBefore(today)
          ? DateUtils.dateOnly(_kickoffAt)
          : today,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null) return;
    setState(() {
      _kickoffAt = DateTime(
        date.year,
        date.month,
        date.day,
        _kickoffAt.hour,
        _kickoffAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_kickoffAt),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _kickoffAt = DateTime(
        _kickoffAt.year,
        _kickoffAt.month,
        _kickoffAt.day,
        time.hour,
        time.minute,
      );
    });
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

    final notifier = ref.read(matchesControllerProvider.notifier);
    final address = _addressController.text.trim();
    if (_isInternal) {
      if (widget.match == null) {
        await notifier.createInternalMatch(
          seasonId: _seasonId,
          kickoffAt: _kickoffAt,
          address: address.isEmpty ? null : address,
        );
      } else {
        await notifier.updateInternalMatch(
          id: widget.match!.id,
          seasonId: _seasonId,
          kickoffAt: _kickoffAt,
          expectedUpdatedAt: widget.match!.updatedAt,
          address: address.isEmpty ? null : address,
          rememberAddressAsDefault: _rememberAddressAsDefault,
        );
      }
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
    final jerseyNote = _selectedJersey?.id;
    if (widget.match == null) {
      await notifier.createMatch(
        seasonId: _seasonId,
        opponentId: _opponentId,
        kickoffAt: _kickoffAt,
        isHome: _isHome,
        oddsWin: oddsWin,
        oddsDraw: oddsDraw,
        oddsLoss: oddsLoss,
        squadSizeLimit: squadSizeLimit,
        address: address.isEmpty ? null : address,
        rememberAddressAsDefault: _rememberAddressAsDefault,
        matchType: _matchType,
        jerseyNote: jerseyNote,
      );
    } else {
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
        jerseyNote: jerseyNote,
      );
    }
    if (!mounted) return;
    if (ref.read(matchesControllerProvider).error == null) {
      Navigator.pop(context);
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
                // Sans repli, une illustration manquante ou non chargée laisse
                // une case vide et le maillot devient impossible à choisir.
                errorBuilder: (context, _, __) => _JerseyFallback(
                  label: option.label,
                  selected: selected,
                ),
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

/// Repli du sélecteur de maillot quand l'illustration ne peut pas être chargée.
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
