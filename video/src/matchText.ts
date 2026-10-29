// Textes du match, rédigés comme dans l'application (match_model.dart).
import type {PresentationMatch} from './types.ts';

export type MatchLines = {
  opponent: string | null;
  competition: string | null;
  when: string | null;
};

const capitalize = (value: string) =>
  value.length === 0 ? value : value[0].toUpperCase() + value.slice(1);

/** « Mardi 3 novembre · 21:00 », à l'heure de Paris. */
export const kickoffLabel = (iso: string | null): string | null => {
  if (!iso) return null;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  const day = new Intl.DateTimeFormat('fr-FR', {
    timeZone: 'Europe/Paris',
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  }).format(date);
  const time = new Intl.DateTimeFormat('fr-FR', {
    timeZone: 'Europe/Paris',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
  return `${capitalize(day)} · ${time}`;
};

export const matchLines = (match: PresentationMatch): MatchLines => {
  const opponent = match.opponentName?.trim() || null;
  let competition: string | null = null;
  if (match.matchType === 'amical') {
    competition = 'Match amical';
  } else if (match.matchType === 'championnat') {
    competition =
      match.championshipRound === null
        ? 'Championnat'
        : `Championnat · Journée ${match.championshipRound}`;
  }
  return {opponent, competition, when: kickoffLabel(match.kickoffAt)};
};
