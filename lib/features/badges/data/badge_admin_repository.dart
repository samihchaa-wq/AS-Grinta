import 'dart:typed_data';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un badge tel que vu par l'admin (pour la liste et l'attribution).
class AdminBadge {
  const AdminBadge({
    required this.code,
    required this.name,
    required this.emoji,
    required this.imageUrl,
    required this.kind,
    required this.family,
  });

  final String code;
  final String name;
  final String emoji;
  final String? imageUrl;

  /// 'tier' | 'title' | 'custom'
  final String kind;
  final String family;

  bool get isCustom => kind == 'custom';
}

/// Une personne à qui décerner un badge.
class AdminPerson {
  const AdminPerson({required this.id, required this.name});
  final String id;
  final String name;
}

class BadgeAdminRepository {
  BadgeAdminRepository(this._client);
  final SupabaseClient _client;

  Future<List<AdminBadge>> fetchBadges() async {
    final rows = await _client
        .from('badges')
        .select('code,name,emoji,image_url,kind,family')
        .order('sort_order');
    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return AdminBadge(
        code: m['code'].toString(),
        name: (m['name'] ?? '').toString(),
        emoji: (m['emoji'] ?? '🏅').toString(),
        imageUrl: m['image_url']?.toString(),
        kind: (m['kind'] ?? 'tier').toString(),
        family: (m['family'] ?? 'joueur').toString(),
      );
    }).toList();
  }

  Future<List<AdminPerson>> fetchActiveProfiles() async {
    final res = await _client.rpc('staff_list_profiles');
    final people = <AdminPerson>[];
    for (final r in (res as List? ?? const [])) {
      final m = Map<String, dynamic>.from(r as Map);
      if ((m['status'] ?? 'active').toString() != 'active') continue;
      final surnom = (m['surnom'] ?? '').toString().trim();
      final first = (m['first_name'] ?? '').toString().trim();
      final name = surnom.isNotEmpty
          ? surnom
          : (first.isNotEmpty ? first : 'Compte sans nom');
      people.add(AdminPerson(id: m['id'].toString(), name: name));
    }
    people.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return people;
  }

  /// Les profils qui possèdent déjà ce badge.
  Future<Set<String>> fetchAwardees(String badgeCode) async {
    final badge = await _client
        .from('badges')
        .select('id')
        .eq('code', badgeCode)
        .maybeSingle();
    if (badge == null) return {};
    final rows = await _client
        .from('profile_badges')
        .select('profile_id')
        .eq('badge_id', badge['id']);
    return {
      for (final r in rows as List)
        Map<String, dynamic>.from(r as Map)['profile_id'].toString(),
    };
  }

  /// Téléverse une image de badge et renvoie son URL publique.
  Future<String> uploadBadgeImage(Uint8List bytes, String fileExt) async {
    final ext = fileExt.isEmpty ? 'png' : fileExt.toLowerCase();
    final path = 'custom/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('badge-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: 'image/$ext',
            upsert: true,
          ),
        );
    return _client.storage.from('badge-images').getPublicUrl(path);
  }

  Future<void> createCustomBadge({
    required String name,
    String description = '',
    String? imageUrl,
  }) async {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final code =
        'custom_${slug.isEmpty ? 'badge' : slug}_${DateTime.now().millisecondsSinceEpoch}';
    await _client.rpc('staff_create_badge', params: {
      'p_code': code,
      'p_name': name,
      'p_emoji': '🏅',
      'p_description': description,
      'p_image_url': imageUrl,
    });
  }

  Future<void> awardBadge(String code, String profileId) async {
    await _client.rpc('staff_award_badge', params: {
      'p_profile_id': profileId,
      'p_badge_code': code,
    });
  }

  Future<void> revokeBadge(String code, String profileId) async {
    await _client.rpc('staff_revoke_badge', params: {
      'p_profile_id': profileId,
      'p_badge_code': code,
    });
  }
}

final badgeAdminRepositoryProvider = Provider<BadgeAdminRepository>((ref) {
  return BadgeAdminRepository(ref.watch(supabaseClientProvider));
});

final adminBadgesProvider =
    FutureProvider.autoDispose<List<AdminBadge>>((ref) async {
  return ref.watch(badgeAdminRepositoryProvider).fetchBadges();
});

final adminPeopleProvider =
    FutureProvider.autoDispose<List<AdminPerson>>((ref) async {
  return ref.watch(badgeAdminRepositoryProvider).fetchActiveProfiles();
});
