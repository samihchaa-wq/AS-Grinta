import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Délais au-delà desquels une écriture ou sa relecture sont considérées comme
/// perdues. Ils reprennent ceux déjà retenus pour les pronostics de match et
/// les disponibilités.
const kConfirmedWriteTimeout = Duration(seconds: 12);
const kConfirmedReadTimeout = Duration(seconds: 8);

/// L'écriture a peut-être été appliquée par le serveur, mais l'application n'a
/// pas pu le vérifier.
///
/// L'appelant doit le dire tel quel à l'utilisateur — surtout pas annoncer un
/// échec — et ne jamais rejouer la mutation automatiquement.
class WriteOutcomeUnknown implements Exception {
  const WriteOutcomeUnknown();

  @override
  String toString() => 'Write outcome is unknown.';
}

/// Envoie une mutation puis, si l'accusé de réception se perd, relit l'état
/// serveur au lieu de rejouer l'écriture.
///
/// Un refus explicite du serveur est un échec certain et remonte tel quel :
/// seule une issue ambiguë — délai dépassé, transport coupé, accusé perdu —
/// déclenche la relecture. C'est ce qui distingue « le serveur a dit non » de
/// « je n'ai pas entendu la réponse », les deux seuls cas où rejouer une
/// mutation serait sûr ou dangereux.
///
/// [isExpected] doit prouver que c'est bien *cette* écriture qui a abouti, et
/// non un état antérieur qui lui ressemble : comparer un numéro de version ou
/// un horodatage, pas seulement les valeurs envoyées.
Future<T> confirmWrite<T extends Object>({
  required Future<T> Function() submit,
  required Future<T?> Function() readBack,
  required bool Function(T value) isExpected,
  Duration writeTimeout = kConfirmedWriteTimeout,
  Duration readTimeout = kConfirmedReadTimeout,
}) async {
  try {
    return await submit().timeout(writeTimeout);
  } on PostgrestException {
    // Le serveur a répondu explicitement avec un refus : l'échec est certain.
    rethrow;
  } on AuthException {
    // Session refusée : l'écriture n'a pas pu être appliquée.
    rethrow;
  } on StateError {
    // Réponse RPC inattendue : échec certain, pas une coupure ambiguë.
    rethrow;
  } catch (_) {
    // Délai dépassé, transport interrompu ou accusé perdu : la transaction
    // serveur a peut-être abouti. On ne la rejoue pas, on va la relire.
  }

  try {
    final current = await readBack().timeout(readTimeout);
    if (current != null && isExpected(current)) {
      return current;
    }
  } catch (_) {
    // La relecture est elle-même indisponible : le résultat reste inconnu.
  }

  throw const WriteOutcomeUnknown();
}
