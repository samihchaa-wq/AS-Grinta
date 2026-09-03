import 'dart:convert';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/push/push_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Gère l'abonnement du navigateur aux notifications push et sa copie
/// dans la table push_subscriptions.
///
/// L'interface existe pour que l'écran des notifications soit testable sans
/// navigateur ni serveur : le navigateur ne sait ni s'abonner ni se
/// désabonner dans un test, et sans point de substitution le bouton
/// « Désactiver » ne pourrait être vérifié qu'à la main.
abstract interface class PushSubscriptionsRepository {
  /// L'appareil sait-il recevoir des notifications push.
  Future<bool> isSupported();

  /// Cet appareil est-il déjà abonné.
  Future<bool> isSubscribed();

  /// Demande la permission puis enregistre l'abonnement.
  Future<bool> enable();

  /// Désabonne le navigateur et supprime l'abonnement enregistré.
  Future<void> disable();
}

class SupabasePushSubscriptionsRepository
    implements PushSubscriptionsRepository {
  SupabasePushSubscriptionsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> isSupported() => pushSupported();

  @override
  Future<bool> isSubscribed() async {
    final current = await pushCurrentSubscription();
    return current != null;
  }

  /// Demande la permission puis enregistre l'abonnement. Retourne false si
  /// la permission est refusée ou si le navigateur ne supporte pas le push.
  @override
  Future<bool> enable() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final json = await pushSubscribe(pushVapidPublicKey);
    if (json == null) return false;

    final subscription = Map<String, dynamic>.from(jsonDecode(json) as Map);
    final endpoint = subscription['endpoint']?.toString() ?? '';
    final keys = Map<String, dynamic>.from(
      subscription['keys'] as Map? ?? const {},
    );
    final p256dh = keys['p256dh']?.toString() ?? '';
    final auth = keys['auth']?.toString() ?? '';
    if (endpoint.isEmpty || p256dh.isEmpty || auth.isEmpty) return false;

    await _client.rpc(
      'register_push_subscription',
      params: {
        'p_endpoint': endpoint,
        'p_p256dh': p256dh,
        'p_auth': auth,
      },
    );
    return true;
  }

  /// Désabonne le navigateur et supprime la ligne correspondante.
  @override
  Future<void> disable() async {
    final json = await pushUnsubscribe();
    if (json == null) return;

    final subscription = Map<String, dynamic>.from(jsonDecode(json) as Map);
    final endpoint = subscription['endpoint']?.toString() ?? '';
    if (endpoint.isEmpty) return;

    await _client.from('push_subscriptions').delete().eq('endpoint', endpoint);
  }
}

final pushSubscriptionsRepositoryProvider =
    Provider<PushSubscriptionsRepository>((ref) {
  return SupabasePushSubscriptionsRepository(
    ref.watch(supabaseClientProvider),
  );
});

/// État courant de l'abonnement push du navigateur.
final pushStatusProvider = FutureProvider<({bool supported, bool subscribed})>(
  (ref) async {
    final repository = ref.watch(pushSubscriptionsRepositoryProvider);
    final supported = await repository.isSupported();
    if (!supported) return (supported: false, subscribed: false);
    return (supported: true, subscribed: await repository.isSubscribed());
  },
);
