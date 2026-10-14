import 'dart:convert';

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/push/push_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// Réenregistre côté serveur l'abonnement que l'appareil possède déjà, sans
  /// rien demander. Retourne false si l'appareil n'est pas abonné.
  Future<bool> resync();

  /// Désabonne le navigateur et supprime l'abonnement enregistré.
  Future<void> disable();
}

class SupabasePushSubscriptionsRepository
    implements PushSubscriptionsRepository {
  SupabasePushSubscriptionsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> isSupported() => pushSupported();

  /// Abonné ET autorisé. Un joueur qui coupe les notifications dans les
  /// réglages du téléphone garde son abonnement : Apple et Google acceptent
  /// toujours les envois, mais rien ne s'affiche. La cloche ne doit alors pas
  /// rester verte.
  @override
  Future<bool> isSubscribed() async {
    final current = await pushCurrentSubscription();
    if (current == null) return false;
    return await pushPermission() == 'granted';
  }

  /// Demande la permission puis enregistre l'abonnement. Retourne false si
  /// la permission est refusée ou si le navigateur ne supporte pas le push.
  @override
  Future<bool> enable() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final json = await pushSubscribe(pushVapidPublicKey);
    if (json == null) return false;
    final registered = await _register(json);
    if (registered) await writePushOptOut(false);
    return registered;
  }

  /// La cloche lit l'abonnement du navigateur, pas celui du serveur, et les
  /// deux peuvent diverger : un autre compte s'est connecté sur ce téléphone
  /// sans déconnexion, un sixième appareil a remplacé le plus ancien… La
  /// cloche reste alors verte alors que plus rien n'arrive. Réenregistrer
  /// l'abonnement existant est sans effet de bord : il est rattaché au compte
  /// connecté et repasse en tête des appareils récents.
  @override
  Future<bool> resync() async {
    if (_client.auth.currentUser == null) return false;

    final json = await pushCurrentSubscription();
    final registered = json != null && await _register(json);
    await _reportDevice(json);
    return registered;
  }

  /// Dit au serveur si ce téléphone autorise encore les notifications et
  /// lesquelles il a réellement affichées depuis la dernière ouverture. Sans
  /// ce retour, un envoi accepté par Apple ou Google passe pour reçu même
  /// quand le téléphone ne l'a jamais montré.
  Future<void> _reportDevice(String? subscriptionJson) async {
    final receipts = await pushDisplayReceipts();
    String? endpoint;
    if (subscriptionJson != null) {
      final subscription =
          Map<String, dynamic>.from(jsonDecode(subscriptionJson) as Map);
      endpoint = subscription['endpoint']?.toString();
    }
    if (endpoint == null && receipts == '[]') return;

    await _client.rpc(
      'report_my_push_device',
      params: {
        'p_endpoint': endpoint,
        'p_permission': await pushPermission(),
        'p_receipts': jsonDecode(receipts),
      },
    );
    await pushForgetDisplayReceipts(receipts);
  }

  Future<bool> _register(String json) async {
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

/// Ce que l'application doit signaler au joueur sur cet appareil.
enum PushDeviceAlert {
  /// Rien à signaler : l'appareil reçoit, ne sait pas recevoir, ou le joueur
  /// a choisi de ne rien recevoir ici.
  none,

  /// Le téléphone bloque l'affichage dans ses réglages. Apple et Google
  /// acceptent encore les envois, le joueur ne voit rien.
  blocked,

  /// L'appareil n'est pas abonné alors que le joueur ne l'a pas choisi :
  /// après une déconnexion, ou un abonnement perdu par le navigateur.
  notEnabled,
}

const _pushOptOutKey = 'asg-push-opted-out';

/// Le joueur a choisi de ne rien recevoir sur cet appareil (cloche éteinte ou
/// « Non merci »). Une déconnexion n'est pas un choix : elle désabonne
/// l'appareil sans poser ce marqueur.
Future<bool> readPushOptOut() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pushOptOutKey) ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> writePushOptOut(bool value) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pushOptOutKey, value);
  } catch (_) {
    // Au pire, le bandeau réapparaît à la prochaine ouverture.
  }
}

/// Recalculé à chaque relecture de l'état de la cloche.
final pushDeviceAlertProvider = FutureProvider<PushDeviceAlert>((ref) async {
  final status = await ref.watch(pushStatusProvider.future);
  if (!status.supported || status.subscribed) return PushDeviceAlert.none;
  if (await readPushOptOut()) return PushDeviceAlert.none;

  // Refus : seul le joueur peut le lever, dans les réglages. Sinon, un appui
  // sur « Activer » suffit (le navigateur redemande si besoin).
  return await pushPermission() == 'denied'
      ? PushDeviceAlert.blocked
      : PushDeviceAlert.notEnabled;
});
