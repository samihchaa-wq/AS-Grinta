import 'dart:typed_data';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/storage/image_mime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Une personne à qui décerner un badge.
class AdminPerson {
  const AdminPerson({
    required this.id,
    required this.name,
    this.isGoalkeeper = false,
  });
  final String id;
  final String name;
  final bool isGoalkeeper;
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
      people.add(
        AdminPerson(
          id: m['id'].toString(),
          name: name,
          isGoalkeeper: m['is_goalkeeper'] == true,
        ),
      );
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
    await _client.storage
        .from('badge-images')
        .uploadBinary(
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

  String _badgeImagePathFromPublicUrl(String imageUrl) {
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
    return path;
  }

  Future<void> _removeUploadedBadgeImage(String imageUrl) async {
    final path = _badgeImagePathFromPublicUrl(imageUrl);
    await _client.storage.from('badge-images').remove([path]);
  }

  /// Recharge l'image actuellement associée à un badge afin de pouvoir la
  /// recadrer sans demander à l'administrateur de retrouver le fichier source.
  Future<Uint8List> downloadBadgeImage(String imageUrl) async {
    final path = _badgeImagePathFromPublicUrl(imageUrl);
    return _client.storage.from('badge-images').download(path);
  }

  /// Remplace uniquement l'image centrale d'un badge existant.
  /// Le JPEG fourni est déjà positionné/zoomé par l'éditeur côté Flutter.
  Future<void> replaceBadgeImage({
    required String badgeCode,
    required Uint8List bytes,
  }) async {
    final imageUrl = await uploadBadgeImage(bytes, 'jpg');
    await _client.rpc(
      'staff_update_badge_image',
      params: {'p_badge_code': badgeCode, 'p_image_url': imageUrl},
    );
  }

  /// Crée un badge manuel directement avec son illustration finale.
  ///
  /// Le visuel est téléversé avant la RPC afin que la ligne `badges` soit créée
  /// d'un seul coup avec son image. Si la création SQL échoue, le fichier tout
  /// juste envoyé est supprimé en compensation pour éviter un objet orphelin.
  Future<void> createCustomBadge({
    required String name,
    required Uint8List imageBytes,
    String description = '',
    String? color,
  }) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError.value(imageBytes, 'imageBytes', 'Image requise');
    }

    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final code =
        'custom_${slug.isEmpty ? 'badge' : slug}_${DateTime.now().millisecondsSinceEpoch}';

    final imageUrl = await uploadBadgeImage(imageBytes, 'jpg');
    try {
      await _client.rpc(
        'staff_create_badge',
        params: {
          'p_code': code,
          'p_name': name,
          'p_emoji': '🏅',
          'p_description': description,
          'p_image_url': imageUrl,
          'p_color': color ?? '#C0455B',
        },
      );
    } catch (_) {
      try {
        await _removeUploadedBadgeImage(imageUrl);
      } catch (_) {
        // La création reste l'erreur principale. Le nettoyage du bucket est
        // compensatoire et ne doit jamais masquer l'échec SQL d'origine.
      }
      rethrow;
    }
  }

  Future<void> awardBadge(String code, String profileId) async {
    await _client.rpc(
      'staff_award_badge',
      params: {'p_profile_id': profileId, 'p_badge_code': code},
    );
  }

  Future<void> revokeBadge(String code, String profileId) async {
    await _client.rpc(
      'staff_revoke_badge',
      params: {'p_profile_id': profileId, 'p_badge_code': code},
    );
  }
}

final badgeAdminRepositoryProvider = Provider<BadgeAdminRepository>((ref) {
  return BadgeAdminRepository(ref.watch(supabaseClientProvider));
});

final adminPeopleProvider = FutureProvider.autoDispose<List<AdminPerson>>((
  ref,
) async {
  return ref.watch(badgeAdminRepositoryProvider).fetchActiveProfiles();
});
