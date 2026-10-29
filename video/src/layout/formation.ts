// Dispositifs tactiques de l'application, repris à l'identique.
//
// La source de vérité reste lib/features/sports_management/domain/
// football_formation.dart : formations.json en est une copie exacte, et un
// test Flutter échoue dès que les deux divergent. Le dessin de la vidéo et
// celui de l'écran Compo restent ainsi superposables au pixel près.
import catalogue from './formations.json' with {type: 'json'};

export type Point = {x: number; y: number};

export type FormationSlot = {label: string; x: number; y: number};

export type Formation = {
  code: string;
  defenderLine: number;
  slots: FormationSlot[];
};

export const defaultFormationCode: string = catalogue.defaultFormationCode;
export const matchSheetSlots: FormationSlot[] = catalogue.matchSheetSlots;
export const footballFormations: Formation[] = catalogue.formations;
const legacyAliases: Record<string, string> = catalogue.legacyAliases;

/** Équivalent de `formationForCodeOrNull` : jamais de dispositif inventé. */
export const formationForCodeOrNull = (
  code: string | null | undefined,
): Formation | null => {
  const raw = code?.trim();
  if (!raw) return null;
  const canonical = legacyAliases[raw] ?? raw;
  return footballFormations.find((f) => f.code === canonical) ?? null;
};

const knownSlotPositions: FormationSlot[] = [
  ...matchSheetSlots,
  ...footballFormations.flatMap((f) => f.slots),
];

/** Équivalent de `nearestMatchSheetSlotLabel`. */
export const nearestMatchSheetSlotLabel = (position: Point): string => {
  let closest = matchSheetSlots[0];
  let best = Number.POSITIVE_INFINITY;
  for (const slot of knownSlotPositions) {
    const dx = slot.x - position.x;
    const dy = slot.y - position.y;
    const distance = dx * dx + dy * dy;
    if (distance < best) {
      best = distance;
      closest = slot;
    }
  }
  return closest.label;
};
