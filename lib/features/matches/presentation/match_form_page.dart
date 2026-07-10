import 'package:as_grinta/features/auth/domain/auth_profile.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
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
  final _opponentController = TextEditingController();
  final _timeController = TextEditingController();
  final _competitionController = TextEditingController();
  final _oddsWinController = TextEditingController();
  final _oddsDrawController = TextEditingController();
  final _oddsLossController = TextEditingController();

  late String _seasonId;
  late String _opponentId;
  late DateTime _kickoffAt;
  late bool _isHome;

  @override
  void initState() {
    super.initState();
    final match = widget.match;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _seasonId = match?.seasonId ?? '';
    _opponentId = match?.opponentId ?? '';
    _opponentController.text = match?.opponentName ?? '';
    _competitionController.text = match?.competition ?? 'Championnat';
    _kickoffAt = match?.kickoffAt ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 21);
    _timeController.text = _formatTime(_kickoffAt);
    _isHome = match?.isHome ?? true;
    _oddsWinController.text = _formatOdds(match?.oddsWin ?? 2.00);
    _oddsDrawController.text = _formatOdds(match?.oddsDraw ?? 3.50);
    _oddsLossController.text = _formatOdds(match?.oddsLoss ?? 3.00);
  }

  @override
  void dispose() {
    _opponentController.dispose();
    _timeController.dispose();
    _competitionController.dispose();
    _oddsWinController.dispose();
    _oddsDrawController.dispose();
    _oddsLossController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchesControllerProvider);
    final role = ref.watch(authControllerProvider).profile?.role;
    final canManage = role == AuthRole.admin || role == AuthRole.moderateur;
    final opponents = [...state.opponents]
      ..sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
    final openSeasons = state.seasons
        .where((season) => season['status']?.toString() == 'open')
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.match == null ? 'Créer un match' : 'Modifier le match'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              value: _seasonId.isEmpty ? null : _seasonId,
              decoration: const InputDecoration(labelText: 'Saison'),
              items: (widget.match == null ? openSeasons : state.seasons)
                  .map(
                    (season) => DropdownMenuItem<String>(
                      value: season['id'].toString(),
                      child: Text(season['name'].toString()),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _seasonId = value ?? ''),
              validator: (value) => value == null || value.isEmpty
                  ? 'Sélectionnez une saison'
                  : null,
            ),
            const SizedBox(height: 12),
            Autocomplete<Map<String, dynamic>>(
              displayStringForOption: (option) => option['name'].toString(),
              initialValue: TextEditingValue(text: _opponentController.text),
              optionsBuilder: (value) {
                final query = value.text.trim().toLowerCase();
                return opponents.where((opponent) => opponent['name']
                    .toString()
                    .toLowerCase()
                    .contains(query));
              },
              onSelected: (opponent) {
                _opponentId = opponent['id'].toString();
                _opponentController.text = opponent['name'].toString();
              },
              fieldViewBuilder: (context, controller, focusNode, submit) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Adversaire',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Ajouter un adversaire',
                      onPressed: _createOpponent,
                    ),
                  ),
                  onChanged: (value) {
                    _opponentController.text = value;
                    final exact = opponents.where((opponent) =>
                        opponent['name'].toString().toLowerCase() ==
                        value.trim().toLowerCase());
                    _opponentId =
                        exact.isEmpty ? '' : exact.first['id'].toString();
                  },
                  validator: (_) =>
                      _opponentId.isEmpty ? 'Sélectionnez un adversaire' : null,
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _competitionController,
              decoration: const InputDecoration(
                labelText: 'Championnat / compétition',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Renseignez la compétition'
                  : null,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_formatDate(_kickoffAt)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            TextFormField(
              controller: _timeController,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Heure',
                hintText: '21:00',
              ),
              validator: _validateTime,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<bool>(
              value: _isHome,
              decoration: const InputDecoration(labelText: 'Lieu'),
              items: const [
                DropdownMenuItem(value: true, child: Text('Domicile')),
                DropdownMenuItem(value: false, child: Text('Extérieur')),
              ],
              onChanged: (value) => setState(() => _isHome = value ?? true),
            ),
            const SizedBox(height: 20),
            Text('Cotes', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Elles sont proposées automatiquement puis peuvent être ajustées.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _oddsWinController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Victoire'),
                    validator: _validateOdds,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _oddsDrawController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Nul'),
                    validator: _validateOdds,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _oddsLossController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Défaite'),
                    validator: _validateOdds,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: canManage && !state.isLoading ? _submit : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer'),
            ),
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
    final id = await ref
        .read(matchesControllerProvider.notifier)
        .createOpponent(name.trim());
    if (!mounted || id == null) return;
    setState(() {
      _opponentId = id;
      _opponentController.text = name.trim();
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _kickoffAt,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final parts = _timeController.text.trim().split(':');
    _kickoffAt = DateTime(
      _kickoffAt.year,
      _kickoffAt.month,
      _kickoffAt.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    final oddsWin = _parseOdds(_oddsWinController.text)!;
    final oddsDraw = _parseOdds(_oddsDrawController.text)!;
    final oddsLoss = _parseOdds(_oddsLossController.text)!;
    final notifier = ref.read(matchesControllerProvider.notifier);
    if (widget.match == null) {
      await notifier.createMatch(
        seasonId: _seasonId,
        opponentId: _opponentId,
        kickoffAt: _kickoffAt,
        isHome: _isHome,
        competition: _competitionController.text.trim(),
        oddsWin: oddsWin,
        oddsDraw: oddsDraw,
        oddsLoss: oddsLoss,
      );
    } else {
      await notifier.updateMatch(
        id: widget.match!.id,
        seasonId: _seasonId,
        opponentId: _opponentId,
        kickoffAt: _kickoffAt,
        isHome: _isHome,
        competition: _competitionController.text.trim(),
        status: widget.match!.status,
        oddsWin: oddsWin,
        oddsDraw: oddsDraw,
        oddsLoss: oddsLoss,
      );
    }
    if (!mounted) return;
    if (ref.read(matchesControllerProvider).error == null) {
      Navigator.pop(context);
    }
  }

  String? _validateTime(String? raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw?.trim() ?? '');
    if (match == null) return 'Format attendu : 21:00';
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return 'Heure invalide';
    }
    return null;
  }

  String? _validateOdds(String? raw) {
    final value = _parseOdds(raw ?? '');
    if (value == null || value < 1.01 || value > 100) {
      return '1,01 à 100';
    }
    return null;
  }

  double? _parseOdds(String raw) {
    return double.tryParse(raw.trim().replaceAll(',', '.'));
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }

  String _formatOdds(double value) => value.toStringAsFixed(2).replaceAll('.', ',');
}
