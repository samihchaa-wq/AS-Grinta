// Fabrique les vidéos de présentation en attente (workflow GitHub
// « Lineup presentation render »).
//
//   1. réserve les demandes auprès de Supabase ;
//   2. télécharge les photos des titulaires (liens valables quelques minutes) ;
//   3. rend chaque vidéo, puis ses deux encodages de diffusion ;
//   4. dépose les fichiers dans le stockage privé et annonce la vidéo prête.
//
// Une erreur sur une vidéo est notée sans toucher aux autres : la demande
// repart en file et sera retentée (trois essais au plus). Le dépôt étant
// public, ce script ne journalise que des identifiants techniques : jamais
// un prénom, une photo ou une adresse signée.
import {spawn} from 'node:child_process';
import {mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {bundle} from '@remotion/bundler';
import {renderMedia, selectComposition} from '@remotion/renderer';
import {encodeVariants} from './encode.mjs';
import {toPresentationProps} from './job-props.mjs';
import {callRenderApi} from './render-api.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const jobsPublicDir = join(root, 'public', 'jobs');
const jobsOutDir = join(root, 'out', 'jobs');
const MAX_PHOTO_BYTES = 6 * 1024 * 1024;
const require = createRequire(import.meta.url);

const log = (message) => console.log(`[rendu] ${message}`);

/** Format d'une image, d'après ses premiers octets. */
const imageKind = (bytes) => {
  if (bytes.length > 8 && bytes[0] === 0x89 && bytes.toString('ascii', 1, 4) === 'PNG') return 'png';
  if (bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'jpg';
  if (bytes.length > 12 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') {
    return 'webp';
  }
  return null;
};

/**
 * Vrai pour une photo détourée : le haut de l'image (de part et d'autre de
 * la tête) est transparent. Les épaules d'un joueur détouré touchent souvent
 * les coins du bas : seuls les coins du haut, ou une part notable de pixels
 * transparents, font foi. Lit une vignette de 8 × 8 avec le ffmpeg de Remotion.
 */
const hasTransparentCorners = (file) =>
  new Promise((resolve) => {
    const dir = dirname(require.resolve('@remotion/compositor-linux-x64-gnu/package.json'));
    const child = spawn(
      join(dir, 'ffmpeg'),
      ['-hide_banner', '-loglevel', 'error', '-i', file, '-vf', 'scale=8:8:flags=area', '-f', 'image2pipe', '-c:v', 'rawvideo', '-pix_fmt', 'rgba', 'pipe:1'],
      {env: {...process.env, LD_LIBRARY_PATH: dir}, stdio: ['ignore', 'pipe', 'ignore']},
    );
    const chunks = [];
    child.stdout.on('data', (chunk) => chunks.push(chunk));
    child.on('error', () => resolve(false));
    // « close » et non « exit » : la sortie doit être entièrement lue.
    child.on('close', (code) => {
      const pixels = Buffer.concat(chunks);
      if (code !== 0 || pixels.length < 256) return resolve(false);
      const alphaAt = (index) => pixels[index * 4 + 3];
      const topCorners = alphaAt(0) < 160 && alphaAt(7) < 160;
      let transparent = 0;
      for (let index = 0; index < 64; index += 1) {
        if (alphaAt(index) < 128) transparent += 1;
      }
      resolve(topCorners || transparent >= 10);
    });
  });

/** Télécharge une photo ; une photo illisible laisse place aux initiales. */
const downloadPhoto = async (url, jobId, index) => {
  if (!url) return null;
  try {
    const response = await fetch(url, {signal: AbortSignal.timeout(20_000)});
    if (!response.ok) return null;
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length === 0 || bytes.length > MAX_PHOTO_BYTES) return null;
    const kind = imageKind(bytes);
    if (!kind) return null;
    const relative = `jobs/${jobId}/${index}.${kind}`;
    const file = join(root, 'public', relative);
    mkdirSync(dirname(file), {recursive: true});
    writeFileSync(file, bytes);
    const alpha = kind === 'jpg' ? false : await hasTransparentCorners(file);
    return {src: relative, alpha};
  } catch {
    return null;
  }
};

const uploadFile = async (url, file) => {
  const response = await fetch(url, {
    method: 'PUT',
    headers: {
      'Content-Type': 'video/mp4',
      // Le chemin contient l'empreinte : un fichier ne change jamais.
      'Cache-Control': 'max-age=31536000',
      'x-upsert': 'true',
    },
    body: readFileSync(file),
  });
  if (!response.ok) throw new Error(`Dépôt refusé (${response.status})`);
};

const main = async () => {
  const {jobs} = await callRenderApi('claim', {limit: 2});
  if (!Array.isArray(jobs) || jobs.length === 0) {
    log('Rien à fabriquer.');
    return;
  }
  log(`${jobs.length} vidéo(s) réservée(s).`);

  rmSync(jobsPublicDir, {recursive: true, force: true});
  const prepared = [];
  for (const job of jobs) {
    const players = Array.isArray(job.payload?.players) ? job.payload.players : [];
    const photos = await Promise.all(
      players.map((player, index) => downloadPhoto(player.photo_url, job.id, index)),
    );
    log(`${job.id} : ${photos.filter(Boolean).length}/${players.length} photos, ${photos.filter((p) => p?.alpha).length} détourées.`);
    prepared.push({job, props: toPresentationProps(job.payload ?? {}, photos)});
  }

  // Les photos doivent être en place avant l'assemblage : il copie public/.
  const serveUrl = await bundle({entryPoint: join(root, 'src', 'index.ts')});

  let failures = 0;
  for (const {job, props} of prepared) {
    const started = Date.now();
    try {
      if (props.players.length === 0) throw new Error('Aucun titulaire');
      const composition = await selectComposition({
        serveUrl,
        id: 'LineupPresentation',
        inputProps: props,
      });
      const workDir = join(jobsOutDir, job.id);
      mkdirSync(workDir, {recursive: true});
      const master = join(workDir, 'master.mp4');
      await renderMedia({
        composition,
        serveUrl,
        codec: 'h264',
        outputLocation: master,
        inputProps: props,
        crf: 12,
        pixelFormat: 'yuv420p',
        imageFormat: 'jpeg',
        jpegQuality: 92,
        logLevel: 'error',
      });
      const files = await encodeVariants(master, workDir, 'video');
      const {uploads} = await callRenderApi('uploads', {
        match_id: job.match_id,
        fingerprint: job.fingerprint,
      });
      for (const variant of ['1080', '720']) {
        await uploadFile(uploads[variant].url, files[variant].path);
      }
      await callRenderApi('complete', {
        job_id: job.id,
        match_id: job.match_id,
        fingerprint: job.fingerprint,
        duration_ms: Math.round((composition.durationInFrames / composition.fps) * 1000),
      });
      log(`${job.id} : prête en ${Math.round((Date.now() - started) / 1000)} s (${files['1080'].bytes} / ${files['720'].bytes} octets).`);
    } catch (error) {
      failures += 1;
      const message = error instanceof Error ? error.message : 'Échec du rendu';
      log(`${job.id} : échec.`);
      await callRenderApi('fail', {job_id: job.id, error: message}).catch(() => undefined);
    }
  }

  rmSync(jobsPublicDir, {recursive: true, force: true});
  rmSync(jobsOutDir, {recursive: true, force: true});
  if (failures > 0) process.exitCode = 1;
};

await main();
