import 'dart:typed_data';

import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/equal_height_column.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/badges/data/badge_admin_repository.dart';
import 'package:as_grinta/features/badges/data/badge_repository.dart';
import 'package:as_grinta/features/badges/presentation/badge_detail_sheet.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:as_grinta/features/badges/presentation/badge_image_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Écran admin : créer un badge manuel dans le format visuel actuel et le
/// décerner à une personne.
class BadgeAdminPage extends ConsumerStatefulWidget {
  const BadgeAdminPage({super.key});

  @override
  ConsumerState<BadgeAdminPage> createState() => _BadgeAdminPageState();
}

class _BadgeAdminPageState extends ConsumerState<BadgeAdminPage> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _commonSearchController = TextEditingController();
  final _mysterySearchController = TextEditingController();
  Uint8List? _badgeImageBytes;
  bool _creating = false;
  String _commonQuery = '';
  String _mysteryQuery = '';

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _commonSearchController.dispose();
    _mysterySearchController.dispose();
    super.dispose();
  }

  Future<void> _editNewBadgeImage() async {
    if (_creating) return;
    final badgeColor =
        parseBadgeColor(kCustomBadgeColorHex) ?? kDefaultBadgeColor;
    final edited = await showBadgeImageCropDialog(
      context,
      badgeColor: badgeColor,
      initialBytes: _badgeImageBytes,
    );
    if (edited == null || !mounted) return;
    setState(() => _badgeImageBytes = edited);
  }

  void _resetNewBadgeImage() {
    if (_creating) return;
    setState(() => _badgeImageBytes = null);
  }

  Future<void> _createBadge() async {
    final name = _nameController.text.trim();
    final imageBytes = _badgeImageBytes;
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Donne un nom au badge.')));
      return;
    }
    if (imageBytes == null || imageBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisis et recadre l’image du badge.')),
      );
      return;
    }

    setState(() => _creating = true);
    try {
      final repo = ref.read(badgeAdminRepositoryProvider);
      await repo.createCustomBadge(
        name: name,
        description: _descController.text.trim(),
        imageBytes: imageBytes,
      );
      ref.invalidate(badgeCatalogProvider);
      if (mounted) {
        _nameController.clear();
        _descController.clear();
        setState(() => _badgeImageBytes = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Badge « $name » créé.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Widget _buildBadgeList(
    BuildContext context,
    AsyncValue<List<BadgeDef>> badgesAsync, {
    required bool mystery,
    required TextEditingController searchController,
    required String query,
    required ValueChanged<String> onSearchChanged,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Text(
          mystery
              ? 'Uniquement les badges mystères.'
              : 'Tous les badges communs visibles dans l’application.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: searchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Rechercher un badge…',
          ),
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: 12),
        badgesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: GrintaProgressIndicator()),
          ),
          error: (e, _) => Text(humanizeError(e)),
          data: (badges) {
            final sectionBadges = badges.where((badge) {
              final isMystery =
                  badge.secret || badge.code.startsWith('custom_');
              return mystery == isMystery;
            });
            final filtered = query.isEmpty
                ? sectionBadges.toList()
                : sectionBadges
                    .where(
                      (badge) =>
                          badge.name.toLowerCase().contains(query),
                    )
                    .toList();

            if (filtered.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucun badge trouvé.'),
              );
            }

            return EqualHeightColumn(
              spacing: 8,
              children: [
                for (final badge in filtered) _buildBadgeCard(context, badge),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildBadgeCard(BuildContext context, BadgeDef badge) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showBadgeDetailSheet(
          context,
          badge,
          onAward: () {
            Navigator.of(context).pop();
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _AwardSheet(badge: badge),
            );
          },
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BadgeEmblem(
                emoji: badge.emoji,
                imageUrl: badge.imageUrl,
                color: badge.color,
                baremeLabel: baremeLabelFor(
                  badge.metric,
                  badge.threshold,
                ),
                descriptor: badgeDescriptorFor(
                  code: badge.code,
                  metric: badge.metric,
                  category: badge.category,
                  name: badge.name,
                ),
                showStar: badge.hasStar,
                size: 81,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badge.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (badge.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(badge.description),
                    ] else if (badge.kind == 'custom') ...[
                      const SizedBox(height: 4),
                      const Text('Custom'),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BadgeImageEditorButton(
                    badge: badge,
                    compact: true,
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabLabel(String label) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(label, textAlign: TextAlign.center),
    );
  }

  @override
  Widget build(BuildContext context) {
    final badgesAsync = ref.watch(badgeCatalogProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: GrintaAppBar(title: const Text('Badges'), admin: true),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(child: _tabLabel('Badges communs')),
                    Tab(child: _tabLabel('Badges mystères')),
                    Tab(child: _tabLabel('Création de badge')),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildBadgeList(
                    context,
                    badgesAsync,
                    mystery: false,
                    searchController: _commonSearchController,
                    query: _commonQuery,
                    onSearchChanged: (value) => setState(
                      () => _commonQuery = value.trim().toLowerCase(),
                    ),
                  ),
                  _buildBadgeList(
                    context,
                    badgesAsync,
                    mystery: true,
                    searchController: _mysterySearchController,
                    query: _mysteryQuery,
                    onSearchChanged: (value) => setState(
                      () => _mysteryQuery = value.trim().toLowerCase(),
                    ),
                  ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                    children: [
                      _CreateBadgeCard(
                        nameController: _nameController,
                        descController: _descController,
                        imageBytes: _badgeImageBytes,
                        creating: _creating,
                        onEditImage: _editNewBadgeImage,
                        onResetImage: _resetNewBadgeImage,
                        onCreate: _createBadge,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateBadgeCard extends StatelessWidget {
  const _CreateBadgeCard({
    required this.nameController,
    required this.descController,
    required this.imageBytes,
    required this.creating,
    required this.onEditImage,
    required this.onResetImage,
    required this.onCreate,
  });

  final TextEditingController nameController;
  final TextEditingController descController;
  final Uint8List? imageBytes;
  final bool creating;
  final VoidCallback onEditImage;
  final VoidCallback onResetImage;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageBytes?.isNotEmpty == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Créer un badge',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Le badge est créé directement comme badge mystère, avec le '
              'fond orange standard, son illustration, son nom et sa description.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            Text(
              '1. Illustration',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: nameController,
                    builder: (context, _) => BadgeEmblem(
                      emoji: '🏅',
                      imageBytes: imageBytes,
                      color: kCustomBadgeColorHex,
                      descriptor: BadgeDescriptor(
                        nameController.text.trim().isEmpty
                            ? 'NOM DU BADGE'
                            : nameController.text.trim().toUpperCase(),
                      ),
                      size: 92,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasImage
                              ? 'Illustration prête'
                              : 'Ajoute l’image du badge',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasImage
                              ? 'L’aperçu ci-contre est celui qui sera enregistré.'
                              : 'Choisis un PNG ou JPEG, puis déplace et zoome '
                                  'l’image exactement comme pour les badges existants.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: creating ? null : onEditImage,
                          icon: Icon(
                            hasImage
                                ? Icons.crop_rounded
                                : Icons.photo_library_rounded,
                          ),
                          label: Text(
                            hasImage
                                ? 'Modifier le recadrage'
                                : 'Choisir et recadrer',
                          ),
                        ),
                        if (hasImage) ...[
                          const SizedBox(height: 4),
                          TextButton.icon(
                            onPressed: creating ? null : onResetImage,
                            icon: const Icon(
                              Icons.restart_alt_rounded,
                              size: 18,
                            ),
                            label: const Text('Choisir une autre image'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '2. Informations',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameController,
              enabled: !creating,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nom du badge',
                hintText: 'Ex. Champion du BBQ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              enabled: !creating,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (facultatif)',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Plus besoin d’emoji : l’illustration choisie devient le visuel '
              'du badge et son nom apparaît automatiquement sur le socle.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: creating || !hasImage ? null : onCreate,
                icon: creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: GrintaProgressIndicator(strokeWidth: 2),
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

/// Feuille pour décerner un badge.
///
/// Un badge décerné ne se retire plus : la liste ne propose donc que les
/// personnes qui ne l'ont pas encore, et chaque attribution est confirmée
/// avant d'être envoyée.
class _AwardSheet extends ConsumerStatefulWidget {
  const _AwardSheet({required this.badge});
  final BadgeDef badge;

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

  Future<bool> _confirm(AdminPerson person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Décerner « ${widget.badge.name} » ?'),
        content: Text(
          '${person.name} recevra ce badge. Une fois décerné, il ne pourra '
          'plus lui être retiré.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Décerner'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _award(AdminPerson person) async {
    if (!await _confirm(person) || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(person.id));
    try {
      await ref
          .read(badgeAdminRepositoryProvider)
          .awardBadge(widget.badge.code, person.id);
      if (!mounted) return;
      // La personne disparaît de la liste : elle a désormais le badge.
      setState(() => _awardees.add(person.id));
      messenger.showSnackBar(
        SnackBar(content: Text('Badge décerné à ${person.name}.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(humanizeError(e))));
    } finally {
      if (mounted) setState(() => _busy.remove(person.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final peopleAsync = ref.watch(adminPeopleProvider);
    final goalkeeperOnly = widget.badge.code == 'role_goalkeeper';
    final holders = _awardees.length;
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
              BadgeEmblem(
                emoji: widget.badge.emoji,
                imageUrl: widget.badge.imageUrl,
                color: widget.badge.color,
                baremeLabel: baremeLabelFor(
                  widget.badge.metric,
                  widget.badge.threshold,
                ),
                descriptor: badgeDescriptorFor(
                  code: widget.badge.code,
                  metric: widget.badge.metric,
                  category: widget.badge.category,
                  name: widget.badge.name,
                ),
                showStar: widget.badge.hasStar,
                size: 81,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.badge.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (!_loading && _error == null) ...[
                      const SizedBox(height: 4),
                      Text(
                        switch (holders) {
                          0 => 'Encore décerné à personne.',
                          1 => 'Déjà décerné à 1 personne.',
                          _ => 'Déjà décerné à $holders personnes.',
                        },
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: goalkeeperOnly
                  ? 'Rechercher un gardien…'
                  : 'Rechercher une personne…',
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          if (_loading || _error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: _error != null
                  ? Text(_error!)
                  : const Center(child: GrintaProgressIndicator()),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: peopleAsync.when(
                loading: () => const Center(child: GrintaProgressIndicator()),
                error: (e, _) => Text(humanizeError(e)),
                data: (people) {
                  final candidates = people
                      .where((p) => !goalkeeperOnly || p.isGoalkeeper)
                      .where((p) => !_awardees.contains(p.id))
                      .toList();
                  final filtered = _query.isEmpty
                      ? candidates
                      : candidates
                          .where((p) => p.name.toLowerCase().contains(_query))
                          .toList();
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in filtered)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.name),
                          trailing: _busy.contains(p.id)
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: GrintaProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : FilledButton.tonal(
                                  onPressed:
                                      _busy.isEmpty ? () => _award(p) : null,
                                  child: const Text('Décerner'),
                                ),
                        ),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            candidates.isEmpty
                                ? goalkeeperOnly
                                    ? 'Tous les gardiens ont déjà ce badge.'
                                    : 'Tout le monde a déjà ce badge.'
                                : goalkeeperOnly
                                    ? 'Aucun gardien trouvé.'
                                    : 'Aucune personne trouvée.',
                          ),
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
