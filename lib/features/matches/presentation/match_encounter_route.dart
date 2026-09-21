String? matchEncounterRoute({
  required String? encounterId,
  required bool isHistorical,
}) {
  final id = encounterId?.trim();
  if (id == null || id.isEmpty) return null;
  return isHistorical ? '/matches/history/$id' : '/matches/$id';
}
