// Chronologie de la présentation, en images (30 par seconde).
//
//   A  0 → 2 s    introduction : écusson, titre, match
//   B  2 → 14 s   révélation des titulaires, environ une seconde chacun
//   C  14 → 17 s  le onze complet s'illumine, dispositif et nom de l'équipe
//   D  17 → 18 s  la caméra se redresse : l'image devient l'écran Compo
//
// Avec moins de onze titulaires, chaque révélation garde son rythme et la
// vidéo raccourcit d'autant : on n'étire jamais une séquence pour la remplir.

export const introEnd = 60;
const revealWindow = 360;
const maxStride = 40;

/** Durée de vie d'une révélation, de l'apparition à l'atterrissage. */
export const revealLength = 46;
export const formationLength = 90;
export const finaleLength = 30;
/** Images figées à la fin : l'application prend le relais sur celles-ci. */
export const finalHold = 8;

export type Timeline = {
  count: number;
  stride: number;
  revealStart: (order: number) => number;
  revealsEnd: number;
  formationStart: number;
  finaleStart: number;
  duration: number;
};

export const buildTimeline = (count: number): Timeline => {
  const safeCount = Math.max(1, count);
  const stride = Math.min(maxStride, revealWindow / safeCount);
  const revealsEnd = introEnd + stride * safeCount;
  const formationStart = revealsEnd;
  const finaleStart = formationStart + formationLength;
  return {
    count: safeCount,
    stride,
    revealStart: (order) => introEnd - 6 + order * stride,
    revealsEnd,
    formationStart,
    finaleStart,
    duration: Math.round(finaleStart + finaleLength),
  };
};

/** Avancement 0 → 1 entre deux images, borné. */
export const progress = (frame: number, start: number, end: number) =>
  Math.min(1, Math.max(0, (frame - start) / (end - start)));
