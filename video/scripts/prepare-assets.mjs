// Copie dans public/ les fichiers de marque déjà présents dans l'application
// (police Oswald, écusson) : le dépôt n'en garde qu'un seul exemplaire. La
// police Roboto, celle des prénoms de l'écran Compo sur le Web, vient d'un
// paquet npm figé : aucun téléchargement pendant le rendu.
import {copyFileSync, mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const repo = join(root, '..');
const publicDir = join(root, 'public');

mkdirSync(join(publicDir, 'fonts'), {recursive: true});
for (const weight of ['Light', 'Regular', 'Medium', 'Bold']) {
  copyFileSync(
    join(repo, 'assets', 'fonts', `Oswald-${weight}.ttf`),
    join(publicDir, 'fonts', `Oswald-${weight}.ttf`),
  );
}
for (const subset of ['latin', 'latin-ext']) {
  copyFileSync(
    join(root, 'node_modules', '@fontsource', 'roboto', 'files', `roboto-${subset}-400-normal.woff2`),
    join(publicDir, 'fonts', `Roboto-${subset}-400.woff2`),
  );
}
copyFileSync(
  join(repo, 'assets', 'images', 'as_grinta_logo.webp'),
  join(publicDir, 'crest.webp'),
);
