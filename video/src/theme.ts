// Charte de la présentation : les couleurs de l'écusson et de l'application.
export const colors = {
  /** Bleu nuit de l'application (AppTheme.background). */
  night: '#041224',
  /** Plus profond encore, pour les noirs du stade. */
  abyss: '#020814',
  surface: '#091B33',
  /** Bleu royal de l'écusson. */
  crestBlue: '#05299D',
  /** Bleu royal des boutons de l'application (AppTheme.primary). */
  royal: '#1A4AC0',
  royalBright: '#6E93F6',
  /** Or des bandes de l'écusson. */
  gold: '#D9B24A',
  /** Jaune club de l'application (AppTheme.accent). */
  accent: '#FBE80C',
  white: '#F8FBFF',
  textFaint: '#9FB4CC',
  /** Liseré du gardien, comme sur les avatars de l'application. */
  keeper: '#E59A1F',
  /** Pelouse et liseré du terrain de l'application. */
  turfDark: '#14512E',
  turfLight: '#1C6B3B',
  pitchFill: '#124529',
  pitchBorder: '#6DAD8B',
  /** Fond de l'étiquette du prénom sur le terrain. */
  nameLabel: 'rgba(7, 21, 39, 0.82)',
} as const;

export const fonts = {
  display: 'Oswald',
  /** Police par défaut de l'application Web, pour le raccord final. */
  app: 'Roboto',
} as const;

export const video = {
  width: 1080,
  height: 1920,
  fps: 30,
} as const;
