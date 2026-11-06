import 'dart:convert';

import 'package:as_grinta/core/storage/profile_photo_urls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ProfilePhotoUrlCache.instance.clear();
  });

  group('storagePath', () {
    test('un chemin relatif est renvoyé tel quel', () {
      expect(
        ProfilePhotoUrlCache.storagePath('season/abc/avatar_1.png'),
        'season/abc/avatar_1.png',
      );
    });

    test('les barres de tête sont retirées', () {
      expect(
        ProfilePhotoUrlCache.storagePath('/profil/avatar_1.png'),
        'profil/avatar_1.png',
      );
    });

    test('une ancienne URL Supabase complète redonne son chemin', () {
      expect(
        ProfilePhotoUrlCache.storagePath(
          'https://exemple.supabase.co/storage/v1/object/public/'
          'profile-photos/season/abc/avatar%201.png',
        ),
        'season/abc/avatar 1.png',
      );
    });

    test('une URL externe n’a pas de chemin de stockage', () {
      expect(
        ProfilePhotoUrlCache.storagePath('https://exemple.test/photo.png'),
        isNull,
      );
    });

    test('une valeur vide n’a pas de chemin de stockage', () {
      expect(ProfilePhotoUrlCache.storagePath('   '), isNull);
      expect(ProfilePhotoUrlCache.storagePath(null), isNull);
    });
  });

  group('cache', () {
    test('une URL externe est affichable sans signature', () async {
      const external = 'https://exemple.test/photo.png';
      expect(ProfilePhotoUrlCache.instance.cached(external), external);
      expect(await ProfilePhotoUrlCache.instance.resolve(external), external);
    });

    test('une valeur vide ne donne aucune URL', () async {
      expect(ProfilePhotoUrlCache.instance.cached(''), isNull);
      expect(await ProfilePhotoUrlCache.instance.resolve(null), isNull);
    });

    test('une URL encore valide survit au redémarrage', () async {
      final expiresAt = DateTime.now().add(const Duration(hours: 6));
      SharedPreferences.setMockInitialValues(<String, Object>{
        profilePhotoSignedUrlsPrefsKey: jsonEncode(<String, dynamic>{
          'season/abc/avatar_1.png': <String, dynamic>{
            'url': 'https://exemple.supabase.co/signed/abc',
            'expires_at': expiresAt.toIso8601String(),
          },
        }),
      });

      await ProfilePhotoUrlCache.instance.warmUp();

      expect(
        ProfilePhotoUrlCache.instance.cached('season/abc/avatar_1.png'),
        'https://exemple.supabase.co/signed/abc',
      );
      expect(
        await ProfilePhotoUrlCache.instance.resolve('season/abc/avatar_1.png'),
        'https://exemple.supabase.co/signed/abc',
      );
    });

    test('une URL expirée n’est pas réutilisée', () async {
      final expiredAt = DateTime.now().subtract(const Duration(minutes: 1));
      SharedPreferences.setMockInitialValues(<String, Object>{
        profilePhotoSignedUrlsPrefsKey: jsonEncode(<String, dynamic>{
          'season/abc/avatar_1.png': <String, dynamic>{
            'url': 'https://exemple.supabase.co/signed/perime',
            'expires_at': expiredAt.toIso8601String(),
          },
        }),
      });

      await ProfilePhotoUrlCache.instance.warmUp();

      expect(
        ProfilePhotoUrlCache.instance.cached('season/abc/avatar_1.png'),
        isNull,
      );
    });

    test('un cache disque illisible ne fait pas échouer la lecture', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        profilePhotoSignedUrlsPrefsKey: 'ceci-nest-pas-du-json',
      });

      await ProfilePhotoUrlCache.instance.warmUp();

      expect(
        ProfilePhotoUrlCache.instance.cached('season/abc/avatar_1.png'),
        isNull,
      );
    });

    test('la déconnexion efface les URLs signées', () async {
      final expiresAt = DateTime.now().add(const Duration(hours: 6));
      SharedPreferences.setMockInitialValues(<String, Object>{
        profilePhotoSignedUrlsPrefsKey: jsonEncode(<String, dynamic>{
          'profil/avatar_1.png': <String, dynamic>{
            'url': 'https://exemple.supabase.co/signed/profil',
            'expires_at': expiresAt.toIso8601String(),
          },
        }),
      });
      await ProfilePhotoUrlCache.instance.warmUp();
      expect(
        ProfilePhotoUrlCache.instance.cached('profil/avatar_1.png'),
        isNotNull,
      );

      await ProfilePhotoUrlCache.instance.clear();

      expect(
        ProfilePhotoUrlCache.instance.cached('profil/avatar_1.png'),
        isNull,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(profilePhotoSignedUrlsPrefsKey), isNull);
    });
  });
}
