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
  late String _seasonId;
  late String _opponentId;
  late DateTime _kickoffAt;
  late bool _isHome;
  late int _plannedDurationMinutes;
  late String _status;

  @override
  void initState() {
    super.initState();
    final match = widget.match;
    _seasonId = match?.seasonId ?? '';
    _opponentId = match?.opponentId ?? '';
    _opponentTextController.text = match?.opponentName ?? '';
    _kickoffAt =
        match?.kickoffAt ?? DateTime.now().add(const Duration(days: 1));
    _isHome = match?.isHome ?? true;
    _plannedDurationMinutes = match?.plannedDurationMinutes ?? 90;
    _status = match?.status ?? 'a_venir';
  }

  @override
  void dispose() {
    _opponentTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchesState = ref.watch(matchesControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final canManage = authState.profile?.role == AuthRole.admin;

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
            DropdownButtonFormField<String>(
              initialValue: _seasonId.isEmpty ? null : _seasonId,
              decoration: const InputDecoration(labelText: 'Saison'),
              items: matchesState.seasons.map((season) {
                return DropdownMenuItem<String>(
                  value: season['id'].toString(),
                  child: Text(season['name'].toString()),
                );
              }).toList(),
              onChanged: (value) => setState(() => _seasonId = value ?? ''),
              validator: (value) => value == null || value.isEmpty
                  ? 'Sélectionnez une saison'
                  : null,
            ),
            const SizedBox(height: 16),
            Autocomplete<Map<String, dynamic>>(
              displayStringForOption: (option) => option['name'].toString(),
              initialValue:
                  TextEditingValue(text: _opponentTextController.text),
              optionsBuilder: (textValue) {
                final query = textValue.text.trim().toLowerCase();
                if (query.isEmpty) return matchesState.opponents;
                return matchesState.opponents.where(
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
                textController.addListener(() {
                  if (_opponentTextController.text != textController.text) {
                    _opponentTextController.text = textController.text;
                    final exact = matchesState.opponents.where(
                      (opponent) =>
                          opponent['name'].toString().toLowerCase() ==
                          textController.text.trim().toLowerCase(),
                    );
                    _opponentId =
                        exact.isEmpty ? '' : exact.first['id'].toString();
                  }
                });
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
                        final opponent = matchesState.opponents.where(
                          (item) => item['id'].toString() == created,
                        );
                        setState(() {
                          _opponentId = created;
                          if (opponent.isNotEmpty) {
                            textController.text =
                                opponent.first['name'].toString();
                          }
                        });
                      },
                    ),
                  ),
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
              title: const Text('Date et heure'),
              subtitle: Text(_kickoffAt.toLocal().toString()),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _kickoffAt,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (!context.mounted || date == null) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_kickoffAt),
                );
                if (!context.mounted || time == null) return;
                setState(() {
                  _kickoffAt = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  );
                });
              },
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
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _plannedDurationMinutes.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Durée (minutes)'),
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                if (parsed == null || parsed <= 0) return 'Durée invalide';
                return null;
              },
              onChanged: (value) =>
                  _plannedDurationMinutes = int.tryParse(value) ?? 90,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Statut'),
              items: const [
                DropdownMenuItem(value: 'a_venir', child: Text('À venir')),
                DropdownMenuItem(value: 'en_cours', child: Text('En cours')),
                DropdownMenuItem(value: 'termine', child: Text('Terminé')),
                DropdownMenuItem(value: 'archive', child: Text('Archivé')),
              ],
              onChanged: (value) =>
                  setState(() => _status = value ?? 'a_venir'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: !canManage || matchesState.isLoading ? null : _submit,
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(matchesControllerProvider.notifier);

    if (widget.match == null) {
      await notifier.createMatch(
        seasonId: _seasonId,
        opponentId: _opponentId,
        kickoffAt: _kickoffAt,
        isHome: _isHome,
        plannedDurationMinutes: _plannedDurationMinutes,
        status: _status,
      );
    } else {
      await notifier.updateMatch(
        id: widget.match!.id,
        seasonId: _seasonId,
        opponentId: _opponentId,
        kickoffAt: _kickoffAt,
        isHome: _isHome,
        plannedDurationMinutes: _plannedDurationMinutes,
        status: _status,
      );
    }

    if (!mounted) return;
    if (ref.read(matchesControllerProvider).error == null) {
      Navigator.of(context).pop();
    }
  }
}
