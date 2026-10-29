// Encodages de diffusion, à partir du rendu maître.
//
// H.264 High, 4:2:0, sans piste son, index en tête de fichier (« faststart ») :
// la lecture commence avant la fin du téléchargement, sur iPhone comme sur
// Android. Deux tailles : 1080 × 1920 pour les bonnes connexions, 720 × 1280
// pour les connexions lentes ou le mode économie de données.
import {spawn} from 'node:child_process';
import {statSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname, join} from 'node:path';

const require = createRequire(import.meta.url);

/** ffmpeg livré avec Remotion : même binaire en local et sur GitHub. */
const ffmpegDir = () =>
  dirname(require.resolve('@remotion/compositor-linux-x64-gnu/package.json'));

export const runFfmpeg = (args) =>
  new Promise((resolve, reject) => {
    const dir = ffmpegDir();
    const child = spawn(join(dir, 'ffmpeg'), ['-hide_banner', '-loglevel', 'error', '-y', ...args], {
      env: {...process.env, LD_LIBRARY_PATH: dir},
      stdio: ['ignore', 'inherit', 'inherit'],
    });
    child.on('error', reject);
    child.on('exit', (code) =>
      code === 0 ? resolve() : reject(new Error(`ffmpeg a échoué (code ${code})`)),
    );
  });

export const variants = [
  {name: '1080', width: 1080, height: 1920, crf: 21, maxrate: '4500k', bufsize: '9000k', level: '4.1'},
  {name: '720', width: 720, height: 1280, crf: 23, maxrate: '2200k', bufsize: '4400k', level: '3.1'},
];

export const encodeVariants = async (master, outDir, base) => {
  const files = {};
  for (const v of variants) {
    const output = join(outDir, `${base}-${v.name}.mp4`);
    await runFfmpeg([
      '-i', master,
      '-an',
      '-vf', `scale=${v.width}:${v.height}:flags=lanczos`,
      '-c:v', 'libx264',
      '-preset', 'slow',
      '-profile:v', 'high',
      '-level', v.level,
      '-crf', String(v.crf),
      '-maxrate', v.maxrate,
      '-bufsize', v.bufsize,
      '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart',
      '-tag:v', 'avc1',
      output,
    ]);
    files[v.name] = {path: output, bytes: statSync(output).size, width: v.width, height: v.height};
  }
  return files;
};
