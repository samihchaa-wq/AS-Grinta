from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, found {count}")
    file.write_text(text.replace(old, new, 1))


replace_once(
    "lib/app/shell/app_shell.dart",
    """  /// Seuls les 4 onglets principaux affichent la barre du bas. Les autres écrans
  /// (Paramètres, Armoire, Profil, Admin, détail de match…) sont des pages
  /// poussées, en plein écran avec un bouton retour.
  bool get _isMainTab {
    final p = _uri.path;
    return p == '/accueil' || p == '/pronos' || p == '/statistics';
  }

  int get _selectedIndex {
    if (_uri.path == '/statistics') return 3;
    if (_uri.path == '/pronos') {
      return switch (_uri.queryParameters['category']) {
        'general' || 'scorers' => 2,
        _ => 1,
      };
    }
    return 0;
  }
""",
    """  int get _selectedIndex {
    final path = _uri.path;
    if (path == '/statistics') return 3;
    if (path == '/pronos') {
      return switch (_uri.queryParameters['category']) {
        'general' || 'scorers' => 2,
        _ => 1,
      };
    }
    if (path.startsWith('/matches') || path.startsWith('/predictions')) {
      return 1;
    }
    return 0;
  }
""",
)
replace_once(
    "lib/app/shell/app_shell.dart",
    """  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isMainTab) return child;

    return Scaffold(
""",
    """  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
""",
)

replace_once(
    "lib/features/sports_management/presentation/admin_squad_plan_page.dart",
    """import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/sports_management/data/guest_players_repository.dart';
""",
    """import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/features/predictions/presentation/widgets/inline_match_prediction_card.dart';
import 'package:as_grinta/features/sports_management/data/guest_players_repository.dart';
""",
)
replace_once(
    "lib/features/sports_management/presentation/admin_squad_plan_page.dart",
    "enum _AdminStep { effectif, composition }",
    "enum _AdminStep { effectif, composition, prediction }",
)
replace_once(
    "lib/features/sports_management/presentation/admin_squad_plan_page.dart",
    """class AdminSquadPlanPage extends ConsumerStatefulWidget {
  const AdminSquadPlanPage({super.key, this.initialMatchId, this.initialStep});

  final String? initialMatchId;
  final String? initialStep;
""",
    """class AdminSquadPlanPage extends ConsumerStatefulWidget {
  const AdminSquadPlanPage({
    super.key,
    this.initialMatchId,
    this.initialStep,
    this.showPredictionStep = false,
  });

  final String? initialMatchId;
  final String? initialStep;
  final bool showPredictionStep;
""",
)
replace_once(
    "lib/features/sports_management/presentation/admin_squad_plan_page.dart",
    """  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedMatchId = widget.initialMatchId;
    _step = widget.initialStep == 'composition'
        ? _AdminStep.composition
        : _AdminStep.effectif;
    _limitController = TextEditingController(text: '14');
    Future.microtask(_loadMatches);
  }

  @override
  void dispose() {
""",
    """  String? _error;

  _AdminStep _stepFrom(String? value) {
    if (widget.showPredictionStep && value == 'prediction') {
      return _AdminStep.prediction;
    }
    if (value == 'composition') return _AdminStep.composition;
    return _AdminStep.effectif;
  }

  @override
  void initState() {
    super.initState();
    _selectedMatchId = widget.initialMatchId;
    _step = _stepFrom(widget.initialStep);
    _limitController = TextEditingController(text: '14');
    Future.microtask(_loadMatches);
  }

  @override
  void didUpdateWidget(covariant AdminSquadPlanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStep != widget.initialStep ||
        oldWidget.showPredictionStep != widget.showPredictionStep) {
      _step = _stepFrom(widget.initialStep);
    }
  }

  @override
  void dispose() {
""",
)
replace_once(
    "lib/features/sports_management/presentation/admin_squad_plan_page.dart",
    """          SegmentedButton<_AdminStep>(
            segments: const [
              ButtonSegment(
                value: _AdminStep.effectif,
                icon: Icon(Icons.groups_2_outlined),
                label: Text('Effectif'),
              ),
              ButtonSegment(
                value: _AdminStep.composition,
                icon: Icon(Icons.sports_soccer_outlined),
                label: Text('Composition'),
              ),
            ],
""",
    """          SegmentedButton<_AdminStep>(
            segments: [
              const ButtonSegment(
                value: _AdminStep.effectif,
                icon: Icon(Icons.groups_2_outlined),
                label: Text('Effectif'),
              ),
              const ButtonSegment(
                value: _AdminStep.composition,
                icon: Icon(Icons.sports_soccer_outlined),
                label: Text('Composition'),
              ),
              if (widget.showPredictionStep)
                const ButtonSegment(
                  value: _AdminStep.prediction,
                  icon: Icon(Icons.sports_score_outlined),
                  label: Text('Ton pari'),
                ),
            ],
""",
)
replace_once(
    "lib/features/sports_management/presentation/admin_squad_plan_page.dart",
    """          if (_convocations != null && _composition != null)
            _step == _AdminStep.effectif
                ? _buildEffectif()
                : _buildComposition(),
""",
    """          if (_step == _AdminStep.prediction && _selectedMatchId != null)
            InlineMatchPredictionCard(matchId: _selectedMatchId!)
          else if (_convocations != null && _composition != null)
            _step == _AdminStep.effectif
                ? _buildEffectif()
                : _buildComposition(),
""",
)

match_lineup = Path(
    "lib/features/sports_management/presentation/match_lineup_page.dart"
)
text = match_lineup.read_text()
old = """    if (isAdmin) {
      return _AdminMatchWorkspace(matchId: matchId, section: section);
    }
"""
new = """    if (isAdmin) {
      return AdminSquadPlanPage(
        initialMatchId: matchId,
        initialStep: section,
        showPredictionStep: true,
      );
    }
"""
if text.count(old) != 1:
    raise SystemExit("match_lineup_page.dart: admin workspace call mismatch")
text = text.replace(old, new, 1)
text, count = re.subn(
    r"\nclass _AdminMatchWorkspace[\s\S]*?(?=\nclass PublishedLineupCard)",
    "",
    text,
    count=1,
)
if count != 1:
    raise SystemExit("match_lineup_page.dart: admin workspace class mismatch")
match_lineup.write_text(text)

replace_once("web/index.html", "sw.js?v=67", "sw.js?v=68")
replace_once(
    "web/index.html",
    "flutter_bootstrap.js?v=67",
    "flutter_bootstrap.js?v=68",
)
replace_once(
    "web/sw.js",
    "Cache fonctionnel v67 — fiches de match, pari et vote HDM.",
    "Cache fonctionnel v68 — navigation principale persistante.",
)
replace_once(
    "web/sw.js",
    "const CACHE_NAME = 'as-grinta-v67';",
    "const CACHE_NAME = 'as-grinta-v68';",
)
