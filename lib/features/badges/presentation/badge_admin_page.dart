import 'dart:typed_data';

import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/badges/data/badge_admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Écran admin : créer un badge (nom + image) et le décerner manuellement.
class BadgeAdminPage extends ConsumerStatefulWidget {
  const BadgeAdminPage({super.key});

  @override
  ConsumerState<BadgeAdminPage> createState() => _BadgeAdminPageState();
}

class _BadgeAdminPageState extends ConsumerState<BadgeAdminPage> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _searchController = TextEditingController();
  Uint8List? _imageBytes;
  String _imageExt = 'png';
  bool _creating = false;
  String _query = '';

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final name = file.name;
    final ext = name.contains('.') ? name.split('.').last : 'png';
    setState(() {
      _imageBytes = bytes;
      _imageExt = ext;
    });
  }

  Future<void> _createBadge() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Donne un nom au badge.')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      final repo = ref.read(badgeAdminRepositoryProvider);
      String? imageUrl;
      if (_imageBytes != null) {
        imageUrl = await repo.uploadBadgeImage(_imageBytes!, _imageExt);
      }
      await repo.createCustomBadge(
        name: name,
        description: _descController.text.trim(),
        imageUrl: imageUrl,
      );
      ref.invalidate(adminBadgesProvider);
      if (mounted) {
        _nameController.clear();
        _descController.clear();
        setState(() => _imageBytes = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Badge « $name » créé.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final badgesAsync = ref.watch(adminBadgesProvider);

    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Badges')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _CreateBadgeCard(
            nameController: _nameController,
            descController: _descController,
            imageBytes: _imageBytes,
            creating: _creating,
            onPickImage: _pickImage,
            onRemoveImage: () => setState(() => _imageBytes = null),
            onCreate: _createBadge,
          ),
          const SizedBox(height: 24),
          Text('Décerner un badge',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Clique sur un badge, puis choisis à qui l’attribuer ou le retirer.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Rechercher un badge…',
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          badgesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(humanizeError(e)),
            data: (badges) {
              final filtered = _query.isEmpty
                  ? badges
                  : badges
                      .where((b) => b.name.toLowerCase().contains(_query))
                      .toList();
              if (filtered.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aucun badge trouvé.'),
                );
              }
              return Column(
                children: [
                  for (final b in filtered)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: _BadgeAvatar(badge: b),
                        title: Text(b.name),
                        subtitle: b.isCustom ? const Text('Custom') : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => _AwardSheet(badge: b),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BadgeAvatar extends StatelessWidget {
  const _BadgeAvatar({required this.badge});
  final AdminBadge badge;

  @override
  Widget build(BuildContext context) {
    if (badge.imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          badge.imageUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Text(badge.emoji, style: const TextStyle(fontSize: 26)),
        ),
      );
    }
    return Text(badge.emoji, style: const TextStyle(fontSize: 26));
  }
}

class _CreateBadgeCard extends StatelessWidget {
  const _CreateBadgeCard({
    required this.nameController,
    required this.descController,
    required this.imageBytes,
    required this.creating,
    required this.onPickImage,
    required this.onRemoveImage,
    required this.onCreate,
  });

  final TextEditingController nameController;
  final TextEditingController descController;
  final Uint8List? imageBytes;
  final bool creating;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Créer un badge',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nom du badge',
                hintText: 'Ex. Champion du BBQ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (facultatif)',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: imageBytes == null
                      ? const Icon(Icons.image_outlined)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            imageBytes!,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onPickImage,
                        icon: const Icon(Icons.upload_outlined, size: 18),
                        label: Text(
                          imageBytes == null
                              ? 'Choisir une image'
                              : 'Changer l’image',
                        ),
                      ),
                      if (imageBytes != null)
                        TextButton.icon(
                          onPressed: onRemoveImage,
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Retirer l’image'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sans image, le badge utilisera une médaille 🏅 par défaut.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: creating ? null : onCreate,
                icon: creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Créer le badge'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Feuille pour décerner / retirer un badge à des personnes.
class _AwardSheet extends ConsumerStatefulWidget {
  const _AwardSheet({required this.badge});
  final AdminBadge badge;

  @override
  ConsumerState<_AwardSheet> createState() => _AwardSheetState();
}

class _AwardSheetState extends ConsumerState<_AwardSheet> {
  Set<String> _awardees = {};
  final Set<String> _busy = {};
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final awardees = await ref
          .read(badgeAdminRepositoryProvider)
          .fetchAwardees(widget.badge.code);
      if (mounted) {
        setState(() {
          _awardees = awardees;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = humanizeError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle(AdminPerson person) async {
    final repo = ref.read(badgeAdminRepositoryProvider);
    final has = _awardees.contains(person.id);
    setState(() => _busy.add(person.id));
    try {
      if (has) {
        await repo.revokeBadge(widget.badge.code, person.id);
        _awardees.remove(person.id);
      } else {
        await repo.awardBadge(widget.badge.code, person.id);
        _awardees.add(person.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(person.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final peopleAsync = ref.watch(adminPeopleProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BadgeAvatar(badge: widget.badge),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.badge.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Rechercher une personne…',
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          if (_loading || _error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: _error != null
                  ? Text(_error!)
                  : const Center(child: CircularProgressIndicator()),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: peopleAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text(humanizeError(e)),
                data: (people) {
                  final filtered = _query.isEmpty
                      ? people
                      : people
                          .where((p) => p.name.toLowerCase().contains(_query))
                          .toList();
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in filtered)
                        CheckboxListTile(
                          value: _awardees.contains(p.id),
                          title: Text(p.name),
                          secondary: _busy.contains(p.id)
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                          onChanged:
                              _busy.contains(p.id) ? null : (_) => _toggle(p),
                        ),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Aucune personne trouvée.'),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
