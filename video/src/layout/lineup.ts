// Modèle de la présentation : de la composition publiée aux onze révélations.
import {alignFieldToFormation} from './alignment.ts';
import {displayPoint} from './display.ts';
import {formationForCodeOrNull, nearestMatchSheetSlotLabel} from './formation.ts';
import type {LineupPresentationProps, PresentationPlayer} from '../types.ts';

export type Band = 'goalkeeper' | 'defense' | 'midfield' | 'attack';

export type LineupPlayer = PresentationPlayer & {
  photoHasAlpha: boolean;
  /** Position affichée par l'écran Compo (après alignement et bornes). */
  point: {x: number; y: number};
  slotLabel: string;
  band: Band;
  positionName: string;
  initials: string;
  avatarColors: [string, string];
  /** Rang de révélation, de 0 au nombre de titulaires moins un. */
  order: number;
};

export type Lineup = {
  players: LineupPlayer[];
  formationLabel: string | null;
};

const positionNames: Record<string, string> = {
  GB: 'Gardien de but',
  DG: 'Défenseur gauche',
  DCG: 'Défenseur central gauche',
  DC: 'Défenseur central',
  DCD: 'Défenseur central droit',
  DD: 'Défenseur droit',
  MDG: 'Milieu défensif gauche',
  MDC: 'Milieu défensif',
  MDD: 'Milieu défensif droit',
  MG: 'Milieu gauche',
  MCG: 'Milieu central gauche',
  MC: 'Milieu central',
  MCD: 'Milieu central droit',
  MD: 'Milieu droit',
  MOG: 'Milieu offensif gauche',
  MOC: 'Meneur de jeu',
  MOD: 'Milieu offensif droit',
  AG: 'Ailier gauche',
  AD: 'Ailier droit',
  BUG: 'Attaquant gauche',
  BU: 'Avant-centre',
  BUD: 'Attaquant droit',
};

export const bandOfSlot = (label: string): Band => {
  if (label === 'GB') return 'goalkeeper';
  if (['DG', 'DCG', 'DC', 'DCD', 'DD'].includes(label)) return 'defense';
  if (['AG', 'AD', 'BUG', 'BU', 'BUD'].includes(label)) return 'attack';
  return 'midfield';
};

export const bandTitles: Record<Band, string> = {
  goalkeeper: 'Le gardien',
  defense: 'La défense',
  midfield: 'Le milieu',
  attack: "L'attaque",
};

const bandRank: Record<Band, number> = {
  goalkeeper: 0,
  defense: 1,
  midfield: 2,
  attack: 3,
};

/**
 * Même règle que `capitalizePersonName` (name_validation.dart) : majuscule à
 * l'initiale de chaque partie du nom, le reste n'est pas touché.
 */
export const capitalizePersonName = (value: string): string => {
  const trimmed = value.trim();
  if (trimmed.length === 0) return trimmed;
  return trimmed.replace(/(^|[ '’-])(\p{L})/gu, (_, start: string, letter: string) =>
    `${start}${letter.toUpperCase()}`,
  );
};

/** Même règle que `avatarInitials` (name_validation.dart). */
export const avatarInitials = (name: string): string => {
  const words = name.trim().split(/\s+/).filter((word) => word.length > 0);
  if (words.length === 0) return '?';
  if (words.length > 1) return `${words[0][0]}${words[1][0]}`.toUpperCase();
  const word = words[0];
  return (word.length >= 2 ? word.substring(0, 2) : word).toUpperCase();
};

/** Même palette et même tirage que `PlayerAvatar` : mêmes couleurs partout. */
export const avatarPalette: [string, string][] = [
  ['#7C4DFF', '#5E35B1'],
  ['#2E86DE', '#1B4F91'],
  ['#17A589', '#0E6B57'],
  ['#E84393', '#B61E74'],
  ['#00A8E8', '#006C93'],
  ['#27AE60', '#1E7A45'],
  ['#E74C3C', '#992D22'],
  ['#00B2A9', '#00807A'],
  ['#8E44AD', '#5E2C72'],
  ['#546E7A', '#37474F'],
];

export const avatarColors = (name: string): [string, string] => {
  const seed = name.trim().toLowerCase();
  let hash = 0;
  for (let i = 0; i < seed.length; i += 1) {
    // Même arithmétique que Dart : on ne garde que les 31 bits de poids faible.
    hash = (hash * 31 + seed.charCodeAt(i)) % 0x80000000;
  }
  return avatarPalette[hash % avatarPalette.length];
};

export const buildLineup = (props: LineupPresentationProps): Lineup => {
  const starters = props.players;
  const aligned = alignFieldToFormation(
    props.formationCode,
    starters.map((p) => ({id: p.id, isGoalkeeper: p.isGoalkeeper, x: p.x, y: p.y})),
  );
  const byId = new Map(aligned.map((entry) => [entry.id, entry]));

  const players = starters.map((source) => {
    // L'écran Compo met une majuscule aux prénoms saisis en minuscules.
    const player = {
      ...source,
      displayName: capitalizePersonName(source.displayName) || 'Joueur',
      photoHasAlpha: source.photoHasAlpha ?? false,
    };
    const entry = byId.get(player.id)!;
    const point = displayPoint(entry.x, entry.y);
    const slotLabel = entry.slotLabel ?? nearestMatchSheetSlotLabel(point);
    // Un gardien déclaré posé hors des cages reste présenté à son poste réel.
    const band = bandOfSlot(slotLabel);
    return {
      ...player,
      point,
      slotLabel,
      band,
      positionName: positionNames[slotLabel] ?? 'Titulaire',
      initials: avatarInitials(player.displayName),
      avatarColors: avatarColors(player.displayName),
      order: 0,
    };
  });

  // Gardien, défenseurs, milieux puis attaquants ; dans une ligne, de gauche
  // à droite, et pour le milieu, du plus reculé au plus avancé.
  players.sort((a, b) => {
    const byBand = bandRank[a.band] - bandRank[b.band];
    if (byBand !== 0) return byBand;
    if (a.band === 'midfield') {
      const byDepth = b.point.y - a.point.y;
      if (Math.abs(byDepth) > 0.05) return byDepth;
    }
    const byX = a.point.x - b.point.x;
    if (Math.abs(byX) > 1e-6) return byX;
    return a.sortOrder - b.sortOrder;
  });
  players.forEach((player, index) => {
    player.order = index;
  });

  const formation = formationForCodeOrNull(props.formationCode);
  return {players, formationLabel: formation?.code ?? props.formationCode ?? null};
};
