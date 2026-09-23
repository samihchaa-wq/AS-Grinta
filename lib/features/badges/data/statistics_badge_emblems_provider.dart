import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StatisticsBadgeEmblemData {
  const StatisticsBadgeEmblemData({
    required this.emoji,
    required this.imageUrl,
    required this.color,
    required this.valueLabel,
    required this.descriptor,
    required this.hasStar,
    required this.stars,
    required this.category,
  });

  final String emoji;
  final String? imageUrl;
  final String? color;
  final String? valueLabel;
  final BadgeDescriptor descriptor;
  final bool hasStar;
  final int stars;
  final String? category;
}

final statisticsBadgeEmblemsProvider =
    FutureProvider<Map<String, List<StatisticsBadgeEmblemData>>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client.rpc('featured_badges');
  final featured = [
    for (final raw in (rows as List? ?? const []))
      Map<String, dynamic>.from(raw as Map),
  ];
  final customNames = await _customBadgeNames(client, {
    for (final row in featured)
      if (row['code']?.toString().startsWith('custom_') == true)
        row['code'].toString(),
  });
  final result = <String, List<StatisticsBadgeEmblemData>>{};

  for (final row in featured) {
    final profileId = row['profile_id'].toString();
    final metric = row['metric']?.toString();
    final category = row['category']?.toString();
    final code = row['code']?.toString();
    (result[profileId] ??= []).add(
      StatisticsBadgeEmblemData(
        emoji: (row['emoji'] ?? '🏅').toString(),
        imageUrl: row['image_url']?.toString(),
        color: row['color']?.toString(),
        valueLabel: baremeLabelFor(
          metric,
          (row['display_value'] as num?)?.toInt(),
        ),
        descriptor: badgeDescriptorFor(
          code: code,
          metric: metric,
          category: category,
          name: customNames[code],
        ),
        hasStar: row['has_star'] == true,
        stars: (row['stars'] as num?)?.toInt() ?? 1,
        category: category,
      ),
    );
  }
  return result;
});

/// Le socle d'un badge mystère porte son nom, que `featured_badges` ne renvoie
/// pas. Il est donc lu à part, et seulement quand un badge mystère est arboré.
/// En cas d'échec, l'emblème garde sa mention générique plutôt que de priver
/// tout le tableau de ses badges.
Future<Map<String, String>> _customBadgeNames(
  SupabaseClient client,
  Set<String> codes,
) async {
  if (codes.isEmpty) return const {};
  try {
    final rows = await client
        .from('badges')
        .select('code,name')
        .inFilter('code', codes.toList());
    final names = <String, String>{};
    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final name = row['name']?.toString();
      if (name != null) names[row['code'].toString()] = name;
    }
    return names;
  } catch (_) {
    return const {};
  }
}
