from pathlib import Path

path = Path('lib/features/sports_management/presentation/admin_squad_plan_page.dart')
text = path.read_text()

old_import = "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
new_import = old_import + "import 'package:go_router/go_router.dart';\n"
if "package:go_router/go_router.dart" not in text:
    if old_import not in text:
        raise SystemExit('Riverpod import not found')
    text = text.replace(old_import, new_import, 1)

old_getter = """  bool get _compositionLocked =>
      _busy || (_postMatch ? _compositionExisted : _locked);

"""
new_getter = """  bool get _compositionLocked =>
      _busy || (_postMatch ? _compositionExisted : _locked);

  bool get _canConsultWaitlist {
    final convocations = _convocations;
    if (convocations == null || !convocations.isPublished) return false;
    final untilKickoff = convocations.kickoffAt.difference(DateTime.now());
    return !untilKickoff.isNegative && untilKickoff <= const Duration(days: 6);
  }

"""
if "bool get _canConsultWaitlist" not in text:
    if old_getter not in text:
        raise SystemExit('Composition lock getter not found')
    text = text.replace(old_getter, new_getter, 1)

old_layout = """        const SizedBox(height: 14),
        LayoutBuilder(
"""
new_layout = """        const SizedBox(height: 14),
        if (_canConsultWaitlist) ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : () => context.push('/admin/waitlist'),
            icon: const Icon(Icons.format_list_numbered_rounded),
            label: const Text('Consulter la liste d’attente'),
          ),
          const SizedBox(height: 14),
        ],
        LayoutBuilder(
"""
if "Consulter la liste d’attente" not in text:
    if old_layout not in text:
        raise SystemExit('Effectif columns layout not found')
    text = text.replace(old_layout, new_layout, 1)

path.write_text(text)
