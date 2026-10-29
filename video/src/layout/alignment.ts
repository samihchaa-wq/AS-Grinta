// Portage fidèle de formation_assignment.dart et formation_display.dart.
//
// L'écran Compo ne dessine pas les coordonnées brutes d'une composition : il
// replace chaque titulaire sur l'emplacement actuel de son dispositif. La
// vidéo doit faire exactement la même chose, sinon la transition finale vers
// l'écran ferait sauter les joueurs. Les tests de test/alignment.test.ts
// rejouent les cas couverts côté Flutter.
import {
  formationForCodeOrNull,
  type FormationSlot,
  type Point,
} from './formation.ts';

export type FieldEntry = {
  id: string;
  isGoalkeeper: boolean;
  x: number | null;
  y: number | null;
};

const goalkeeperOutfieldCost = 100;
const unplacedCost = 1000;
const unplacedGoalkeeperCost = 2000;
const sameGridTolerance = 0.12;
const rescaledTolerance = 0.2;

/** Équivalent de `assignFieldPlayersToSlots`. */
export const assignFieldPlayersToSlots = (
  field: FieldEntry[],
  slots: FormationSlot[],
): Map<string, FormationSlot> => {
  const players = field.length;
  const slotCount = slots.length;
  const result = new Map<string, FormationSlot>();
  if (players === 0 || slotCount === 0) return result;

  const cost = (player: number, slot: number): number => {
    const entry = field[player];
    const target = slots[slot];
    const dx = (entry.x ?? 0.5) - target.x;
    const dy = (entry.y ?? 0.5) - target.y;
    const distance = dx * dx + dy * dy;
    if (entry.isGoalkeeper && target.label !== 'GB') {
      return distance + goalkeeperOutfieldCost;
    }
    return distance;
  };
  const unplaced = (player: number): number =>
    field[player].isGoalkeeper ? unplacedGoalkeeperCost : unplacedCost;

  const masks = 1 << slotCount;
  const best = new Float64Array((players + 1) * masks);
  const choice = new Int32Array(players * masks).fill(-1);
  for (let player = players - 1; player >= 0; player -= 1) {
    for (let used = 0; used < masks; used += 1) {
      let bestCost = unplaced(player) + best[(player + 1) * masks + used];
      let bestSlot = -1;
      for (let slot = 0; slot < slotCount; slot += 1) {
        if ((used & (1 << slot)) !== 0) continue;
        const candidate =
          cost(player, slot) + best[(player + 1) * masks + (used | (1 << slot))];
        if (candidate < bestCost) {
          bestCost = candidate;
          bestSlot = slot;
        }
      }
      best[player * masks + used] = bestCost;
      choice[player * masks + used] = bestSlot;
    }
  }

  let used = 0;
  for (let player = 0; player < players; player += 1) {
    const slot = choice[player * masks + used];
    if (slot < 0) continue;
    result.set(field[player].id, slots[slot]);
    used |= 1 << slot;
  }
  return result;
};

const bounds = (points: Point[]) => ({
  left: Math.min(...points.map((p) => p.x)),
  right: Math.max(...points.map((p) => p.x)),
  top: Math.min(...points.map((p) => p.y)),
  bottom: Math.max(...points.map((p) => p.y)),
});

const rescaledToFormation = (
  field: FieldEntry[],
  slots: FormationSlot[],
): FieldEntry[] => {
  const outfield = field
    .filter((e) => !e.isGoalkeeper)
    .map((e) => ({x: e.x!, y: e.y!}));
  const targets = slots.filter((s) => s.label !== 'GB');
  if (outfield.length === 0 || targets.length === 0) return [...field];

  const from = bounds(outfield);
  const to = bounds(targets);
  const scale = (
    value: number,
    min: number,
    max: number,
    toMin: number,
    toMax: number,
  ) => {
    if (max - min < 1e-6) return (toMin + toMax) / 2;
    return toMin + ((value - min) / (max - min)) * (toMax - toMin);
  };

  return field.map((entry) =>
    entry.isGoalkeeper
      ? entry
      : {
          ...entry,
          x: scale(entry.x!, from.left, from.right, to.left, to.right),
          y: scale(entry.y!, from.top, from.bottom, to.top, to.bottom),
        },
  );
};

export type AlignedEntry = FieldEntry & {
  /** Étiquette du poste occupé dans le dispositif, si l'alignement a eu lieu. */
  slotLabel: string | null;
};

/** Équivalent de `alignFieldToFormation`, enrichi du poste retenu. */
export const alignFieldToFormation = (
  formationCode: string | null | undefined,
  field: FieldEntry[],
): AlignedEntry[] => {
  const unchanged = field.map((e) => ({...e, slotLabel: null}));
  const formation = formationForCodeOrNull(formationCode);
  if (!formation || field.length === 0) return unchanged;
  const slots = formation.slots;
  if (field.length > slots.length) return unchanged;
  if (field.some((e) => e.x === null || e.y === null)) return unchanged;

  const complete = field.length === slots.length;
  const positioned = complete ? rescaledToFormation(field, slots) : [...field];
  const assigned = assignFieldPlayersToSlots(positioned, slots);
  if (assigned.size !== field.length) return unchanged;

  const tolerance = complete ? rescaledTolerance : sameGridTolerance;
  for (const entry of positioned) {
    const slot = assigned.get(entry.id)!;
    if (Math.hypot(entry.x! - slot.x, entry.y! - slot.y) > tolerance) {
      return unchanged;
    }
  }

  return field.map((entry) => {
    const slot = assigned.get(entry.id)!;
    return {...entry, x: slot.x, y: slot.y, slotLabel: slot.label};
  });
};
