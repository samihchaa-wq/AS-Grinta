// Repli hors Web : drapeaux gardés en mémoire pour la durée de la session.
final Map<String, bool> _memory = {};

bool localFlagGet(String key) => _memory[key] ?? false;

void localFlagSet(String key, bool value) => _memory[key] = value;
