// Génère test/fixtures/alignment-cases.json : des compositions d'entrée et
// le placement attendu. Le même fichier est relu par un test Flutter, qui
// vérifie que l'application place les joueurs exactement au même endroit.
//
//   node --experimental-strip-types scripts/make-alignment-fixture.mts
import {writeFileSync} from 'node:fs';
import {alignFieldToFormation} from '../src/layout/alignment.ts';
import {formationForCodeOrNull, matchSheetSlots} from '../src/layout/formation.ts';

type Input = {id: string; x: number | null; y: number | null; gk: boolean};

const archived = (rows: [number, number, string][]): Input[] =>
  rows.map(([x, y, line], i) => ({id: `p${i}`, x: x / 100, y: y / 100, gk: line === 'G'}));

const slotsOf = (code: string, count = 11): Input[] => {
  const formation = formationForCodeOrNull(code)!;
  return formation.slots.slice(0, count).map((slot, i) => ({
    id: `p${i}`,
    x: slot.x,
    y: slot.y,
    gk: slot.label === 'GB',
  }));
};

const gridOf = (code: string, count: number): Input[] => {
  const formation = formationForCodeOrNull(code)!;
  return formation.slots.slice(0, count).map((slot, i) => {
    const grid = matchSheetSlots.find((s) => s.label === slot.label)!;
    return {id: `p${i}`, x: grid.x, y: grid.y, gk: i === 0};
  });
};

const cases: {name: string; formation: string | null; players: Input[]}[] = [
  {name: 'archive 4-3-3', formation: '4-3-3', players: archived([[50, 93.5, 'G'], [10, 68.5, 'D'], [31.5, 74.8, 'D'], [68.5, 74.8, 'D'], [90, 68.5, 'D'], [18.2, 36.5, 'M'], [50, 43.3, 'M'], [81.8, 36.5, 'M'], [21.5, 6.9, 'A'], [50, 5, 'A'], [78.5, 6.9, 'A']])},
  {name: 'archive 4-2-3-1', formation: '4-2-3-1', players: archived([[50, 93.5, 'G'], [10, 68.5, 'D'], [33, 74.8, 'D'], [67, 74.8, 'D'], [90, 68.5, 'D'], [24.8, 49, 'M'], [75.2, 49, 'M'], [10.9, 21.7, 'M'], [50, 30.2, 'M'], [89.1, 21.7, 'M'], [50, 5, 'A']])},
  {name: 'archive 4-3-1-2', formation: '4-3-1-2', players: archived([[50, 95, 'G'], [10, 68.5, 'D'], [33, 74.8, 'D'], [67, 74.8, 'D'], [90, 68.5, 'D'], [10.9, 43.3, 'M'], [50, 52.1, 'M'], [89.1, 43.3, 'M'], [50, 22.5, 'M'], [24.8, 5, 'A'], [75.2, 5, 'A']])},
  {name: 'archive 3-5-2', formation: '3-5-2', players: archived([[50, 93.8, 'G'], [10, 61.3, 'D'], [50, 65.4, 'D'], [90, 61.3, 'D'], [10, 24.6, 'M'], [27.9, 30.2, 'M'], [50, 36.5, 'M'], [72.1, 30.2, 'M'], [90, 24.6, 'M'], [34.2, 5, 'A'], [65.8, 5, 'A']])},
  {name: 'éditeur 4-2-1-3 complet', formation: '4-2-1-3', players: slotsOf('4-2-1-3')},
  {name: 'éditeur 3-4-3 complet', formation: '3-4-3', players: slotsOf('3-4-3')},
  {name: 'éditeur 5-3-2 complet', formation: '5-3-2', players: slotsOf('5-3-2')},
  {name: 'alias 4-4-2', formation: '4-4-2', players: slotsOf('4-4-2 à plat')},
  {name: 'neuf titulaires sur l’ancienne grille', formation: '4-2-1-3', players: gridOf('4-2-1-3', 9)},
  {name: 'sept titulaires', formation: '4-2-1-3', players: gridOf('4-2-1-3', 7)},
  {name: 'placement libre éloigné des postes', formation: '4-4-2 à plat', players: [{id: 'p0', x: 0.5, y: 0.85, gk: true}, {id: 'p1', x: 0.5, y: 0.5, gk: false}, {id: 'p2', x: 0.2, y: 0.95, gk: false}]},
  {name: 'dispositif inconnu', formation: '4-3-0-3', players: slotsOf('4-2-1-3')},
  {name: 'sans dispositif', formation: null, players: slotsOf('4-2-1-3')},
  {name: 'coordonnée manquante', formation: '4-2-1-3', players: [...slotsOf('4-2-1-3', 10), {id: 'p10', x: null, y: null, gk: false}]},
  {name: 'gardien déclaré joué en défense', formation: '4-2-1-3', players: slotsOf('4-2-1-3').map((p, i) => ({...p, gk: i === 2}))},
];

const fixture = {
  cases: cases.map((c) => ({
    ...c,
    expected: alignFieldToFormation(
      c.formation,
      c.players.map((p) => ({id: p.id, isGoalkeeper: p.gk, x: p.x, y: p.y})),
    ).map((e) => ({id: e.id, x: e.x, y: e.y, slot: e.slotLabel})),
  })),
};
writeFileSync(new URL('../test/fixtures/alignment-cases.json', import.meta.url), JSON.stringify(fixture, null, 1) + '\n');
console.log(`${fixture.cases.length} cas`);
