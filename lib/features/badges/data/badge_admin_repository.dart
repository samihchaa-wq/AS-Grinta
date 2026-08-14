import 'dart:typed_data';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/storage/image_mime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Une personne à qui décerner un badge.
class AdminPerson {
  const AdminPerson({required this.id, required this.name});
  final String id;
  final String name;
}

class BadgeAdminRepository {
  BadgeAdminRepository(this._client);
  final SupabaseClient _client;

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
    final ext = fileExt.isEmpty ? 'jpg' : fileExt.toLowerCase();
    final path = 'custom/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('badge-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: imageMimeForExt(ext),
            // Chaque remplacement utilise un nouveau chemin : le navigateur
            // peut donc conserver l'objet un an sans risque d'afficher une
            // ancienne version après une modification du badge.
            cacheControl: '31536000',
            upsert: false,
          ),
        );
    return _client.storage.from('badge-images').getPublicUrl(path);
  }

  /// Recharge l'image actuellement associée à un badge afin de pouvoir la
  /// recadrer sans demander à l'administrateur de retrouver le fichier source.
  Future<Uint8List> downloadBadgeImage(String imageUrl) async {
    const marker = '/storage/v1/object/public/badge-images/';
    final uri = Uri.parse(imageUrl);
    final markerIndex = uri.path.indexOf(marker);
    if (markerIndex < 0) {
      throw StateError('Image de badge invalide.');
    }

    final encodedPath = uri.path.substring(markerIndex + marker.length);
    final path = Uri.decodeComponent(encodedPath);
    if (path.trim().isEmpty) {
      throw StateError('Chemin d’image de badge invalide.');
    }

    return _client.storage.from('badge-images').download(path);
  }

  /// Remplace uniquement l'image centrale d'un badge existant.
  /// Le JPEG fourni est déjà positionné/zoomé par l'éditeur côté Flutter.
  Future<void> replaceBadgeImage({
    required String badgeCode,
    required Uint8List bytes,
  }) async {
    final imageUrl = await uploadBadgeImage(bytes, 'jpg');
    await _client.rpc('staff_update_badge_image', params: {
      'p_badge_code': badgeCode,
      'p_image_url': imageUrl,
    });
  }

  Future<void> createCustomBadge({
    required String name,
    String description = '',
    String emoji = '🏅',
    String? color,
  }) async {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final code =
        'custom_${slug.isEmpty ? 'badge' : slug}_${DateTime.now().millisecondsSinceEpoch}';
    final trimmedEmoji = emoji.trim();
    await _client.rpc('staff_create_badge', params: {
      'p_code': code,
      'p_name': name,
      'p_emoji': trimmedEmoji.isEmpty ? '🏅' : trimmedEmoji,
      'p_description': description,
      'p_image_url': null,
      'p_color': color ?? '#C0455B',
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

final adminPeopleProvider =
    FutureProvider.autoDispose<List<AdminPerson>>((ref) async {
  return ref.watch(badgeAdminRepositoryProvider).fetchActiveProfiles();
});
