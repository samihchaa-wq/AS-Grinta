import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduit une erreur technique (PostgREST, Postgres, Auth…) en un message
/// clair et rassurant pour l'utilisateur. On ne montre jamais de trace brute
/// du type « PostgrestException(message: …, code: 23505) ».
String humanizeError(Object? error) {
  if (error == null) {
    return 'Une erreur est survenue. Réessaie dans un instant.';
  }
  if (error is String) return _fromMessage(error);
  if (error is StateError) return _fromMessage(error.message);
  if (error is ArgumentError) {
    return _fromMessage(error.message?.toString() ?? '');
  }
  if (error is AuthException) {
    return 'Connexion impossible. Vérifie ton identifiant et ton mot de passe.';
  }
  if (error is PostgrestException) {
    switch (error.code) {
      case '23505':
        return 'Cet élément existe déjà.';
      case '23503':
        return 'Action impossible : cet élément est encore utilisé ailleurs.';
      case 'PGRST116':
        return 'Ce contenu est introuvable ou a été supprimé.';
    }
    return _fromMessage(error.message);
  }
  return _fromMessage(error.toString());
}

/// Associe les messages connus (souvent levés par les fonctions SQL en
/// anglais) à un libellé français. Par défaut, renvoie un message générique
/// plutôt que d'exposer un texte technique.
String _fromMessage(String raw) {
  final message = raw.trim();
  if (message.isEmpty) {
    return 'Une erreur est survenue. Réessaie dans un instant.';
  }
  final lower = message.toLowerCase();

  const knownFrench = [
    'mot de passe',
    'identifiant',
    'saison',
    'adversaire',
    'cote',
    'match',
    'joueur',
    'obligatoire',
    'invalide',
    'droits',
  ];

  final patterns = <String, String>{
    'admin role required': 'Action réservée à l’administrateur.',
    'staff role required': 'Action réservée au staff.',
    'admin or moderator role required': 'Action réservée au staff.',
    'last active administrator':
        'Impossible : c’est le dernier administrateur actif.',
    'last active admin': 'Impossible : c’est le dernier administrateur actif.',
    'cannot delete your own account':
        'Tu ne peux pas supprimer ton propre compte.',
    'historical import actor': 'Ce compte technique ne peut pas être supprimé.',
    'target account not found': 'Ce compte est introuvable.',
    'only upcoming or finished matches': 'Ce match ne peut plus être modifié.',
    'season squad': 'Ce joueur ne fait pas partie de l’effectif de la saison.',
    'only a goalkeeper': 'Seul un gardien peut avoir un clean sheet.',
    'clean sheet is impossible':
        'Un clean sheet est impossible si l’adversaire a marqué.',
    'assists cannot exceed goals':
        'Le nombre de passes décisives ne peut pas dépasser le nombre de buts.',
    'motm must be a present player':
        'L’homme du match doit être un joueur présent.',
    'absent players cannot have statistics':
        'Un joueur absent ne peut pas avoir de statistiques.',
    'absent guests cannot have statistics':
        'Un invité absent ne peut pas avoir de statistiques.',
    'guest names must be present and unique':
        'Les noms des invités doivent être renseignés et uniques.',
    'negative statistics': 'Les statistiques ne peuvent pas être négatives.',
    'duplicate': 'Cet élément existe déjà.',
    'row-level security': 'Tu n’as pas les droits pour cette action.',
    'permission denied': 'Tu n’as pas les droits pour cette action.',
    'jwt expired': 'Ta session a expiré. Reconnecte-toi.',
    'failed host lookup':
        'Connexion au serveur impossible. Vérifie ton réseau.',
    'socketexception': 'Connexion au serveur impossible. Vérifie ton réseau.',
    'timeoutexception': 'Le serveur met trop de temps à répondre. Réessaie.',
  };

  for (final entry in patterns.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }

  // Message déjà rédigé en français par l'application : on le garde tel quel.
  if (knownFrench.any(lower.contains)) return message;

  return 'Une erreur est survenue. Réessaie dans un instant.';
}
