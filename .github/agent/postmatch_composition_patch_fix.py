from pathlib import Path

page = Path('lib/features/sports_management/presentation/admin_squad_plan_page.dart')
text = page.read_text()
text = text.replace('  SportMatchFinalization? _finalization;\n', '')
text = text.replace('        _finalization = finalization;\n', '')
text = text.replace(
    '? _normalizePostMatchComposition(finalization!, saved)',
    '? _normalizePostMatchComposition(finalization, saved)',
)
text = text.replace(
    "      final actualPresent = {\n",
    "      final actualPresent = <String>{\n",
)
page.write_text(text)

published_test = Path('test/published_lineup_card_test.dart')
text = published_test.read_text()
needle = """  @override
  Future<MatchComposition> publishComposition({
"""
replacement = """  @override
  Future<MatchComposition> createPostMatchComposition({
    required MatchComposition composition,
    required bool allowSquadSizeException,
    String? reason,
  }) async {
    return composition;
  }

  @override
  Future<MatchComposition> publishComposition({
"""
if needle not in text:
    raise SystemExit('Fake composition repository insertion point not found')
published_test.write_text(text.replace(needle, replacement, 1))
