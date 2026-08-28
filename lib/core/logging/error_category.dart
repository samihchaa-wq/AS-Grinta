import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduit une erreur en catégorie **stable** et non sensible.
///
/// L'ancien enregistrement utilisait `error.runtimeType.toString()`. Sur la
/// version Web publiée, le compilateur remplace les noms de classes par des
/// symboles courts : la production ne recevait que `minified:abz`, illisible et
/// indécodable après coup. Les tests de type (`error is …`) survivent au
/// contraire à cette compression, et sont donc la seule base fiable ici.
///
/// La catégorie ne contient jamais le message de l'erreur : uniquement une
/// famille et, quand il existe, un code structuré déjà non sensible (SQLSTATE
/// PostgreSQL, code d'erreur d'authentification, statut HTTP de Storage).
String describeErrorForIncident(Object? error) {
  if (error == null) return 'null';

  // La coupure réseau se reconnaît avant tout le reste : selon la plateforme et
  // le navigateur, elle arrive déguisée en erreur d'authentification, en
  // exception HTTP ou en erreur de socket.
  if (isNetworkFailure(error)) return 'network';

  if (error is TimeoutException) return 'timeout';

  if (error is PostgrestException) {
    return _withCode('postgrest', error.code);
  }
  if (error is AuthException) {
    return _withCode('auth', error.code ?? error.statusCode);
  }
  if (error is StorageException) {
    return _withCode('storage', error.statusCode);
  }

  if (error is FormatException) return 'format';
  if (error is StateError) return 'state';
  if (error is ArgumentError) return 'argument';
  if (error is RangeError) return 'range';
  if (error is UnsupportedError) return 'unsupported';
  if (error is UnimplementedError) return 'unimplemented';
  if (error is TypeError) return 'type';
  if (error is OutOfMemoryError) return 'out_of_memory';
  if (error is StackOverflowError) return 'stack_overflow';

  // Famille inconnue : le nom de type reste illisible en release, mais il reste
  // stable au sein d'une même version publiée. Le conserver permet au moins de
  // regrouper les occurrences d'un même défaut et de compter leur volume.
  return _withCode('other', _typeToken(error));
}

/// `true` lorsque l'erreur traduit une perte de connexion plutôt qu'un refus
/// du serveur.
///
/// Les tests de type ne suffisent pas ici : sur le Web, l'échec vient de
/// `ClientException` (paquet HTTP transitif, non déclaré par l'application) et
/// son libellé change d'un navigateur à l'autre. La reconnaissance combine donc
/// les types réellement disponibles et les signatures connues, sur une chaîne
/// utilisée uniquement pour classer — jamais pour être journalisée ni affichée.
bool isNetworkFailure(Object? error) {
  if (error == null) return false;

  // Seul marqueur de type disponible : l'échec de transport côté
  // authentification.
  if (error is AuthRetryableFetchException) return true;

  // Écarter d'abord tout ce qui ne peut pas être une coupure réseau. Sans ce
  // filtre, une erreur applicative ordinaire pouvait contenir par hasard une
  // formulation de la liste ci-dessous : `StateError('load failed')` se voyait
  // ainsi annoncé à l'utilisateur comme un problème de connexion.
  if (error is PostgrestException ||
      error is StorageException ||
      error is FormatException ||
      error is StateError ||
      error is ArgumentError ||
      error is RangeError ||
      error is UnsupportedError ||
      error is UnimplementedError ||
      error is TypeError) {
    return false;
  }

  final signature = error.toString().toLowerCase();
  for (final marker in _networkMarkers) {
    if (signature.contains(marker)) return true;
  }
  return false;
}

/// Signatures d'indisponibilité réseau.
///
/// Sur le Web, l'échec de transport remonte enveloppé dans une
/// `ClientException` quel que soit le navigateur, ce qui en fait le marqueur le
/// plus fiable ; les versions mobiles lèvent une `SocketException`. Les
/// formulations propres aux navigateurs ne sont conservées que sous leur forme
/// longue : les variantes courtes comme « load failed » sont trop banales pour
/// être distinguées d'un message applicatif.
const List<String> _networkMarkers = [
  'clientexception',
  'socketexception',
  'httpexception',
  'failed to fetch',
  'networkerror when attempting to fetch',
  'network is unreachable',
  'connection refused',
  'connection reset by peer',
  'failed host lookup',
  'no address associated with hostname',
  'software caused connection abort',
  'err_internet_disconnected',
  'err_network_changed',
  'err_name_not_resolved',
];

String _withCode(String family, String? code) {
  final token = _sanitizeToken(code);
  return token == null ? family : '$family:$token';
}

/// Extrait un identifiant de type exploitable comme clé de regroupement.
///
/// En release Web, `runtimeType` vaut `minified:abz` : seul le symbole est
/// conservé. En debug, c'est le nom réel de la classe.
String? _typeToken(Object error) {
  final raw = error.runtimeType.toString();
  final separator = raw.lastIndexOf(':');
  return _sanitizeToken(separator < 0 ? raw : raw.substring(separator + 1));
}

/// Garantit qu'aucun contenu inattendu ne rejoint le journal : seuls des
/// caractères d'identifiant survivent, et la longueur reste bornée.
String? _sanitizeToken(String? value) {
  if (value == null) return null;
  final cleaned = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
  if (cleaned.isEmpty) return null;
  return cleaned.length <= 32 ? cleaned : cleaned.substring(0, 32);
}
