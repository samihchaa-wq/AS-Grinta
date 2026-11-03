import 'dart:async';
import 'dart:collection';

import 'package:http/http.dart' as http;

/// Garde-fou contre les requêtes envoyées en boucle.
///
/// Le 3 novembre 2026, une minuterie mal bornée relançait la même lecture
/// (l'état de la cloche des buts) des centaines de fois par seconde : plus de
/// 90 % des requêtes du projet depuis juillet, et le quota gratuit de Supabase
/// dépassé pour toute l'organisation. Rien ne se voyait à l'écran.
///
/// Ce client se place sous celui de Supabase et compte les requêtes
/// **strictement identiques** (même méthode, même adresse, même contenu) vers
/// la base (`/rest/v1/`) et les fonctions serveur (`/functions/v1/`). Une
/// utilisation normale n'en envoie jamais plus de quelques-unes par minute.
/// Au-delà de [threshold] en [window], la requête est considérée comme prise
/// dans une boucle :
///
/// - les envois suivants de cette requête sont espacés, d'abord de
///   [throttleSpacing], puis d'un écart qui double tant que la boucle continue,
///   jusqu'à [maxThrottleSpacing] : une boucle tombe ainsi à une requête par
///   minute ;
/// - [onBurst] est appelé une seule fois par requête et par session, pour
///   laisser une trace exploitable (journal d'incidents).
///
/// La requête n'est jamais refusée : au pire elle part quelques secondes plus
/// tard. Dès qu'elle n'est plus demandée pendant [coolDown], elle redevient
/// libre. Les autres requêtes ne sont jamais ralenties.
class RequestBurstGuard extends http.BaseClient {
  RequestBurstGuard(
    this._inner, {
    this.threshold = 60,
    this.window = const Duration(minutes: 1),
    this.throttleSpacing = const Duration(seconds: 5),
    this.maxThrottleSpacing = const Duration(minutes: 1),
    this.coolDown = const Duration(minutes: 2),
    this.onBurst,
    DateTime Function()? now,
    Future<void> Function(Duration delay)? wait,
  })  : _now = now ?? DateTime.now,
        _wait = wait ?? Future<void>.delayed;

  final http.Client _inner;

  /// Nombre de requêtes identiques tolérées dans [window].
  final int threshold;
  final Duration window;

  /// Premier écart imposé entre deux envois d'une requête prise en boucle.
  final Duration throttleSpacing;

  /// Écart maximal, atteint en doublant [throttleSpacing]. Doit rester plus
  /// court que [coolDown], sans quoi la boucle serait libérée entre deux envois.
  final Duration maxThrottleSpacing;

  /// Silence nécessaire pour qu'une requête ralentie redevienne libre.
  final Duration coolDown;

  /// Appelé une fois par requête et par session, avec un libellé court et
  /// non sensible (`rpc/nom_de_fonction`, nom de table…), sans paramètres.
  final void Function(String endpoint)? onBurst;

  final DateTime Function() _now;
  final Future<void> Function(Duration delay) _wait;

  final Map<String, _BurstState> _states = <String, _BurstState>{};
  final Set<String> _reported = <String>{};

  /// Taille au-delà de laquelle un contenu n'est pas comparé : les envois
  /// volumineux (photos, gros formulaires) ne sont jamais des boucles de
  /// lecture et ne doivent pas coûter une comparaison.
  static const int _maxComparedBodyLength = 4096;

  static const int _maxTrackedRequests = 500;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final delay = _admit(request);
    if (delay > Duration.zero) await _wait(delay);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();

  /// Enregistre la requête et renvoie le délai à respecter avant de l'envoyer.
  Duration _admit(http.BaseRequest request) {
    final endpoint = endpointLabel(request.url);
    if (endpoint == null || request is! http.Request) return Duration.zero;
    final body = request.body;
    if (body.length > _maxComparedBodyLength) return Duration.zero;

    final key = '${request.method} ${request.url}\n$body';
    final now = _now();
    final state = _states.putIfAbsent(key, _BurstState.new);

    final lastSeen = state.lastSeen;
    if (state.throttled &&
        lastSeen != null &&
        now.difference(lastSeen) >= coolDown) {
      state
        ..throttled = false
        ..nextAllowed = null
        ..spacing = null
        ..recent.clear();
    }
    state.lastSeen = now;

    final windowStart = now.subtract(window);
    while (
        state.recent.isNotEmpty && state.recent.first.isBefore(windowStart)) {
      state.recent.removeFirst();
    }
    state.recent.addLast(now);

    if (!state.throttled && state.recent.length > threshold) {
      state.throttled = true;
      if (_reported.add(key)) onBurst?.call(endpoint);
    }

    _forgetIdleRequests(now);

    if (!state.throttled) return Duration.zero;

    final spacing = state.spacing ?? throttleSpacing;
    final nextAllowed = state.nextAllowed;
    final sendAt =
        nextAllowed == null || !nextAllowed.isAfter(now) ? now : nextAllowed;
    state
      ..nextAllowed = sendAt.add(spacing)
      ..spacing =
          spacing * 2 > maxThrottleSpacing ? maxThrottleSpacing : spacing * 2;
    return sendAt.difference(now);
  }

  void _forgetIdleRequests(DateTime now) {
    if (_states.length <= _maxTrackedRequests) return;
    final idleBefore = now.subtract(window + coolDown);
    _states.removeWhere((_, state) {
      final lastSeen = state.lastSeen;
      return lastSeen == null || lastSeen.isBefore(idleBefore);
    });
  }

  /// Libellé court de la requête, ou `null` si elle n'est pas surveillée.
  ///
  /// Seul le chemin est gardé : jamais les paramètres, qui peuvent contenir
  /// des identifiants.
  static String? endpointLabel(Uri url) {
    const watched = ['/rest/v1/', '/functions/v1/'];
    for (final prefix in watched) {
      final index = url.path.indexOf(prefix);
      if (index >= 0) {
        final rest = url.path.substring(index + prefix.length);
        return rest.isEmpty ? prefix : rest;
      }
    }
    return null;
  }
}

class _BurstState {
  final Queue<DateTime> recent = Queue<DateTime>();
  DateTime? lastSeen;
  DateTime? nextAllowed;
  Duration? spacing;
  bool throttled = false;
}
