// Géométrie de l'écran Compo de l'application (CompositionPitch), en unités
// de référence : un terrain de 340 × 500, comme dans CompositionPitchWithBench.
//
// La dernière image de la vidéo reproduit cette géométrie à l'identique, mise
// à l'échelle : l'application peut alors poser son propre terrain exactement
// par-dessus et prendre le relais sans que rien ne bouge.

export const pitchRefWidth = 340;
export const pitchRefHeight = pitchRefWidth / 0.68;

/** Bordure du conteneur : la pile des joueurs commence 1,5 plus loin. */
export const pitchBorderWidth = 1.5;
export const pitchOuterRadius = 28;
export const pitchInnerRadius = 26;

export const markerWidth = 64;
export const markerHeight = 84;

/** La photo (52) est centrée en bas d'une case de 60 × 64 posée en haut. */
export const photoSize = 52;
export const photoOffset = {x: 6, y: 12};
export const photoRadiusRatio = 0.28;

/** Les initiales occupent un carré plus petit que la photo (fallbackScale). */
export const initialsScale = 0.84;

/** Étiquette du prénom, sous la case photo (64 + 2). */
export const nameLabelTop = 66;
export const nameLabelFontSize = 11;
export const nameLabelPadding = {x: 5, y: 1};

export const clamp = (value: number, min: number, max: number) =>
  Math.min(max, Math.max(min, value));

/** Position affichée d'un joueur : mêmes bornes que l'écran Compo. */
export const displayPoint = (x: number | null, y: number | null) => ({
  x: clamp(x ?? 0.5, 0.08, 0.92),
  y: clamp(y ?? 0.5, 0.06, 0.94),
});

/**
 * Coin haut-gauche de la case d'un joueur dans le repère du terrain
 * (bordure comprise), comme le `Positioned` de CompositionPitch.
 */
export const markerOrigin = (point: {x: number; y: number}) => ({
  left:
    pitchBorderWidth +
    clamp(point.x * pitchRefWidth - markerWidth / 2, 0, pitchRefWidth - markerWidth),
  top:
    pitchBorderWidth +
    clamp(
      point.y * pitchRefHeight - markerHeight / 2,
      0,
      pitchRefHeight - markerHeight,
    ),
});

/** Centre de la photo d'un joueur dans le repère du terrain. */
export const photoCenter = (point: {x: number; y: number}) => {
  const origin = markerOrigin(point);
  return {
    x: origin.left + photoOffset.x + photoSize / 2,
    y: origin.top + photoOffset.y + photoSize / 2,
  };
};
