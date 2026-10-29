// Données d'une présentation, telles que préparées par Supabase au moment de
// la publication. Rien n'est inventé : un champ inconnu reste vide.

export type PresentationPlayer = {
  /** Identifiant du participant au match. */
  id: string;
  /** Surnom ou prénom, comme sur l'écran Compo. */
  displayName: string;
  lastInitial: string | null;
  /** Adresse de la photo telle qu'elle sera chargée pendant le rendu. */
  photoUrl: string | null;
  /**
   * Vrai pour une photo détourée (fond transparent) : le joueur apparaît
   * seul. Une photo avec son fond est fondue sur les bords.
   */
  photoHasAlpha?: boolean;
  isGoalkeeper: boolean;
  isGuest: boolean;
  /** Prévu pour le jour où l'application saura qui porte le brassard. */
  isCaptain?: boolean;
  /** Prévu pour le jour où l'application connaîtra les numéros. */
  shirtNumber?: number | null;
  /** Coordonnées enregistrées dans la composition (0..1, attaque en haut). */
  x: number | null;
  y: number | null;
  sortOrder: number;
};

export type PresentationMatch = {
  opponentName: string | null;
  /** Coup d'envoi, ISO 8601. */
  kickoffAt: string | null;
  competition: string | null;
  matchType: string | null;
  championshipRound: number | null;
};

export type LineupPresentationProps = {
  teamName: string;
  formationCode: string | null;
  players: PresentationPlayer[];
  match: PresentationMatch;
};
