// Conversion d'une demande de la base vers les données de la composition
// Remotion. Rien n'est inventé : un champ absent reste vide.

const numberOrNull = (value) =>
  typeof value === 'number' && Number.isFinite(value) ? value : null;

const textOrNull = (value) => {
  const text = typeof value === 'string' ? value.trim() : '';
  return text.length > 0 ? text : null;
};

/**
 * @param {Record<string, any>} payload  ce que la base a préparé
 * @param {Array<{src: string, alpha: boolean} | null>} photos  photos locales,
 *   dans l'ordre des joueurs
 */
export const toPresentationProps = (payload, photos) => ({
  teamName: textOrNull(payload.team_name) ?? 'AS Grinta',
  formationCode: textOrNull(payload.formation_code),
  players: (Array.isArray(payload.players) ? payload.players : []).map((player, index) => ({
    id: String(player.id ?? `joueur-${index}`),
    displayName: textOrNull(player.display_name) ?? 'Joueur',
    lastInitial: textOrNull(player.last_initial),
    photoUrl: photos[index]?.src ?? null,
    photoHasAlpha: photos[index]?.alpha ?? false,
    isGoalkeeper: player.is_goalkeeper === true,
    isGuest: player.is_guest === true,
    // Prévus pour plus tard : la base ne les fournit pas encore.
    isCaptain: player.is_captain === true,
    shirtNumber: numberOrNull(player.shirt_number),
    x: numberOrNull(typeof player.x === 'string' ? Number(player.x) : player.x),
    y: numberOrNull(typeof player.y === 'string' ? Number(player.y) : player.y),
    sortOrder: numberOrNull(player.sort_order) ?? index,
  })),
  match: {
    opponentName: textOrNull(payload.match?.opponent_name),
    kickoffAt: textOrNull(payload.match?.kickoff_at),
    competition: textOrNull(payload.match?.competition),
    matchType: textOrNull(payload.match?.match_type),
    championshipRound: numberOrNull(payload.match?.championship_round),
  },
});
