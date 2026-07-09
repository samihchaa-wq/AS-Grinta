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
  final _opponentTextController = TextEditingController();
  final _timeController = TextEditingController();

  late String _seasonId;
  late String _opponentId;
  late DateTime _kickoffAt;
  late bool _isHome;
  late String _status;

  @override
  void initState() {
    super.initState();
    final match = widget.match;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _seasonId = match?.seasonId ?? '';
    _opponentId = match?.opponentId ?? '';
    _opponentTextController.text = match?.opponentName ?? '';
    _kickoffAt = match?.kickoffAt ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 21);
    _timeController.text = _formatTime(_kickoffAt);
    _isHome = match?.isHome ?? true;
    _status = match?.status ?? 'a_venir';
  }

  @override
  void dispose() {
    _opponentTextController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchesState = ref.watch(matchesControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final role = authState.profile?.role;
    final canManage = role == AuthRole.admin || role == AuthRole.moderateur;

    final opponents = List<Map<String, dynamic>>.from(matchesState.opponents)
      ..sort((a, b) => a['name']
          .toString()
          .toLowerCase()
          .compareTo(b['name'].toString().toLowerCase()));

    final hasOpenSeason = widget.match != null ||
        matchesState.seasons.any(
          (season) => season['status']?.toString() == 'open',
        );

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.match == null ? 'Créer un match' : 'Modifier le match'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (!hasOpenSeason) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Aucune saison ouverte. Créez une saison avant d’ajouter un match.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Autocomplete<Map<String, dynamic>>(
              displayStringForOption: (option) => option['name'].toString(),
              initialValue:
                  TextEditingValue(text: _opponentTextController.text),
              optionsBuilder: (textValue) {
                final query = textValue.text.trim().toLowerCase();
                if (query.isEmpty) return opponents;
                return opponents.where(
                  (opponent) =>
                      opponent['name'].toString().toLowerCase().contains(query),
                );
              },
              onSelected: (opponent) {
                setState(() {
                  _opponentId = opponent['id'].toString();
                  _opponentTextController.text = opponent['name'].toString();
                });
              },
              fieldViewBuilder: (
                context,
                textController,
                focusNode,
                onFieldSubmitted,
              ) {
                return TextFormField(
                  controller: textController,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Adversaire',
                    hintText: 'Tapez les premières lettres',
                    suffixIcon: IconButton(
                      tooltip: 'Nouvelle équipe',
                      icon: const Icon(Icons.add_business_outlined),
                      onPressed: () async {
                        final created = await _createOpponent();
                        if (!mounted || created == null) return;
                        final selected = opponents.where(
                          (item) => item['id'].toString() == created,
                        );
                        setState(() {
                          _opponentId = created;
                          if (selected.isNotEmpty) {
                            textController.text =
                                selected.first['name'].toString();
                          } else {
                            textController.text =
                                _opponentTextController.text.trim();
                          }
                        });
                      },
                    ),
                  ),
                  onChanged: (value) {
                    _opponentTextController.text = value;
                    final exact = opponents.where(
                      (opponent) =>
                          opponent['name'].toString().toLowerCase() ==
                          value.trim().toLowerCase(),
                    );
                    _opponentId =
                        exact.isEmpty ? '' : exact.first['id'].toString();
                  },
                  validator: (_) => _opponentId.isEmpty
                      ? 'Sélectionnez une équipe existante ou créez-en une'
                      : null,
                );
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final created = await _createOpponent();
                  if (!mounted || created == null) return;
                  setState(() => _opponentId = created);
                },
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle équipe'),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date du match'),
              subtitle: Text(_formatDate(_kickoffAt)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _kickoffAt,
                  firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (!context.mounted || date == null) return;
                setState(() {
                  _kickoffAt = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    _kickoffAt.hour,
                    _kickoffAt.minute,
                  );
                });
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _timeController,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Heure du match',
                hintText: '21:00',
                helperText: 'Saisissez directement l’heure au format 24 h.',
              ),
              validator: _validateTime,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<bool>(
              initialValue: _isHome,
              decoration: const InputDecoration(labelText: 'Lieu'),
              items: const [
                DropdownMenuItem(value: true, child: Text('Domicile')),
                DropdownMenuItem(value: false, child: Text('Extérieur')),
              ],
              onChanged: (value) => setState(() => _isHome = value ?? true),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: !canManage ||
                      matchesState.isLoading ||
                      !hasOpenSeason
                  ? null
                  : () => _submit(matchesState.seasons),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer'),
            ),
            if (matchesState.error != null) ...[
              const SizedBox(height: 12),
              Text(
                matchesState.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<String?> _createOpponent() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvelle équipe'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom de l’équipe'),
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
    if (name == null || name.trim().isEmpty) return null;

    final id = await ref
        .read(matchesControllerProvider.notifier)
        .createOpponent(name.trim());
    if (id != null) {
      _opponentTextController.text = name.trim();
      setState(() => _opponentId = id);
    }
    return id;
  }

  Future<void> _submit(List<Map<String, dynamic>> seasons) async {
    if (!_formKey.currentState!.validate()) return;

    if (_seasonId.isEmpty) {
      final openSeasons = seasons.where(
        (season) => season['status']?.toString() == 'open',
      );
      if (openSeasons.isEmpty) return;
      _seasonId = openSeasons.first['id'].toString();
    }

    final parts = _timeController.text.trim().split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    _kickoffAt = DateTime(
      _kickoffAt.year,
      _kickoffAt.month,
      _kickoffAt.day,
      hour,
      minute,
    );

    final notifier = ref.read(matchesControllerProvider.notifier);
    if (widget.match == null) {
      await notifier.createMatch(
        seasonId: _seasonId,
        opponentId: _opponentId,
        kickoffAt: _kickoffAt,
        isHome: _isHome,
        plannedDurationMinutes: 90,
        status: 'a_venir',
      );
    } else {
      await notifier.updateMatch(
        id: widget.match!.id,
        seasonId: _seasonId,
        opponentId: _opponentId,
        kickoffAt: _kickoffAt,
        isHome: _isHome,
        plannedDurationMinutes: widget.match!.plannedDurationMinutes,
        status: _status,
      );
    }

    if (!mounted) return;
    if (ref.read(matchesControllerProvider).error == null) {
      Navigator.of(context).pop();
    }
  }

  String? _validateTime(String? raw) {
    final value = raw?.trim() ?? '';
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
    if (match == null) return 'Saisissez une heure au format 21:00';

    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return 'Heure invalide';
    }
    return null;
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }
}
