// Conversion des demandes de la base vers la composition vidéo.
import assert from 'node:assert/strict';
import {test} from 'node:test';
// @ts-expect-error module JavaScript sans types
import {toPresentationProps} from '../scripts/job-props.mjs';

test('une demande de la base devient une présentation', () => {
  const props = toPresentationProps(
    {
      team_name: 'AS Grinta',
      formation_code: '4-2-1-3',
      players: [
        {id: 'a', display_name: 'julien', last_initial: 'D', is_goalkeeper: true, x: 0.5, y: 0.89, sort_order: 1},
        {id: 'b', display_name: '  ', is_goalkeeper: false, x: '0.5', y: '0.14', sort_order: 2},
      ],
      match: {opponent_name: 'FC Test', kickoff_at: '2026-11-03T20:00:00+00:00', match_type: 'championnat', championship_round: 6},
    },
    [{src: 'jobs/j/0.png', alpha: true}, null],
  );
  assert.equal(props.formationCode, '4-2-1-3');
  assert.equal(props.players[0].photoUrl, 'jobs/j/0.png');
  assert.equal(props.players[0].photoHasAlpha, true);
  assert.equal(props.players[0].isGoalkeeper, true);
  assert.equal(props.players[1].displayName, 'Joueur');
  assert.equal(props.players[1].photoUrl, null);
  assert.equal(props.players[1].y, 0.14);
  assert.equal(props.players[1].isCaptain, false);
  assert.equal(props.match.championshipRound, 6);
  assert.equal(props.match.competition, null);
});

test('une demande incomplète ne fait jamais échouer la conversion', () => {
  const props = toPresentationProps({}, []);
  assert.equal(props.teamName, 'AS Grinta');
  assert.deepEqual(props.players, []);
  assert.equal(props.match.opponentName, null);
});
