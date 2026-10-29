// Combien de vidéos attendent ? Écrit `count=<n>` pour la suite du workflow,
// qui n'installe le moteur de rendu que s'il y a quelque chose à fabriquer.
import {appendFileSync} from 'node:fs';
import {callRenderApi} from './render-api.mjs';

const {pending} = await callRenderApi('pending');
const count = Number.isFinite(Number(pending)) ? Number(pending) : 0;
console.log(count === 0 ? 'Aucune vidéo en attente.' : `${count} vidéo(s) en attente.`);
if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `count=${count}\n`);
