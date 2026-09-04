import 'package:as_grinta/core/utils/name_validation.dart';

/// Règle unique d'appellation d'une personne dans toute l'application.
///
/// L'ordre de priorité est le même que côté serveur
/// (`public.person_display_name`) :
///
/// 1. le surnom du compte, s'il est renseigné ;
/// 2. sinon le prénom du compte ;
/// 3. sinon le prénom de repli (fiche d'effectif, invité, import) ;
/// 4. sinon le nom de repli ;
/// 5. sinon [fallback].
///
/// Un champ vide ou uniquement composé d'espaces est traité comme absent : le
/// client enregistre un surnom non renseigné sous la forme d'une chaîne vide,
/// pas d'un `null`.
///
/// Le résultat est toujours capitalisé par [capitalizePersonName] : un prénom
/// saisi en minuscules ne doit jamais s'afficher ainsi.
String resolveDisplayName({
  Object? surnom,
  Object? profileFirstName,
  Object? fallbackFirstName,
  Object? fallbackLastName,
  String fallback = 'Joueur',
}) {
  final first = _text(fallbackFirstName);
  final last = _text(fallbackLastName);
  final candidates = <String>[
    _text(surnom),
    _text(profileFirstName),
    first,
    '$first $last'.trim(),
  ];
  for (final candidate in candidates) {
    if (candidate.isNotEmpty) return capitalizePersonName(candidate);
  }
  return fallback;
}

/// Clé de tri alignée sur le nom réellement affiché, pour qu'une liste soit
/// classée comme elle se lit.
String displayNameSortKey({
  Object? surnom,
  Object? profileFirstName,
  Object? fallbackFirstName,
  Object? fallbackLastName,
}) {
  return resolveDisplayName(
    surnom: surnom,
    profileFirstName: profileFirstName,
    fallbackFirstName: fallbackFirstName,
    fallbackLastName: fallbackLastName,
    fallback: '',
  ).toLowerCase();
}

/// Appellation d'un invité : prénom, éventuellement suivi de son nom. Un
/// invité n'a jamais de surnom, il n'a pas de compte.
String resolveGuestDisplayName({Object? firstName, Object? lastName}) {
  return capitalizePersonName(
    '${_text(firstName)} ${_text(lastName)}'.trim(),
  );
}

String _text(Object? value) => (value ?? '').toString().trim();
