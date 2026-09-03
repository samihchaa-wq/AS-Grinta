import 'dart:async';
import 'dart:convert';

import 'package:as_grinta/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Durée de vie demandée pour une URL signée de photo de profil.
///
/// Le bucket `profile-photos` est privé : chaque affichage a besoin d'une URL
/// signée. Une durée longue permet de réutiliser la même URL pendant toute la
/// session — et donc de laisser le cache image de Flutter et celui du
/// navigateur faire leur travail au lieu de retélécharger la photo à chaque
/// écran.
const Duration profilePhotoSignedUrlTtl = Duration(hours: 12);

/// Marge de sécurité avant expiration : une URL trop proche de la fin de vie
/// est resignée plutôt que servie à un widget qui l'afficherait trop tard.
const Duration _renewMargin = Duration(minutes: 10);

/// Clé du cache disque des URLs signées.
const String profilePhotoSignedUrlsPrefsKey = 'profile_photo_signed_urls_v1';

/// Cache partagé des URLs signées des photos de profil.
///
/// Avant, chaque avatar signait son URL dans son coin, à chaque construction
/// du widget : autant d'allers-retours réseau que d'avatars affichés, et une
/// URL différente à chaque fois, donc aucun cache image possible. Ce cache
/// résout trois choses :
///
/// - une seule signature par photo, réutilisée par tous les avatars ;
/// - les demandes émises dans la même frame sont regroupées en un seul appel
///   réseau (`createSignedUrls`) ;
/// - les URLs sont conservées sur l'appareil, donc encore valides au
///   redémarrage de l'application : la photo s'affiche alors immédiatement,
///   sans attendre le réseau.
class ProfilePhotoUrlCache {
  ProfilePhotoUrlCache._();

  static final ProfilePhotoUrlCache instance = ProfilePhotoUrlCache._();

  static const String bucket = 'profile-photos';

  final Map<String, _SignedUrl> _entries = <String, _SignedUrl>{};
  final Map<String, Completer<String?>> _pending =
      <String, Completer<String?>>{};
  final Set<String> _batch = <String>{};

  Timer? _batchTimer;
  bool _restored = false;
  Future<void>? _restoring;

  /// Extrait le chemin de stockage d'une valeur `photo_url`.
  ///
  /// La base stocke normalement un chemin relatif, mais d'anciennes lignes
  /// peuvent encore contenir une URL Supabase complète. Retourne `null` pour
  /// une URL externe, qui s'affiche alors telle quelle.
  static String? storagePath(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return trimmed.replaceFirst(RegExp(r'^/+'), '');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    const markers = [
      '/storage/v1/object/public/$bucket/',
      '/storage/v1/object/sign/$bucket/',
      '/storage/v1/object/authenticated/$bucket/',
    ];
    for (final marker in markers) {
      final index = uri.path.indexOf(marker);
      if (index >= 0) {
        return Uri.decodeComponent(uri.path.substring(index + marker.length));
      }
    }
    return null;
  }

  /// URL déjà connue pour cette valeur, sans aucun appel réseau.
  ///
  /// Permet à un avatar d'afficher la photo dès sa première frame quand elle a
  /// déjà été signée (autre écran, session précédente).
  String? cached(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final path = storagePath(trimmed);
    // Une URL externe complète est déjà affichable telle quelle.
    if (path == null) return trimmed;
    final entry = _entries[path];
    if (entry == null || entry.isExpired) return null;
    return entry.url;
  }

  /// Retourne une URL affichable, en la signant si nécessaire.
  Future<String?> resolve(String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final path = storagePath(trimmed);
    if (path == null) return trimmed;

    await _restore();

    final entry = _entries[path];
    if (entry != null && !entry.isExpired) return entry.url;

    final pending = _pending[path];
    if (pending != null) return pending.future;

    final completer = Completer<String?>();
    _pending[path] = completer;
    _batch.add(path);
    _batchTimer ??= Timer(Duration.zero, _flush);
    return completer.future;
  }

  /// Oublie l'URL d'une photo dont le chargement a échoué, afin que la
  /// prochaine tentative en redemande une neuve.
  void invalidate(String? value) {
    final path = storagePath(value);
    if (path == null) return;
    _entries.remove(path);
    unawaited(_persist());
  }

  Future<void> _flush() async {
    _batchTimer = null;
    final paths = _batch.toList(growable: false);
    _batch.clear();
    if (paths.isEmpty) return;

    final storage = Supabase.instance.client.storage.from(bucket);
    final signedAt = DateTime.now();
    final ttl = profilePhotoSignedUrlTtl.inSeconds;
    var resolved = <String, String>{};
    try {
      if (paths.length == 1) {
        resolved[paths.first] = await storage.createSignedUrl(paths.first, ttl);
      } else {
        final results = await storage.createSignedUrlsResult(paths, ttl);
        for (var index = 0; index < results.length; index++) {
          final result = results[index];
          if (result is! SignedUrlSuccess) continue;
          final path = _normalize(result.path);
          resolved[paths.contains(path) ? path : paths[index]] =
              result.signedUrl;
        }
      }
    } catch (error, stack) {
      // Une signature groupée qui échoue ne doit pas laisser les avatars en
      // attente : on relâche les demandes, les initiales restent affichées.
      AppLogger.error('profile_photo_sign', error, stack);
      resolved = <String, String>{};
    }

    for (final path in paths) {
      final url = resolved[path];
      if (url != null) {
        _entries[path] = _SignedUrl(
          url: url,
          expiresAt: signedAt.add(profilePhotoSignedUrlTtl),
        );
      }
      _pending.remove(path)?.complete(url);
    }
    await _persist();
  }

  static String _normalize(String path) {
    const prefix = '$bucket/';
    final value = path.replaceFirst(RegExp(r'^/+'), '');
    return value.startsWith(prefix) ? value.substring(prefix.length) : value;
  }

  Future<void> _restore() {
    if (_restored) return Future<void>.value();
    return _restoring ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(profilePhotoSignedUrlsPrefsKey);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            decoded.forEach((key, dynamic value) {
              final entry = _SignedUrl.fromJson(value);
              if (entry != null && !entry.isExpired) {
                _entries.putIfAbsent(key.toString(), () => entry);
              }
            });
          }
        }
      } catch (_) {
        // Un cache local illisible n'est jamais bloquant : on resigne.
      } finally {
        _restored = true;
        _restoring = null;
      }
    }();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        for (final entry in _entries.entries)
          if (!entry.value.isExpired) entry.key: entry.value.toJson(),
      };
      if (payload.isEmpty) {
        await prefs.remove(profilePhotoSignedUrlsPrefsKey);
      } else {
        await prefs.setString(profilePhotoSignedUrlsPrefsKey, jsonEncode(payload));
      }
    } catch (_) {
      // Le cache disque est un confort : son absence ne casse rien.
    }
  }

  /// Recharge le cache disque au démarrage, pour que les photos déjà vues
  /// s'affichent dès la première image de l'écran suivant.
  Future<void> warmUp() => _restore();

  /// Vide le cache (déconnexion, ou tests).
  Future<void> clear() async {
    _entries.clear();
    _batch.clear();
    _batchTimer?.cancel();
    _batchTimer = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.complete(null);
    }
    _pending.clear();
    _restored = false;
    _restoring = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(profilePhotoSignedUrlsPrefsKey);
    } catch (_) {
      // Rien à faire : le cache mémoire est déjà vide.
    }
  }
}

class _SignedUrl {
  const _SignedUrl({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;

  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(_renewMargin));

  Map<String, dynamic> toJson() => <String, dynamic>{
        'url': url,
        'expires_at': expiresAt.toIso8601String(),
      };

  static _SignedUrl? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url']?.toString();
    final expiresAt = DateTime.tryParse(raw['expires_at']?.toString() ?? '');
    if (url == null || url.isEmpty || expiresAt == null) return null;
    return _SignedUrl(url: url, expiresAt: expiresAt);
  }
}
