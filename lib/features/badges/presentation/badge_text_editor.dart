import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/features/badges/data/badge_admin_repository.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/data/featured_badges_repository.dart';
import 'package:as_grinta/features/badges/data/statistics_badge_emblems_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _maxNameLength = 60;
const _maxDescriptionLength = 300;

/// Action d'administration pour corriger le nom et le descriptif d'un badge.
class BadgeTextEditorButton extends StatelessWidget {
  const BadgeTextEditorButton({super.key, required this.badge});

  final BadgeDef badge;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BadgeTextDialog(badge: badge),
      ),
      child: const Text('Texte'),
    );
  }
}

class _BadgeTextDialog extends ConsumerStatefulWidget {
  const _BadgeTextDialog({required this.badge});

  final BadgeDef badge;

  @override
  ConsumerState<_BadgeTextDialog> createState() => _BadgeTextDialogState();
}

class _BadgeTextDialogState extends ConsumerState<_BadgeTextDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.badge.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.badge.description);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_refresh);
    _description.addListener(_refresh);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  bool get _canSave {
    final name = _name.text.trim();
    final description = _description.text.trim();
    final changed = name != widget.badge.name.trim() ||
        description != widget.badge.description.trim();
    return !_saving && name.isNotEmpty && changed;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      await ref.read(badgeAdminRepositoryProvider).updateBadgeText(
            badgeCode: widget.badge.code,
            name: _name.text,
            description: _description.text,
          );
      ref.invalidate(badgeCatalogProvider);
      ref.invalidate(myArmoireProvider);
      ref.invalidate(featuredBadgesProvider);
      ref.invalidate(statisticsBadgeEmblemsProvider);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Badge mis à jour.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier le badge'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              enabled: !_saving,
              autofocus: true,
              maxLength: _maxNameLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              enabled: !_saving,
              minLines: 2,
              maxLines: 5,
              maxLength: _maxDescriptionLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Descriptif'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _canSave ? _save : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
