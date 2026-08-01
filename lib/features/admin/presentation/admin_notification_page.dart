import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/admin/data/admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L'admin écrit son propre message et choisit qui le reçoit.
class AdminNotificationPage extends ConsumerStatefulWidget {
  const AdminNotificationPage({super.key});

  @override
  ConsumerState<AdminNotificationPage> createState() =>
      _AdminNotificationPageState();
}

class _AdminNotificationPageState extends ConsumerState<AdminNotificationPage> {
  static const _titleMaxLength = 80;
  static const _bodyMaxLength = 300;

  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final Set<String> _recipients = {};
  bool _sending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send(List<AdminProfileItem> recipients) async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _showMessage('Écris un titre et un message.');
      return;
    }
    if (_recipients.isEmpty) {
      _showMessage('Choisis au moins un destinataire.');
      return;
    }

    final names = [
      for (final profile in recipients)
        if (_recipients.contains(profile.id)) profile.displayName,
    ];
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Envoyer la notification ?'),
            content: Text(
              '« $title »\n\n$body\n\n'
              'Destinataires (${names.length}) : ${names.join(', ')}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Envoyer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _sending = true);
    try {
      final sent =
          await ref.read(adminRepositoryProvider).sendCustomNotification(
                title: title,
                body: body,
                profileIds: _recipients.toList(),
              );
      if (!mounted) return;
      _showMessage(
        sent <= 1
            ? 'Notification envoyée à 1 personne.'
            : 'Notification envoyée à $sent personnes.',
      );
      setState(() {
        _titleController.clear();
        _bodyController.clear();
        _recipients.clear();
      });
    } catch (error) {
      if (mounted) _showMessage(humanizeError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(adminDashboardProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Notification'), admin: true),
      body: dashboard.when(
        loading: () => const Center(child: GrintaProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(humanizeError(error), textAlign: TextAlign.center),
          ),
        ),
        data: (data) {
          // Seuls les comptes actifs peuvent recevoir une notification.
          final profiles = [
            for (final profile in data.profiles)
              if (profile.status == 'active') profile,
          ]..sort(
              (a, b) => a.displayName.toLowerCase().compareTo(
                    b.displayName.toLowerCase(),
                  ),
            );
          final allSelected = profiles.isNotEmpty &&
              profiles.every((profile) => _recipients.contains(profile.id));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _titleController,
                        enabled: !_sending,
                        maxLength: _titleMaxLength,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Titre',
                          hintText: 'Entraînement déplacé',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _bodyController,
                        enabled: !_sending,
                        maxLength: _bodyMaxLength,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Message',
                          hintText: 'Rendez-vous à 19h au lieu de 18h30.',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Destinataires (${_recipients.length})',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          TextButton(
                            onPressed: _sending || profiles.isEmpty
                                ? null
                                : () => setState(() {
                                      if (allSelected) {
                                        _recipients.clear();
                                      } else {
                                        _recipients
                                          ..clear()
                                          ..addAll(
                                            profiles.map(
                                              (profile) => profile.id,
                                            ),
                                          );
                                      }
                                    }),
                            child: Text(
                              allSelected ? 'Aucun' : 'Tout le monde',
                            ),
                          ),
                        ],
                      ),
                      if (profiles.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Aucun compte actif.'),
                        )
                      else
                        for (final profile in profiles)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _recipients.contains(profile.id),
                            onChanged: _sending
                                ? null
                                : (checked) => setState(() {
                                      if (checked == true) {
                                        _recipients.add(profile.id);
                                      } else {
                                        _recipients.remove(profile.id);
                                      }
                                    }),
                            title: Text(profile.fullName.isEmpty
                                ? profile.displayName
                                : profile.fullName),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _sending ? null : () => _send(profiles),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: GrintaProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Envoyer'),
              ),
              const SizedBox(height: 8),
              Text(
                'Seules les personnes ayant autorisé les notifications sur '
                'leur téléphone la recevront.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}
