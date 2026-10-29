import {useEffect, useState} from 'react';
import {cancelRender, continueRender, delayRender, staticFile} from 'remotion';
import {fonts} from './theme.ts';

const oswaldWeights: [string, string][] = [
  ['300', 'Oswald-Light.ttf'],
  ['400', 'Oswald-Regular.ttf'],
  ['500', 'Oswald-Medium.ttf'],
  ['700', 'Oswald-Bold.ttf'],
];

// Plages Unicode de @fontsource/roboto (latin et latin étendu).
const robotoSubsets: [string, string][] = [
  [
    'latin',
    'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD',
  ],
  [
    'latin-ext',
    'U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,U+0308,U+0329,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C0,U+2113,U+2C60-2C7F,U+A720-A7FF',
  ],
];

let loading: Promise<void> | null = null;

const loadAll = (): Promise<void> => {
  loading ??= (async () => {
    const faces = [
      ...oswaldWeights.map(
        ([weight, file]) =>
          new FontFace(fonts.display, `url(${staticFile(`fonts/${file}`)})`, {
            weight,
          }),
      ),
      // Les prénoms de l'écran Compo s'affichent en Roboto : la dernière
      // image de la vidéo doit les écrire avec la même police.
      ...robotoSubsets.map(
        ([subset, range]) =>
          new FontFace(fonts.app, `url(${staticFile(`fonts/Roboto-${subset}-400.woff2`)})`, {
            weight: '400',
            unicodeRange: range,
          }),
      ),
    ];
    await Promise.all(faces.map((face) => face.load()));
    faces.forEach((face) => document.fonts.add(face));
  })();
  return loading;
};

/**
 * Vrai une fois les polices chargées. Le rendu de chaque image attend ce
 * moment : une mesure de texte faite avec une police de secours donnerait
 * des noms mal ajustés.
 */
export const useFontsReady = (): boolean => {
  const [ready, setReady] = useState(false);
  const [handle] = useState(() => delayRender('Chargement des polices'));
  useEffect(() => {
    loadAll()
      .then(() => {
        setReady(true);
        continueRender(handle);
      })
      // Sans police, la vidéo ne serait pas fidèle : on préfère échouer.
      .catch((error: unknown) => cancelRender(error));
  }, [handle]);
  return ready;
};
