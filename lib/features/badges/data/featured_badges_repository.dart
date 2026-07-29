import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un badge arboré (emblème) affiché à côté d'un prénom.
class FeaturedBadge {
  const FeaturedBadge({
    required this.emoji,
    required this.imageUrl,
    this.color,
    this.baremeLabel,
    this.hasStar = false,
    this.stars = 1,
    this.category,
  });
  final String emoji;
  final String? imageUrl;

  /// Couleur du carré de l'emblème (hex) et seuil du barème, si applicable.
  final String? color;
  final String? baremeLabel;

  /// Étoile posée au-dessus du carré (paliers finaux + titres).
  final bool hasStar;

  /// Nombre d'étoiles (multiples du dernier palier atteint) : 200 buts → 2, etc.
  final int stars;

  /// Catégorie du badge (pour distinguer carrière / saison lors de l'affichage
  /// du chiffre multiplié par les étoiles).
  final String? category;
}

class FeaturedBadgesRepository {
  FeaturedBadgesRepository(this._client);
  final SupabaseClient _client;

  /// Tous les badges arborés, regroupés par profil (max 3 chacun).
  Future<Map<String, List<FeaturedBadge>>> fetchAll() async {
    final rows = await _client.rpc('featured_badges');
    final map = <String, List<FeaturedBadge>>{};
    for (final r in (rows as List? ?? const [])) {
      final m = Map<String, dynamic>.from(r as Map);
      final pid = m['profile_id'].toString();
      (map[pid] ??= []).add(FeaturedBadge(
        emoji: (m['emoji'] ?? '🏅').toString(),
        imageUrl: m['image_url']?.toString(),
        color: m['color']?.toString(),
        baremeLabel: baremeLabelFor(
          m['metric']?.toString(),
          (m['threshold'] as num?)?.toInt(),
        ),
        hasStar: m['has_star'] == true,
        stars: (m['stars'] as num?)?.toInt() ?? 1,
        category: m['category']?.toString(),
      ));
    }
    return map;
  }

  Future<void> setFeatured(String badgeCode, bool featured) async {
    await _client.rpc('set_badge_featured', params: {
      'p_badge_code': badgeCode,
      'p_featured': featured,
    });
  }
}

final featuredBadgesRepositoryProvider =
    Provider<FeaturedBadgesRepository>((ref) {
  return FeaturedBadgesRepository(ref.watch(supabaseClientProvider));
});

/// Cache global des badges arborés (invalidé quand quelqu'un change son choix).
final featuredBadgesProvider =
    FutureProvider<Map<String, List<FeaturedBadge>>>((ref) {
  return ref.watch(featuredBadgesRepositoryProvider).fetchAll();
});

/// Les codes des badges que la personne connectée arbore (pour l'armoire).
final myFeaturedCodesProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final uid = client.auth.currentUser?.id;
  if (uid == null) return <String>{};
  final rows = await client
      .from('profile_badges')
      .select('badges(code)')
      .eq('profile_id', uid)
      .eq('featured', true);
  final codes = <String>{};
  for (final r in rows as List) {
    final b = Map<String, dynamic>.from(r as Map)['badges'];
    final code = b is Map ? b['code']?.toString() : null;
    if (code != null) codes.add(code);
  }
  return codes;
});
