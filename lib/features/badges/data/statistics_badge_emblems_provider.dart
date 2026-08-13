import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/features/badges/presentation/badge_emblem.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final String descriptor;
  final bool hasStar;
  final int stars;
  final String? category;
}

final statisticsBadgeEmblemsProvider =
    FutureProvider<Map<String, List<StatisticsBadgeEmblemData>>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client.rpc('featured_badges');
  final result = <String, List<StatisticsBadgeEmblemData>>{};

  for (final raw in (rows as List? ?? const [])) {
    final row = Map<String, dynamic>.from(raw as Map);
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
        ),
        hasStar: row['has_star'] == true,
        stars: (row['stars'] as num?)?.toInt() ?? 1,
        category: category,
      ),
    );
  }
  return result;
});
