import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpponentStadiumLibraryPage extends ConsumerStatefulWidget {
  const OpponentStadiumLibraryPage({super.key});

  @override
  ConsumerState<OpponentStadiumLibraryPage> createState() =>
      _OpponentStadiumLibraryPageState();
}

class _OpponentStadiumLibraryPageState
    extends ConsumerState<OpponentStadiumLibraryPage> {
  final _searchController = TextEditingController();
  var _loading = true;
  var _saving = false;
  String? _error;
  List<_OpponentStadium> _items = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshSearch);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  void _refreshSearch() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref
          .read(supabaseClientProvider)
          .from('opponents')
          .select('id, name, stadium_name, address')
          .order('name');
      if (!mounted) return;
      setState(() {
        _items = (rows as List)
            .map(
              (row) => _OpponentStadium.fromJson(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList(growable: false);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = humanizeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_OpponentStadium> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items.where((item) {
      return item.name.toLowerCase().contains(query) ||
          (item.stadiumName?.toLowerCase().contains(query) ?? false) ||
          (item.address?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  Future<void> _openEditor([_OpponentStadium? item]) async {
    final result = await showModalBottomSheet<_OpponentStadiumDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _OpponentStadiumEditor(item: item),
    );
    if (result == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(supabaseClientProvider).rpc(
        'admin_save_opponent_stadium',
        params: {
          'p_opponent_id': item?.id,
          'p_name': result.name,
          'p_stadium_name': result.stadiumName,
          'p_address': result.address,
        },
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            item == null
                ? 'Équipe ajoutée à la bibliothèque.'
                : 'Équipe et stade mis à jour.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(humanizeError(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(_OpponentStadium item) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Supprimer cette équipe ?'),
            content: Text(
              '« ${item.name} » ne pourra être supprimée que si elle n’est '
              'liée à aucun match actuel ou historique.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton.tonal(
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
      await ref.read(supabaseClientProvider).rpc(
        'admin_delete_unused_opponent',
        params: {'p_opponent_id': item.id},
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Équipe supprimée.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cette équipe possède un historique de matchs : elle est conservée. '
            'Tu peux modifier son nom, son stade ou son adresse.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    return Scaffold(
      appBar: GrintaAppBar(title: const Text('Équipes & stades'), admin: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
          children: [
            TextField(
              controller: _searchController,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Rechercher',
                hintText: 'Équipe, stade ou adresse',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: GrintaProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              )
            else if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Aucune équipe trouvée.'),
                ),
              )
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      leading: const CircleAvatar(
                        child: Icon(Icons.stadium_outlined),
                      ),
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.stadiumName ?? 'Stade non renseigné',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: item.stadiumName == null
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                    : null,
                              ),
                            ),
                            if (item.address != null) ...[
                              const SizedBox(height: 2),
                              Text(item.address!),
                            ] else ...[
                              const SizedBox(height: 2),
                              Text(
                                'Adresse non renseignée',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        enabled: !_saving,
                        onSelected: (value) {
                          if (value == 'edit') _openEditor(item);
                          if (value == 'delete') _delete(item);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Modifier'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_outline),
                              title: Text('Supprimer'),
                            ),
                          ),
                        ],
                      ),
                      onTap: _saving ? null : () => _openEditor(item),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OpponentStadiumEditor extends StatefulWidget {
  const _OpponentStadiumEditor({this.item});

  final _OpponentStadium? item;

  @override
  State<_OpponentStadiumEditor> createState() => _OpponentStadiumEditorState();
}

class _OpponentStadiumEditorState extends State<_OpponentStadiumEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _stadiumController;
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _stadiumController = TextEditingController(
      text: widget.item?.stadiumName ?? '',
    );
    _addressController = TextEditingController(
      text: widget.item?.address ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _stadiumController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.item == null ? 'Nouvelle équipe' : 'Modifier l’équipe',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                autofocus: widget.item == null,
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Équipe',
                  hintText: 'Ex. US Pibrac Loisirs',
                  prefixIcon: Icon(Icons.shield_outlined),
                ),
                validator: (raw) {
                  final value = raw?.trim() ?? '';
                  if (value.length < 2) return 'Nom trop court';
                  if (value.length > 120) return '120 caractères maximum';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _stadiumController,
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Stade / terrain actuel',
                  hintText: 'Ex. Stade de Pibrac',
                  prefixIcon: Icon(Icons.stadium_outlined),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                textCapitalization: TextCapitalization.words,
                keyboardType: TextInputType.multiline,
                minLines: 2,
                maxLines: null,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Adresse',
                  hintText: 'Rue, code postal, ville…',
                  prefixIcon: Icon(Icons.place_outlined),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () {
                  if (!_formKey.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    _OpponentStadiumDraft(
                      name: _nameController.text.trim(),
                      stadiumName: _nullableTrim(_stadiumController.text),
                      address: _nullableTrim(_addressController.text),
                    ),
                  );
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _nullableTrim(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

class _OpponentStadium {
  const _OpponentStadium({
    required this.id,
    required this.name,
    this.stadiumName,
    this.address,
  });

  factory _OpponentStadium.fromJson(Map<String, dynamic> json) {
    return _OpponentStadium(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      stadiumName: _nullableTrim(json['stadium_name']?.toString() ?? ''),
      address: _nullableTrim(json['address']?.toString() ?? ''),
    );
  }

  final String id;
  final String name;
  final String? stadiumName;
  final String? address;
}

class _OpponentStadiumDraft {
  const _OpponentStadiumDraft({
    required this.name,
    required this.stadiumName,
    required this.address,
  });

  final String name;
  final String? stadiumName;
  final String? address;
}
