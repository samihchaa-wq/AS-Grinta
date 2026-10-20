// Logo AS La Grinta : le « ballon occitan » (croix occitane épousant le ballon)
// + le nom du club.
// Usage : node logo.js --variant=icon|maskable|mark|logo-dark|logo-light --font=Barlow-Condensed-BlackItalic.ttf [--embed]
//   icon       : icône d'application plein cadre (carré, sans bordure de blason)
//   maskable   : même icône, contenu resserré dans la zone sûre d'Android
//   mark       : symbole seul plein cadre, pour les très petites tailles (onglet)
//   logo-dark  : logo détouré, texte blanc (pour fond sombre)
//   logo-light : logo détouré, texte bleu nuit (pour fond clair)
// Police : Barlow Condensed Black Italic (Google Fonts, licence OFL).
const fs = require('fs');
const { emblem } = require('./emblem');

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, '').split('=');
    return [k, v === undefined ? true : v];
  })
);
const variant = args.variant || 'icon';
const font = args.font;
const fontSrc = font ? (args.embed ? `data:font/ttf;base64,${fs.readFileSync(font).toString('base64')}` : `file://${font}`) : '';

const GOLD = '#E7B850';
const NAVY = '#0A1540';
const S = 1024;

// Bandes du maillot (proportions du blason d'origine), en bleu clair ton sur ton.
function stripes(width, height) {
  const w = [55, 54, 69, 170, 67, 55, 57];
  const tot = w.reduce((a, b) => a + b, 0);
  let x = 0;
  let out = '';
  w.forEach((ww, i) => {
    const px = (ww / tot) * width;
    if (i % 2) out += `<rect x="${x.toFixed(1)}" y="0" width="${px.toFixed(1)}" height="${height}" fill="url(#stripe)"/>`;
    x += px;
  });
  return out;
}

function wordmark({ y, size, color, shadow }) {
  const t = (fill, dy, extra = '') => `<text x="512" y="${y + dy}" fill="${fill}" ${extra}>AS LA GRINTA</text>`;
  return `<g font-family="Word" font-size="${size}" text-anchor="middle" letter-spacing="2">
      ${shadow ? t('#020A2A', 8, 'opacity="0.6" filter="url(#txtShadow)"') : ''}
      ${t(color, 0)}
    </g>
    <g fill="${GOLD}">
      <rect x="330" y="${y + 44}" width="90" height="6" rx="3"/><rect x="604" y="${y + 44}" width="90" height="6" rx="3"/>
      <text x="516" y="${y + 66}" font-family="Word" font-size="52" letter-spacing="10" text-anchor="middle">2020</text>
    </g>`;
}

const defsCommon = `
  <style>${font ? `@font-face{font-family:Word;src:url(${fontSrc})}` : ''}</style>
  <radialGradient id="bg" cx="0.5" cy="0.32" r="0.85"><stop offset="0" stop-color="#2160F0"/><stop offset="0.5" stop-color="#0B36BF"/><stop offset="1" stop-color="#03135A"/></radialGradient>
  <linearGradient id="stripe" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3A74FF" stop-opacity="0.38"/><stop offset="1" stop-color="#3A74FF" stop-opacity="0.16"/></linearGradient>
  <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#9CC2FF" stop-opacity="0.55"/><stop offset="1" stop-color="#9CC2FF" stop-opacity="0"/></radialGradient>
  <radialGradient id="vig" cx="0.5" cy="0.45" r="0.75"><stop offset="0.55" stop-color="#020A2A" stop-opacity="0"/><stop offset="1" stop-color="#020A2A" stop-opacity="0.55"/></radialGradient>
  <linearGradient id="bottomFade" x1="0" y1="0" x2="0" y2="1"><stop offset="0.6" stop-color="#03114F" stop-opacity="0"/><stop offset="0.85" stop-color="#03114F" stop-opacity="0.92"/></linearGradient>
  <filter id="txtShadow" x="-10%" y="-30%" width="120%" height="160%"><feGaussianBlur stdDeviation="8"/></filter>`;

function background({ withText }) {
  return `<rect width="${S}" height="${S}" fill="url(#bg)"/>
    ${stripes(S, S)}
    ${withText ? `<rect width="${S}" height="${S}" fill="url(#bottomFade)"/>` : ''}
    <rect width="${S}" height="${S}" fill="url(#vig)"/>`;
}

let defs = defsCommon;
let body = '';
let viewW = S;
let viewH = S;

if (variant === 'icon' || variant === 'maskable') {
  const e = emblem({ R: 300 });
  defs += e.defs;
  const k = variant === 'maskable' ? 0.8 : 1;
  body = `${background({ withText: true })}
    <g transform="translate(512 512) scale(${k}) translate(-512 -512)">
      <circle cx="512" cy="410" r="510" fill="url(#glow)"/>
      <g transform="translate(512 410)">${e.body}</g>
      ${wordmark({ y: 868, size: 150, color: '#FFFFFF', shadow: true })}
    </g>`;
} else if (variant === 'mark') {
  const e = emblem({ R: 400 });
  defs += e.defs;
  body = `${background({ withText: false })}
    <circle cx="512" cy="512" r="560" fill="url(#glow)"/>
    <g transform="translate(512 512)">${e.body}</g>`;
} else {
  // logo détouré : symbole + nom, fond transparent
  const e = emblem({ R: 300, shadow: variant === 'logo-dark' ? 0.6 : 0.28 });
  defs += e.defs;
  viewH = 1000;
  const dark = variant === 'logo-dark';
  body = `<g transform="translate(512 320)">${e.body}</g>
    ${wordmark({ y: 848, size: 150, color: dark ? '#FFFFFF' : NAVY, shadow: false })}`;
}

const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${viewW} ${viewH}" width="${viewW}" height="${viewH}">
<defs>${defs}</defs>
${body}
</svg>`;
process.stdout.write(svg);
