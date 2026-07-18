import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// État d'un badge dans l'armoire.
enum BadgeState { validated, inProgress, locked }

class BadgeDef {
  const BadgeDef({
    required this.code,
    required this.name,
    required this.description,
    required this.emoji,
    required this.imageUrl,
    required this.color,
    required this.family,
    required this.kind,
    required this.category,
    required this.metric,
    required this.threshold,
    required this.sortOrder,
    this.hasStar = false,
    this.standalone = false,
    this.secret = false,
  });

  final String code;
  final String name;
  final String description;
  final String emoji;
  final String? imageUrl;

  /// Couleur du carré de l'emblème (hex `#RRGGBB`).
  final String? color;
  final String family;

  /// 'tier' | 'title' | 'custom'
  final String kind;

  /// 'all_time' | 'saison' | 'faits_de_jeu' | 'pronos'
  final String category;
  final String? metric;
  final int? threshold;
  final int sortOrder;

  /// Étoile posée au-dessus du carré (paliers finaux + titres).
  final bool hasStar;

  /// Badge « exploit » autonome (ex. Triplé/Quadruplé/Quintuplé) : affiché seul,
  /// sans barème gradué ni barre de progression.
  final bool standalone;

  /// Badge secret : masqué (« ??? » dans « À débloquer ») tant qu'il n'est pas
  /// gagné. Une fois obtenu, il apparaît normalement dans « Validés ».
  final bool secret;

  factory BadgeDef.fromMap(Map<String, dynamic> m) => BadgeDef(
        code: m['code'].toString(),
        name: (m['name'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        emoji: (m['emoji'] ?? '🏅').toString(),
        imageUrl: m['image_url']?.toString(),
        color: m['color']?.toString(),
        family: (m['family'] ?? 'joueur').toString(),
        kind: (m['kind'] ?? 'tier').toString(),
        category: (m['category'] ?? 'all_time').toString(),
        metric: m['metric']?.toString(),
        threshold: (m['threshold'] as num?)?.toInt(),
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        hasStar: m['has_star'] == true,
        standalone: m['standalone'] == true,
        secret: m['secret'] == true,
      );
}

/// Une entrée de l'armoire : un badge + son état pour la personne.
class ArmoireBadge {
  const ArmoireBadge({
    required this.def,
    required this.state,
    this.current,
    this.target,
    this.awardedAt,
    this.stars = 1,
  });

  final BadgeDef def;
  final BadgeState state;

  /// Pour « en cours » : valeur actuelle et seuil visé.
  final int? current;
  final int? target;
  final DateTime? awardedAt;

  /// Nombre d'étoiles à afficher au-dessus de l'emblème (paliers étoilés
  /// rejouables : une étoile par saison / titre gagné). 1 par défaut.
  final int stars;

  double? get progress => (current != null && target != null && target! > 0)
      ? (current! / target!).clamp(0.0, 1.0)
      : null;

  int? get remaining =>
      (current != null && target != null) ? (target! - current!) : null;
}

class Armoire {
  const Armoire({
    required this.validated,
    required this.inProgress,
    required this.locked,
  });

  final List<ArmoireBadge> validated;
  final List<ArmoireBadge> inProgress;
  final List<ArmoireBadge> locked;

  /// Aperçu pour l'accueil : les badges validés les plus récents.
  List<ArmoireBadge> get recent {
    final sorted = [...validated]..sort((a, b) =>
        (b.awardedAt ?? DateTime(0)).compareTo(a.awardedAt ?? DateTime(0)));
    return sorted;
  }
}

class BadgeRepository {
  BadgeRepository(this._client);

  final SupabaseClient _client;

  Future<List<BadgeDef>> fetchCatalog() async {
    final rows = await _client
        .from('badges')
        .select(
            'code,name,description,emoji,image_url,color,family,kind,category,metric,threshold,sort_order,has_star,standalone,secret')
        .order('sort_order');
    return (rows as List)
        .map((r) => BadgeDef.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<Armoire> fetchArmoire(String profileId) async {
    final catalog = await fetchCatalog();

    // Badges directement attribués (paliers + custom).
    final earnedRows = await _client
        .from('profile_badges')
        .select('badge_id, awarded_at, featured, badges(code)')
        .eq('profile_id', profileId);
    final earnedAt = <String, DateTime>{};
    final featuredCodes = <String>{};
    for (final r in earnedRows as List) {
      final m = Map<String, dynamic>.from(r as Map);
      final b = m['badges'];
      final code = b is Map ? b['code']?.toString() : null;
      if (code != null) {
        earnedAt[code] =
            DateTime.tryParse(m['awarded_at']?.toString() ?? '') ?? DateTime(0);
        if (m['featured'] == true) featuredCodes.add(code);
      }
    }
    final byCode = {for (final b in catalog) b.code: b};

    // Valeurs de stats courantes (pour la progression).
    final metricsRes = await _client
        .rpc('profile_badge_metrics', params: {'p_profile_id': profileId});
    final metrics = <String, int>{};
    if (metricsRes is List && metricsRes.isNotEmpty) {
      final m = Map<String, dynamic>.from(metricsRes.first as Map);
      for (final k in m.keys) {
        metrics[k] = (m[k] as num?)?.toInt() ?? 0;
      }
    }

    // Nombre d'étoiles par badge : un palier étoilé ré-atteint (nouvelle saison,
    // titre regagné) ajoute une étoile. 1 par défaut pour les paliers carrière.
    final starsRes = await _client
        .rpc('profile_badge_stars', params: {'p_profile_id': profileId});
    final starCounts = <String, int>{};
    if (starsRes is List) {
      for (final r in starsRes) {
        final m = Map<String, dynamic>.from(r as Map);
        final code = m['badge_code']?.toString();
        final n = (m['stars'] as num?)?.toInt() ?? 1;
        if (code != null && n > 0) starCounts[code] = n;
      }
    }

    final validated = <ArmoireBadge>[];
    final inProgress = <ArmoireBadge>[];
    final locked = <ArmoireBadge>[];

    // Paliers : par métrique, on montre le palier validé le plus haut + le
    // suivant « en cours » avec sa progression.
    // Les badges « standalone » (exploits autonomes) forment chacun leur propre
    // groupe (clé = code), donc ils s'affichent séparément, sans barème gradué.
    final byMetric = <String, List<BadgeDef>>{};
    for (final b
        in catalog.where((b) => b.kind == 'tier' && b.metric != null)) {
      final key = b.standalone ? 'code:${b.code}' : b.metric!;
      byMetric.putIfAbsent(key, () => []).add(b);
    }
    byMetric.forEach((groupKey, tiers) {
      tiers.sort((a, b) => (a.threshold ?? 0).compareTo(b.threshold ?? 0));
      final metric = tiers.first.metric!;
      final value = metrics[metric] ?? 0;
      // Barème à un seul palier (titres, exploits autonomes) : pas de barre de
      // progression ni de compteur « 0/1 · plus que 1 ».
      final singleTier = tiers.length == 1;
      // Un palier est « validé » dès qu'il a été GAGNÉ (ligne profile_badges),
      // et le reste à vie — même si la stat de la saison est retombée. On
      // affiche le plus haut palier gagné + le premier palier pas encore gagné
      // « en cours ».
      BadgeDef? highestOwned;
      BadgeDef? nextUnowned;
      for (final t in tiers) {
        if (earnedAt.containsKey(t.code)) {
          highestOwned = t;
        } else {
          nextUnowned ??= t;
        }
      }
      if (highestOwned != null) {
        validated.add(ArmoireBadge(
          def: highestOwned,
          state: BadgeState.validated,
          awardedAt: earnedAt[highestOwned.code],
          stars: starCounts[highestOwned.code] ?? 1,
        ));
      }
      if (nextUnowned != null) {
        if (nextUnowned.secret) {
          // Badge secret pas encore gagné : reste masqué (« ??? ») dans la
          // section « À débloquer », sans dévoiler son nom ni sa condition.
          locked.add(ArmoireBadge(def: nextUnowned, state: BadgeState.locked));
        } else {
          inProgress.add(ArmoireBadge(
            def: nextUnowned,
            state: BadgeState.inProgress,
            current: singleTier ? null : value,
            target: singleTier ? null : nextUnowned.threshold,
          ));
        }
      }
    });

    // Titres et badges custom : acquis une seule fois, à vie.
    for (final b in catalog.where((b) => b.kind != 'tier')) {
      if (earnedAt.containsKey(b.code)) {
        validated.add(ArmoireBadge(
          def: b,
          state: BadgeState.validated,
          awardedAt: earnedAt[b.code],
          stars: starCounts[b.code] ?? 1,
        ));
      } else {
        locked.add(ArmoireBadge(def: b, state: BadgeState.locked));
      }
    }

    // Badges arborés qui ne sont plus dans le palier courant (ex. un badge
    // saisonnier après un changement de saison) : on les garde visibles dans
    // « Validés » pour que la personne puisse toujours les voir et les retirer.
    final shownCodes = {for (final v in validated) v.def.code};
    for (final code in featuredCodes) {
      if (shownCodes.contains(code)) continue;
      final def = byCode[code];
      if (def == null) continue;
      validated.add(ArmoireBadge(
        def: def,
        state: BadgeState.validated,
        awardedAt: earnedAt[code],
        stars: starCounts[code] ?? 1,
      ));
    }

    validated.sort((a, b) => a.def.sortOrder.compareTo(b.def.sortOrder));
    inProgress.sort((a, b) => a.def.sortOrder.compareTo(b.def.sortOrder));
    locked.sort((a, b) => a.def.sortOrder.compareTo(b.def.sortOrder));

    return Armoire(
        validated: validated, inProgress: inProgress, locked: locked);
  }
}

final badgeRepositoryProvider = Provider<BadgeRepository>((ref) {
  return BadgeRepository(ref.watch(supabaseClientProvider));
});

/// Catalogue complet des badges (tous les paliers, titres, exploits).
final badgeCatalogProvider =
    FutureProvider.autoDispose<List<BadgeDef>>((ref) async {
  return ref.watch(badgeRepositoryProvider).fetchCatalog();
});

/// Armoire de la personne connectée.
final myArmoireProvider = FutureProvider.autoDispose<Armoire>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final uid = client.auth.currentUser?.id;
  if (uid == null) {
    return const Armoire(validated: [], inProgress: [], locked: []);
  }
  return ref.watch(badgeRepositoryProvider).fetchArmoire(uid);
});
