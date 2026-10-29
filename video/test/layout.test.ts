// Tests de la géométrie de la présentation.
//
//   npm test
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {alignFieldToFormation} from '../src/layout/alignment.ts';
import {displayPoint, markerOrigin, photoCenter} from '../src/layout/display.ts';
import {formationForCodeOrNull, footballFormations} from '../src/layout/formation.ts';
import {
  avatarColors,
  avatarInitials,
  avatarPalette,
  buildLineup,
  capitalizePersonName,
} from '../src/layout/lineup.ts';
import {kickoffLabel, matchLines} from '../src/matchText.ts';
import {buildTimeline} from '../src/timeline.ts';
import {sampleProps} from '../src/data/sample.ts';
import type {LineupPresentationProps} from '../src/types.ts';

type Fixture = {
  cases: {
    name: string;
    formation: string | null;
    players: {id: string; x: number | null; y: number | null; gk: boolean}[];
    expected: {id: string; x: number | null; y: number | null; slot: string | null}[];
  }[];
};

const fixture: Fixture = JSON.parse(
  readFileSync(new URL('./fixtures/alignment-cases.json', import.meta.url), 'utf8'),
);

test('le placement suit exactement les cas partagés avec l’application', () => {
  for (const c of fixture.cases) {
    const aligned = alignFieldToFormation(
      c.formation,
      c.players.map((p) => ({id: p.id, isGoalkeeper: p.gk, x: p.x, y: p.y})),
    );
    assert.deepEqual(
      aligned.map((e) => ({id: e.id, x: e.x, y: e.y, slot: e.slotLabel})),
      c.expected,
      c.name,
    );
  }
});

test('les compositions archivées rejoignent chacune un poste distinct', () => {
  for (const c of fixture.cases.filter((c) => c.name.startsWith('archive'))) {
    const slots = new Set(c.expected.map((e) => e.slot));
    assert.equal(slots.size, 11, c.name);
    assert.ok(!slots.has(null), c.name);
  }
});

test('chaque dispositif a onze postes, gardien compris', () => {
  for (const formation of footballFormations) {
    assert.equal(formation.slots.length, 11, formation.code);
    assert.equal(formation.slots.filter((s) => s.label === 'GB').length, 1, formation.code);
  }
  assert.equal(formationForCodeOrNull('4-3-3')?.code, '4-3-3 défensif');
  assert.equal(formationForCodeOrNull('inconnu'), null);
});

test('les joueurs gardent les bornes et les cases de l’écran Compo', () => {
  assert.deepEqual(displayPoint(0, 1), {x: 0.08, y: 0.94});
  assert.deepEqual(displayPoint(null, null), {x: 0.5, y: 0.5});
  // Gardien d'un 4-2-1-3 : case de 64 × 84 centrée en (0,50 ; 0,89).
  const origin = markerOrigin({x: 0.5, y: 0.89});
  assert.equal(origin.left, 1.5 + 170 - 32);
  assert.ok(Math.abs(origin.top - (1.5 + 0.89 * 500 - 42)) < 1e-9);
  // Un joueur collé au bord reste entièrement sur le terrain.
  assert.equal(markerOrigin({x: 0.08, y: 0.06}).left, 1.5);
  const center = photoCenter({x: 0.5, y: 0.5});
  assert.equal(center.x, 1.5 + 170);
  // 340 / 0,68 ne tombe pas juste en virgule flottante, en Dart comme ici.
  assert.ok(Math.abs(center.y - (1.5 + 250 - 42 + 12 + 26)) < 1e-9);
});

test('les initiales et les couleurs sont celles des avatars de l’application', () => {
  assert.equal(avatarInitials('Julien'), 'JU');
  assert.equal(avatarInitials('Jean Baptiste'), 'JB');
  assert.equal(avatarInitials('  '), '?');
  assert.equal(avatarInitials('Él'), 'ÉL');
  // Même tirage que PlayerAvatar : hachage ×31 sur 31 bits, puis modulo 10.
  const expected = (name: string) => {
    let hash = 0;
    for (const unit of name.trim().toLowerCase().split('').map((c) => c.charCodeAt(0))) {
      hash = Number((BigInt(hash) * 31n + BigInt(unit)) & 0x7fffffffn);
    }
    return hash % 10;
  };
  for (const name of ['Rémi', 'Sofiane', 'Jean-Baptiste', 'Le Kaiser', 'Anthony-Alexandre']) {
    assert.deepEqual(avatarColors(name), avatarPalette[expected(name)], name);
  }
  assert.deepEqual(avatarColors('Rémi'), avatarColors('  rémi '));
});

test('les prénoms prennent la majuscule de l’écran Compo, sans rien défaire', () => {
  assert.equal(capitalizePersonName('romain'), 'Romain');
  assert.equal(capitalizePersonName(' jean-pierre '), 'Jean-Pierre');
  assert.equal(capitalizePersonName("l'éclair"), "L'Éclair");
  assert.equal(capitalizePersonName('CHÂA'), 'CHÂA');
  assert.equal(capitalizePersonName('McDonald'), 'McDonald');
  assert.equal(capitalizePersonName('élodie'), 'Élodie');
});

test('la révélation suit gardien, défense, milieu puis attaque', () => {
  const lineup = buildLineup(sampleProps);
  assert.deepEqual(
    lineup.players.map((p) => p.slotLabel),
    ['GB', 'DG', 'DCG', 'DCD', 'DD', 'MDG', 'MDD', 'MOC', 'AG', 'BU', 'AD'],
  );
  assert.deepEqual(
    lineup.players.map((p) => p.order),
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  );
  assert.equal(lineup.players[0].band, 'goalkeeper');
  assert.equal(lineup.players[7].positionName, 'Meneur de jeu');
  assert.equal(lineup.formationLabel, '4-2-1-3');
});

test('une composition incomplète ou sans dispositif reste présentable', () => {
  const few: LineupPresentationProps = {
    ...sampleProps,
    formationCode: null,
    players: sampleProps.players.slice(0, 7),
  };
  const lineup = buildLineup(few);
  assert.equal(lineup.players.length, 7);
  assert.equal(lineup.formationLabel, null);
  for (const p of lineup.players) assert.ok(p.positionName.length > 0);
  const t = buildTimeline(7);
  assert.ok(t.duration < buildTimeline(11).duration);
  assert.equal(buildTimeline(11).duration, 540);
  assert.equal(buildTimeline(0).count, 1);
});

test('les textes du match sont rédigés comme dans l’application', () => {
  assert.equal(kickoffLabel('2026-11-03T20:00:00Z'), 'Mardi 3 novembre · 21:00');
  assert.equal(kickoffLabel('2026-07-14T18:30:00Z'), 'Mardi 14 juillet · 20:30');
  assert.equal(kickoffLabel(null), null);
  assert.deepEqual(
    matchLines({opponentName: ' FC Test ', kickoffAt: null, competition: 'Championnat', matchType: 'championnat', championshipRound: 4}),
    {opponent: 'FC Test', competition: 'Championnat · Journée 4', when: null},
  );
  assert.equal(
    matchLines({opponentName: null, kickoffAt: null, competition: 'Championnat', matchType: 'amical', championshipRound: null}).competition,
    'Match amical',
  );
});
