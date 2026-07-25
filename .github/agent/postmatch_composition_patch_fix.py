from pathlib import Path

page = Path('lib/features/sports_management/presentation/admin_squad_plan_page.dart')
text = page.read_text()
text = text.replace('  SportMatchFinalization? _finalization;\n', '')
text = text.replace('        _finalization = finalization;\n', '')
text = text.replace(
    '? _normalizePostMatchComposition(finalization, saved)',
    '? _normalizePostMatchComposition(finalization!, saved)',
)
page.write_text(text)
