final RegExp _liveGuestSuffix = RegExp(
  r'\s*\(invité\)\s*$',
  caseSensitive: false,
);

/// Dans le Live, un invité est toujours affiché avec son prénom uniquement.
/// Le nom complet reste conservé côté serveur et dans les écrans hors Live.
String liveGuestFirstName(String value) {
  final cleaned = value.replaceFirst(_liveGuestSuffix, '').trim();
  if (cleaned.isEmpty) return value.trim();
  return cleaned.split(RegExp(r'\s+')).first;
}

/// Normalise une composition reçue par le Live sans modifier le modèle
/// générique utilisé par les autres écrans de gestion sportive.
Object? normalizeLiveLineupGuestNames(Object? raw) {
  if (raw is! Map) return raw;

  final lineup = Map<String, dynamic>.from(raw);
  final entries = lineup['entries'];
  if (entries is! List) return lineup;

  lineup['entries'] = [
    for (final row in entries)
      if (row is Map)
        _normalizeLiveLineupEntry(Map<String, dynamic>.from(row))
      else
        row,
  ];
  return lineup;
}

Map<String, dynamic> _normalizeLiveLineupEntry(Map<String, dynamic> entry) {
  final guestPlayerId = entry['guest_player_id']?.toString().trim();
  final isGuest = entry['is_guest'] == true ||
      (guestPlayerId != null &&
          guestPlayerId.isNotEmpty &&
          guestPlayerId != 'null');

  if (isGuest) {
    entry['display_name'] = liveGuestFirstName(
      (entry['display_name'] ?? 'Invité').toString(),
    );
  }
  return entry;
}

/// Les événements Live ne transportent pas toujours le drapeau `is_guest`.
/// La mention « (Invité) » permet alors de reconnaître le cas sans toucher
/// aux noms des joueurs réguliers.
String? liveEventDisplayName(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') return null;
  if (!_liveGuestSuffix.hasMatch(text)) return text;
  return liveGuestFirstName(text);
}
