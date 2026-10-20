// Icône d'application AS La Grinta, plein cadre (les bords de l'icône remplacent
// la bordure du blason).
// Usage : node make_svg.js [--maskable] [--cross=right|center] [--font800=path] [--embed]
// Police : Montserrat ExtraBold (Google Fonts, licence OFL), passée avec --font800=chemin.ttf ;
// --embed l'intègre dans le SVG pour qu'il s'affiche partout sans installation.
const fs = require('fs');
const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, '').split('=');
    return [k, v === undefined ? true : v];
  })
);
const S = 1024;
const maskable = !!args.maskable;
const crossPos = args.cross || 'right';

const C = {
  blueHi: '#1E4FE0',
  blue: '#0A36BE',
  blueLo: '#041C78',
  gold: '#DCAE45',
  goldHi: '#F2CF72',
  goldLo: '#A97A22',
  goldDeep: '#7E5B16',
  navy: '#0A1540',
  navyDeep: '#030A26',
  white: '#FFFFFF',
};

// ---------------------------------------------------------------- outils
const f = (n) => Number(n.toFixed(2));
const norm = (p) => {
  const l = Math.hypot(...p);
  return p.map((c) => c / l);
};
const lerp = (p, q, t) => p.map((c, i) => c + (q[i] - c) * t);
const dot = (a, b) => a.reduce((s, c, i) => s + c * b[i], 0);
const mix = (h1, h2, t) => {
  const a = h1.match(/\w\w/g).map((x) => parseInt(x, 16));
  const b = h2.match(/\w\w/g).map((x) => parseInt(x, 16));
  return '#' + a.map((c, i) => Math.round(c + (b[i] - c) * Math.min(1, Math.max(0, t))).toString(16).padStart(2, '0')).join('');
};

// ---------------------------------------------------------------- mise en page
const L = {
  cross: crossPos === 'center' ? { x: 512, y: 173, size: 286, rot: 0 } : { x: 772, y: 150, size: 300, rot: 18 },
  band: { x0: 92, x1: 932, top: 332, h: 150, arch: 30 },
  tailDrop: 44,
  tailInset: 44,
  tailEnd: 14,
  year: { y: 558 },
  ball: { x: 512, y: 850, r: 250 },
};

// Bandes : proportions mesurées sur le blason d'origine (bleu, or, bleu, or large, bleu, or, bleu).
const stripeWidths = [55, 54, 69, 170, 67, 55, 57];
const stripes = (() => {
  const total = stripeWidths.reduce((a, b) => a + b, 0);
  let x = 0;
  const out = [];
  stripeWidths.forEach((w, i) => {
    const ww = (w / total) * S;
    if (i % 2 === 1) out.push({ x, w: ww });
    x += ww;
  });
  return out;
})();

// ---------------------------------------------------------------- croix occitane
// Croix « vidée, cléchée et pommetée de 12 pièces » : chaque branche se termine
// par trois pointes surmontées d'une boule (deux coins + une pointe au centre).
// Coordonnées d'une branche (vers le haut), en unités du rayon D (centre → pointe).
function occitanCross({ x, y, size, rot }) {
  const D = size / 2.25;
  const P = (pt) => `${f(pt[0] * D)} ${f(pt[1] * D)}`;
  const turn = (pt, k) => {
    let [px, py] = pt;
    for (let i = 0; i < k; i++) [px, py] = [-py, px];
    return [px, py];
  };
  const mirror = ([px, py]) => [-px, py];
  // contour extérieur : demi-branche gauche, du creux entre deux branches jusqu'à la pointe centrale
  const outerHalf = [
    ['C', [-0.202, -0.444], [-0.351, -0.639], [-0.408, -0.696]],
    ['L', [-0.442, -0.741]],
    ['L', [-0.391, -0.749]],
    ['C', [-0.2, -0.779], [-0.087, -0.89], [-0.033, -0.958]],
    ['L', [0, -1.0]],
  ];
  const outerJoin = [-0.161, -0.161];
  // contour intérieur (le vide qui laisse voir le fond)
  const innerHalf = [
    ['C', [-0.058, -0.197], [-0.094, -0.49], [-0.252, -0.679]],
    ['C', [-0.252, -0.679], [-0.12, -0.708], [0, -0.837]],
  ];
  const innerJoin = [-0.05, -0.05];

  // parcourt une branche complète : moitié gauche puis moitié droite en miroir (sens inverse)
  const armSegments = (half, join) => {
    const pts = [join];
    const segs = [];
    let prev = join;
    for (const [cmd, ...ps] of half) { segs.push([cmd, ...ps]); prev = ps[ps.length - 1]; }
    // miroir : on refait le chemin à l'envers de l'autre côté
    const rev = [];
    let cur = mirror(prev);
    const points = [join, ...half.map((h) => h[h.length - 1])];
    for (let i = half.length - 1; i >= 0; i--) {
      const [cmd, ...ps] = half[i];
      const startPt = mirror(points[i]);
      if (cmd === 'C') rev.push(['C', mirror(ps[1]), mirror(ps[0]), startPt]);
      else rev.push(['L', startPt]);
    }
    return [...segs, ...rev];
  };
  const loop = (half, join) => {
    let d = `M ${P(join)} `;
    for (let k = 0; k < 4; k++) {
      for (const [cmd, ...ps] of armSegments(half, join)) {
        d += `${cmd} ${ps.map((pt) => P(turn(pt, k))).join(' ')} `;
      }
    }
    return d + 'Z';
  };
  const band = `${loop(outerHalf, outerJoin)} ${loop(innerHalf, innerJoin)}`;
  const pommels = [];
  for (let k = 0; k < 4; k++) for (const pt of [[0, -1.041], [-0.47, -0.775], [0.47, -0.775]]) pommels.push(turn(pt, k));
  const shape = (fill) =>
    `<path d="${band}" fill="${fill}" fill-rule="evenodd" stroke="${fill}" stroke-width="${f(0.05 * D)}" stroke-linejoin="round"/>` +
    pommels.map((pt) => `<circle cx="${f(pt[0] * D)}" cy="${f(pt[1] * D)}" r="${f(0.096 * D)}" fill="${fill}"/>`).join('');
  return `<g transform="translate(${x} ${y}) rotate(${rot})">
    <g filter="url(#softShadow)" opacity="0.55" transform="translate(${f(size * 0.02)} ${f(size * 0.045)})">${shape(C.navyDeep)}</g>
    <g transform="translate(${f(size * 0.007)} ${f(size * 0.016)})">${shape(C.goldDeep)}</g>
    <g filter="url(#bevel)">${shape('url(#goldGrad)')}</g>
  </g>`;
}

// ---------------------------------------------------------------- ballon
// Icosaèdre tronqué projeté sur la sphère, éclairé face par face.
function ball({ x, y, r: R }) {
  const phi = (1 + Math.sqrt(5)) / 2;
  const V = [];
  for (const a of [-1, 1]) for (const b of [-phi, phi]) V.push([0, a, b], [a, b, 0], [b, 0, a]);
  const near = (p, q) => Math.abs(Math.hypot(...p.map((c, i) => c - q[i])) - 2) < 1e-6;
  const nbrs = V.map((v, i) => V.map((_, j) => j).filter((j) => j !== i && near(v, V[j])));

  // Orientation : un pentagone presque de face, légèrement incliné.
  const rad = (d) => (d * Math.PI) / 180;
  const front = norm(V[0]);
  const rotate = (p) => {
    // aligne « front » sur +z
    let [px, py, pz] = p;
    const ay = Math.atan2(front[0], front[2]);
    let c = Math.cos(-ay), s = Math.sin(-ay);
    [px, pz] = [px * c + pz * s, -px * s + pz * c];
    const f2 = [front[0] * Math.cos(-ay) + front[2] * Math.sin(-ay), front[1], -front[0] * Math.sin(-ay) + front[2] * Math.cos(-ay)];
    const ax = Math.atan2(f2[1], f2[2]);
    c = Math.cos(ax); s = Math.sin(ax);
    [py, pz] = [py * c - pz * s, py * s + pz * c];
    for (const [axis, deg] of [['x', -16], ['y', 14], ['z', 10]]) {
      c = Math.cos(rad(deg)); s = Math.sin(rad(deg));
      if (axis === 'x') [py, pz] = [py * c - pz * s, py * s + pz * c];
      if (axis === 'y') [px, pz] = [px * c + pz * s, -px * s + pz * c];
      if (axis === 'z') [px, py] = [px * c - py * s, px * s + py * c];
    }
    return [px, py, pz];
  };

  const faces = [];
  V.forEach((v, i) => faces.push({ pts: nbrs[i].map((j) => lerp(v, V[j], 1 / 3)), dark: true }));
  for (let i = 0; i < 12; i++)
    for (const j of nbrs[i])
      for (const k of nbrs[i]) {
        if (!(i < j && j < k) || !nbrs[j].includes(k)) continue;
        const [a, b, c] = [V[i], V[j], V[k]];
        faces.push({ pts: [lerp(a, b, 1 / 3), lerp(a, b, 2 / 3), lerp(b, c, 1 / 3), lerp(b, c, 2 / 3), lerp(c, a, 1 / 3), lerp(c, a, 2 / 3)], dark: false });
      }

  const light = norm([-0.5, 0.62, 0.62]);
  const paths = [];
  for (const face of faces) {
    const cen = norm(face.pts.reduce((acc, p) => acc.map((c, i) => c + p[i]), [0, 0, 0]));
    const u = norm(face.pts[0].map((c, i) => c - cen[i] * dot(face.pts[0], cen)));
    const w = [cen[1] * u[2] - cen[2] * u[1], cen[2] * u[0] - cen[0] * u[2], cen[0] * u[1] - cen[1] * u[0]];
    const ang = (p) => Math.atan2(dot(p, w), dot(p, u));
    face.pts.sort((p, q) => ang(p) - ang(q));
    const poly = [];
    const n = face.pts.length;
    // panneaux légèrement « gonflés » : sommets un peu rentrés pour arrondir les coutures
    for (let e = 0; e < n; e++) {
      const p = face.pts[e], q = face.pts[(e + 1) % n];
      for (let t = 0; t < 14; t++) poly.push(rotate(norm(lerp(p, q, t / 14))));
    }
    if (Math.max(...poly.map((p) => p[2])) <= 0) continue;
    for (const p of poly) if (p[2] < 0) {
      const l = Math.hypot(p[0], p[1]);
      p[0] /= l; p[1] /= l; p[2] = 0;
    }
    const rc = rotate(cen);
    const lam = Math.max(0, dot(rc, light));
    const fill = face.dark ? mix('#020822', '#26356E', lam * 0.85) : mix('#B3BDD0', '#FFFFFF', Math.pow(lam, 0.55) * 1.12);
    const d = poly.map((p, i) => `${i ? 'L' : 'M'}${f(p[0] * R)} ${f(-p[1] * R)}`).join('') + 'Z';
    paths.push({ z: rc[2], d, fill });
  }
  paths.sort((a, b) => a.z - b.z);
  const faceSvg = paths
    .map((p) => `<path d="${p.d}" fill="${p.fill}" stroke="#0B1336" stroke-width="${f(R * 0.02)}" stroke-linejoin="round"/>`)
    .join('');

  return `<g transform="translate(${x} ${y})">
    <ellipse cx="0" cy="${f(R * 0.1)}" rx="${f(R * 1.05)}" ry="${f(R * 1.05)}" fill="${C.navyDeep}" opacity="0.55" filter="url(#bigShadow)"/>
    <circle r="${f(R * 1.045)}" fill="#E9EEF6"/>
    <g clip-path="url(#ballClip)">
      <circle r="${R}" fill="#FFFFFF"/>
      ${faceSvg}
      <circle r="${R}" fill="url(#ballShade)"/>
      <ellipse cx="${f(-R * 0.36)}" cy="${f(-R * 0.42)}" rx="${f(R * 0.42)}" ry="${f(R * 0.26)}" transform="rotate(-38 ${f(-R * 0.36)} ${f(-R * 0.42)})" fill="#FFFFFF" opacity="0.32" filter="url(#glow)"/>
    </g>
    <circle r="${R}" fill="none" stroke="${C.navyDeep}" stroke-width="${f(R * 0.032)}"/>
  </g>`;
}

// ---------------------------------------------------------------- banderole
function ribbon() {
  const { x0, x1, top, h, arch } = L.band;
  const cx = (x0 + x1) / 2;
  const yAt = (base, x) => {
    // quadratique : bords à base+arch, milieu à base
    const t = (x - x0) / (x1 - x0);
    return base + arch * (1 - 4 * t * (1 - t)) * 1;
  };
  const panelTop = `M ${x0} ${top + arch} Q ${cx} ${top - arch} ${x1} ${top + arch}`;
  const panel = `${panelTop} L ${x1} ${top + h + arch} Q ${cx} ${top + h - arch} ${x0} ${top + h + arch} Z`;
  const pt = top + arch;
  const pb = top + h + arch;
  const dy = L.tailDrop;
  const ins = L.tailInset;
  const e = L.tailEnd;
  const notch = 30;
  // pans arrière (gauche puis droite), avec queue d'aronde près du bord
  const tailL = `M ${x0 + ins} ${pt + dy} L ${e} ${pt + dy} L ${e + notch} ${pt + dy + h / 2} L ${e} ${pb + dy} L ${x0 + ins} ${pb + dy} Z`;
  const tailR = `M ${x1 - ins} ${pt + dy} L ${S - e} ${pt + dy} L ${S - e - notch} ${pt + dy + h / 2} L ${S - e} ${pb + dy} L ${x1 - ins} ${pb + dy} Z`;
  const foldL = `M ${x0} ${pb} L ${x0 + ins} ${pb} L ${x0 + ins} ${pb + dy} Z`;
  const foldR = `M ${x1} ${pb} L ${x1 - ins} ${pb} L ${x1 - ins} ${pb + dy} Z`;
  // ligne de base du texte, parallèle à la courbe de la banderole
  const base = top + h / 2 + 34;
  const textArc = `M ${x0 - 60} ${base + arch + 6} Q ${cx} ${base - arch - 6} ${x1 + 60} ${base + arch + 6}`;
  return `
    <g filter="url(#bigShadow)" opacity="0.6"><path d="${panel}" fill="${C.navyDeep}" transform="translate(0 16)"/><path d="${tailL}" fill="${C.navyDeep}" transform="translate(0 12)"/><path d="${tailR}" fill="${C.navyDeep}" transform="translate(0 12)"/></g>
    <path d="${tailL}" fill="url(#tailGrad)"/>
    <path d="${tailR}" fill="url(#tailGrad)"/>
    <path d="${foldL}" fill="#5E6C86"/>
    <path d="${foldR}" fill="#5E6C86"/>
    <path d="${panel}" fill="url(#bandGrad)"/>
    <path d="${panel}" fill="none" stroke="${C.navy}" stroke-opacity="0.18" stroke-width="3"/>
    <path d="${panelTop}" fill="none" stroke="#FFFFFF" stroke-width="4" transform="translate(0 4)" opacity="0.9"/>
    <path id="textArc" d="${textArc}" fill="none"/>
    <text font-family="GrintaTitle" font-weight="800" font-size="104" fill="${C.navy}" letter-spacing="1" text-anchor="middle">
      <textPath href="#textArc" startOffset="50%">AS LA GRINTA</textPath>
    </text>`;
}

// ---------------------------------------------------------------- assemblage
function content() {
  const stripeTop = L.band.top + 60;
  const stripeSvg = stripes
    .map((s) => `<rect x="${f(s.x)}" y="${stripeTop}" width="${f(s.w)}" height="${S - stripeTop + 300}" fill="url(#stripeGrad)"/>
      <rect x="${f(s.x)}" y="${stripeTop}" width="3" height="${S}" fill="${C.goldLo}" opacity="0.7"/>
      <rect x="${f(s.x + s.w - 3)}" y="${stripeTop}" width="3" height="${S}" fill="${C.goldLo}" opacity="0.7"/>`)
    .join('');
  return `
    ${stripeSvg}
    <rect width="${S}" height="${S}" fill="url(#vignette)"/>
    ${occitanCross(L.cross)}
    ${ribbon()}
    <text x="${S / 2}" y="${L.year.y}" font-family="GrintaTitle" font-weight="800" font-size="62" fill="${C.navy}" text-anchor="middle" letter-spacing="3">2020</text>
    ${ball(L.ball)}`;
}

const k = maskable ? 0.8 : 1;
const fontFace = (name, weight, path) => {
  if (!path) return '';
  const src = args.embed ? `data:font/ttf;base64,${fs.readFileSync(path).toString('base64')}` : `file://${path}`;
  return `@font-face{font-family:${name};font-weight:${weight};src:url(${src})}`;
};

const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${S} ${S}" width="${S}" height="${S}">
  <defs>
    <style>${fontFace('GrintaTitle', 800, args.font800)}</style>
    <radialGradient id="bg" cx="0.5" cy="0.18" r="0.95">
      <stop offset="0" stop-color="${C.blueHi}"/><stop offset="0.55" stop-color="${C.blue}"/><stop offset="1" stop-color="${C.blueLo}"/>
    </radialGradient>
    <radialGradient id="vignette" cx="0.5" cy="0.42" r="0.78">
      <stop offset="0.6" stop-color="${C.navyDeep}" stop-opacity="0"/><stop offset="1" stop-color="${C.navyDeep}" stop-opacity="0.38"/>
    </radialGradient>
    <linearGradient id="stripeGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${C.goldLo}"/><stop offset="0.12" stop-color="${C.gold}"/><stop offset="1" stop-color="#C99B3C"/>
    </linearGradient>
    <linearGradient id="goldGrad" x1="-150" y1="-150" x2="150" y2="150" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="${C.goldHi}"/><stop offset="0.5" stop-color="${C.gold}"/><stop offset="1" stop-color="${C.goldLo}"/>
    </linearGradient>
    <linearGradient id="bandGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset="0.6" stop-color="#F3F5F9"/><stop offset="1" stop-color="#CBD3E0"/>
    </linearGradient>
    <linearGradient id="tailGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#C3CBD9"/><stop offset="1" stop-color="#8F9BB2"/>
    </linearGradient>
    <radialGradient id="ballShade" cx="0.36" cy="0.3" r="0.82">
      <stop offset="0.45" stop-color="${C.navyDeep}" stop-opacity="0"/><stop offset="0.85" stop-color="${C.navyDeep}" stop-opacity="0.22"/><stop offset="1" stop-color="${C.navyDeep}" stop-opacity="0.5"/>
    </radialGradient>
    <clipPath id="ballClip"><circle r="${L.ball.r}"/></clipPath>
    <filter id="softShadow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="6"/></filter>
    <filter id="bigShadow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="14"/></filter>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="16"/></filter>
    <filter id="bevel" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="4" result="blur"/>
      <feSpecularLighting in="blur" surfaceScale="4" specularConstant="0.8" specularExponent="26" lighting-color="#FFF6D8" result="spec">
        <feDistantLight azimuth="235" elevation="48"/>
      </feSpecularLighting>
      <feComposite in="spec" in2="SourceAlpha" operator="in" result="specIn"/>
      <feComposite in="SourceGraphic" in2="specIn" operator="arithmetic" k1="0" k2="1" k3="0.4" k4="0"/>
    </filter>
  </defs>
  <rect width="${S}" height="${S}" fill="url(#bg)"/>
  <g transform="translate(${S / 2} ${S / 2}) scale(${k}) translate(${-S / 2} ${-S / 2})">${content()}</g>
</svg>`;

process.stdout.write(svg);
