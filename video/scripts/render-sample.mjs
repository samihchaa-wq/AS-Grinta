// Rend l'aperçu avec la composition d'exemple (silhouettes, prénoms fictifs).
//
//   node scripts/render-sample.mjs                → out/apercu.mp4 (+ 720p)
//   node scripts/render-sample.mjs --stills 0,90  → images fixes de contrôle
import {mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {bundle} from '@remotion/bundler';
import {renderMedia, renderStill, selectComposition} from '@remotion/renderer';
import {encodeVariants} from './encode.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'out');
mkdirSync(outDir, {recursive: true});

const stillsArg = process.argv.indexOf('--stills');
const stills =
  stillsArg >= 0 ? process.argv[stillsArg + 1].split(',').map((v) => Number(v)) : null;

const serveUrl = await bundle({entryPoint: join(root, 'src', 'index.ts')});
const composition = await selectComposition({serveUrl, id: 'LineupPresentation'});

if (stills) {
  for (const frame of stills) {
    const output = join(outDir, `still-${String(frame).padStart(3, '0')}.png`);
    await renderStill({composition, serveUrl, frame, output, imageFormat: 'png'});
    console.log(output);
  }
} else {
  const master = join(outDir, 'apercu-master.mp4');
  const started = Date.now();
  await renderMedia({
    composition,
    serveUrl,
    codec: 'h264',
    outputLocation: master,
    crf: 12,
    pixelFormat: 'yuv420p',
    imageFormat: 'jpeg',
    jpegQuality: 92,
  });
  console.log(`Rendu en ${((Date.now() - started) / 1000).toFixed(1)} s`);
  const files = await encodeVariants(master, outDir, 'apercu');
  console.log(files);
}
