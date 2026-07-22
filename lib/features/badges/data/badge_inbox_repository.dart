import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BadgeInboxRepository {
  BadgeInboxRepository(this._client);

  final SupabaseClient _client;

  Future<bool> hasUnseenBadge() async {
    final profileId = _client.auth.currentUser?.id;
    if (profileId == null) return false;

    final latestAward = await _client
        .from('profile_badges')
        .select('awarded_at')
        .eq('profile_id', profileId)
        .order('awarded_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final latestAwardedAt = DateTime.tryParse(
      latestAward?['awarded_at']?.toString() ?? '',
    );

    final state = await _client
        .from('badge_inbox_state')
        .select('seen_through')
        .eq('profile_id', profileId)
        .maybeSingle();
    final seenThrough = DateTime.tryParse(
      state?['seen_through']?.toString() ?? '',
    );

    if (seenThrough == null) {
      await _client.from('badge_inbox_state').upsert({
        'profile_id': profileId,
        'seen_through': (latestAwardedAt ?? DateTime.now().toUtc())
            .toUtc()
            .toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return false;
    }

    return latestAwardedAt != null && latestAwardedAt.isAfter(seenThrough);
  }

  Future<void> markSeen() async {
    final profileId = _client.auth.currentUser?.id;
    if (profileId == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('badge_inbox_state').upsert({
      'profile_id': profileId,
      'seen_through': now,
      'updated_at': now,
    });
  }
}

final badgeInboxRepositoryProvider = Provider<BadgeInboxRepository>((ref) {
  return BadgeInboxRepository(ref.watch(supabaseClientProvider));
});

final hasUnseenBadgeProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(badgeInboxRepositoryProvider).hasUnseenBadge();
});
