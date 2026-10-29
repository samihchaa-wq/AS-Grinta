// Composition d'exemple pour l'aperçu et le studio Remotion.
//
// Les vraies photos des joueurs sont privées : l'aperçu utilise des
// silhouettes anonymes, détourées comme les photos du club et au même
// cadrage que l'éditeur de photo de l'application (visage dans l'ovale,
// épaules en bas). Les prénoms sont fictifs. Les vraies présentations sont
// fabriquées avec les vraies photos.
import type {LineupPresentationProps} from '../types.ts';

const hairStyles = [
  'M104 130 Q 100 62 160 60 Q 220 62 216 130 Q 204 90 160 90 Q 116 90 104 130 Z',
  'M106 118 Q 110 58 160 56 Q 214 58 214 118 Q 196 80 160 82 Q 124 80 106 118 Z',
  'M102 140 Q 96 56 160 52 Q 226 56 218 140 Q 210 84 160 84 Q 110 84 102 140 Z',
];

const silhouette = (variant: number): string => {
  const hair = hairStyles[variant % hairStyles.length];
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 320" width="320" height="320">
<defs>
<linearGradient id="skin" x1="0" y1="0" x2="0.3" y2="1"><stop offset="0" stop-color="#A3AEBF"/><stop offset="1" stop-color="#697587"/></linearGradient>
<linearGradient id="shirt" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2155D6"/><stop offset="1" stop-color="#08277D"/></linearGradient>
<radialGradient id="rim" cx="50%" cy="20%" r="60%"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>
</defs>
<path d="M24 320 C 34 260 92 234 134 226 L 186 226 C 228 234 286 260 296 320 Z" fill="url(#shirt)"/>
<path d="M114 232 L 100 320 L 124 320 L 134 229 Z" fill="#D9B24A"/>
<path d="M206 232 L 220 320 L 196 320 L 186 229 Z" fill="#D9B24A"/>
<path d="M136 196 L 136 232 Q 160 250 184 232 L 184 196 Z" fill="url(#skin)"/>
<path d="M130 226 Q 160 266 190 226 L 180 223 Q 160 248 140 223 Z" fill="#FBE80C"/>
<ellipse cx="160" cy="134" rx="55" ry="69" fill="url(#skin)"/>
<path d="${hair}" fill="#262D3A"/>
<ellipse cx="160" cy="120" rx="70" ry="90" fill="url(#rim)"/>
</svg>`;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
};

type SampleRow = [string, string, number, number, number | null, boolean?];

// Prénom, poste, x, y, variante de silhouette (null = pas de photo), capitaine.
const rows: SampleRow[] = [
  ['Mathis', 'GB', 0.5, 0.89, 1],
  ['Yanis', 'DG', 0.12, 0.67, 0],
  ['Jean-Baptiste', 'DCG', 0.36, 0.72, 2],
  ['Rémi', 'DCD', 0.64, 0.72, 9],
  ['Thomas', 'DD', 0.88, 0.67, 3],
  ['Karim', 'MDG', 0.36, 0.55, 4],
  ['Lucas', 'MDD', 0.64, 0.55, 5],
  ['Enzo', 'MOC', 0.5, 0.36, 6],
  ['Sofiane', 'AG', 0.15, 0.23, 10],
  ['Maxime', 'BU', 0.5, 0.14, 7, true],
  ['Hugo', 'AD', 0.85, 0.23, 8],
];

export const sampleProps: LineupPresentationProps = {
  teamName: 'AS Grinta',
  formationCode: '4-2-1-3',
  match: {
    opponentName: 'Olympique Exemple 2',
    kickoffAt: '2026-11-03T20:00:00Z',
    competition: 'Championnat',
    matchType: 'championnat',
    championshipRound: 6,
  },
  players: rows.map(([name, , x, y, variant, captain], index) => ({
    id: `sample-${index}`,
    displayName: name,
    lastInitial: null,
    photoUrl: variant === null ? null : silhouette(variant),
    photoHasAlpha: true,
    isGoalkeeper: index === 0,
    isGuest: false,
    isCaptain: captain === true,
    x,
    y,
    sortOrder: index,
  })),
};
